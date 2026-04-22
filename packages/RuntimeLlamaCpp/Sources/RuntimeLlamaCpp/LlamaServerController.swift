import Foundation

// MARK: - Public types

public enum LlamaServerState: Sendable, Equatable, CustomStringConvertible {
    case stopped
    case starting(modelName: String)
    case running(modelName: String)
    case crashed(reason: String)

    public var description: String {
        switch self {
        case .stopped:                return "stopped"
        case .starting(let n):        return "starting · \(n)"
        case .running(let n):         return "running · \(n)"
        case .crashed(let r):         return "crashed · \(r)"
        }
    }

    public var isActive: Bool {
        switch self {
        case .starting, .running: return true
        default:                  return false
        }
    }
}

public struct LlamaServerLaunchConfig: Sendable, Codable, Equatable {
    public var port: Int
    public var host: String
    public var contextSize: Int
    public var ngl: Int
    public var flashAttention: Bool
    public var quantizeKV: Bool
    public var extraArgs: [String]

    public init(port: Int = 8080,
                host: String = "127.0.0.1",
                contextSize: Int = 8192,
                ngl: Int = 99,
                flashAttention: Bool = true,
                quantizeKV: Bool = true,
                extraArgs: [String] = []) {
        self.port = port
        self.host = host
        self.contextSize = contextSize
        self.ngl = ngl
        self.flashAttention = flashAttention
        self.quantizeKV = quantizeKV
        self.extraArgs = extraArgs
    }

    public static let defaults = LlamaServerLaunchConfig()
}

// MARK: - Controller

/// Manages a single `llama-server` subprocess from inside the app.
///
///   1. `findBinary()` locates the binary (Homebrew paths + `which`)
///   2. `GGUFScanner.scan()` lists models on disk
///   3. `start(_:config:)` spawns the subprocess, polls `/v1/models` until
///      responsive, and transitions `state` from `.starting` → `.running`
///   4. `stop()` (or app quit) terminates the subprocess cleanly
///
/// Once `state == .running`, `LlamaCppRuntime` (the existing adapter)
/// auto-discovers the model on the next `ModelRegistry.scan()` — no extra
/// wiring required.
public final class LlamaServerController: ObservableObject, @unchecked Sendable {

    // MARK: - Published state

    @Published public private(set) var state: LlamaServerState = .stopped
    @Published public private(set) var discoveredGGUFs: [GGUFFile] = []
    @Published public private(set) var binaryURL: URL?
    /// Rolling log buffer — the last ~100 lines of llama-server's stdout/stderr.
    @Published public private(set) var log: [String] = []

    private var process: Process?
    private var readinessTask: Task<Void, Never>?
    private let maxLogLines = 200

    public init() {
        self.binaryURL = Self.findBinary()
    }

    // MARK: - Scanning

    public func rescanLocal() {
        discoveredGGUFs = GGUFScanner.scan()
        binaryURL = Self.findBinary()
    }

    // MARK: - Lifecycle

    public func start(_ gguf: GGUFFile,
                      config: LlamaServerLaunchConfig = .defaults) {
        #if !os(iOS) && !os(tvOS) && !os(watchOS)
        // Only tear down a previous subprocess if one is live. Calling
        // stop() unconditionally used to re-set state = .stopped and race
        // with the .starting assignment below, making start()s look like
        // they silently did nothing.
        if process != nil || state.isActive {
            stop()
        }

        guard let binary = binaryURL ?? Self.findBinary() else {
            state = .crashed(reason: "llama-server binary not found on PATH — brew install llama.cpp")
            return
        }
        self.binaryURL = binary

        var args: [String] = [
            "-m", gguf.url.path,
            "--host", config.host,
            "--port", String(config.port),
            "-c", String(config.contextSize),
            "-ngl", String(config.ngl)
        ]
        if let mmproj = gguf.companionMmproj {
            args.append(contentsOf: ["--mmproj", mmproj.path])
        }
        if config.flashAttention {
            // Newer llama.cpp (Apr 2026) requires an explicit on|off|auto
            // value for --flash-attn. Bare `--flash-attn` consumes the
            // next arg (`-ctk`) as its value and bails with
            //   "unknown value for --flash-attn: '-ctk'"
            // Past builds accepted the bare flag; "on" is compatible with
            // both.
            args.append(contentsOf: ["--flash-attn", "on"])
        }
        if config.quantizeKV {
            args.append(contentsOf: ["-ctk", "q8_0", "-ctv", "q8_0"])
        }
        args.append(contentsOf: config.extraArgs)

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = args

        // Capture both streams into the same pipe so the UI log is ordered.
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty,
                  let s = String(data: data, encoding: .utf8) else { return }
            for line in s.split(separator: "\n") where !line.isEmpty {
                self?.appendLog(String(line))
            }
        }

        proc.terminationHandler = { [weak self] p in
            handle.readabilityHandler = nil
            let status = p.terminationStatus
            DispatchQueue.main.async {
                guard let self else { return }
                if case .running = self.state, status == 0 {
                    self.state = .stopped
                } else if case .stopped = self.state {
                    // already cleared intentionally
                } else {
                    self.state = .crashed(reason: "exit code \(status)")
                }
            }
        }

        state = .starting(modelName: gguf.displayLabel)
        appendLog("→ \(binary.path) \(args.joined(separator: " "))")

        do {
            try proc.run()
            self.process = proc
        } catch {
            state = .crashed(reason: "failed to spawn: \(error.localizedDescription)")
            return
        }

        readinessTask = Task { [weak self] in
            await self?.waitForReadiness(config: config, model: gguf)
        }
        #else
        state = .crashed(reason: "llama-server spawn unsupported on this platform")
        #endif
    }

    public func stop() {
        readinessTask?.cancel()
        readinessTask = nil
        process?.terminate()
        process = nil
        // Sync main-hop: using DispatchQueue.main.async here raced with
        // start()'s synchronous `state = .starting` assignment — start()
        // calls stop() first, then sets .starting, then the queued
        // .stopped from stop() overwrites it back and the UI appears
        // "clicked, nothing happened". Set state immediately on main
        // regardless of caller context.
        setStateOnMain(.stopped)
    }

    private func setStateOnMain(_ new: LlamaServerState) {
        if Thread.isMainThread {
            self.state = new
        } else {
            DispatchQueue.main.sync { self.state = new }
        }
    }

    // MARK: - Readiness

    private func waitForReadiness(config: LlamaServerLaunchConfig,
                                  model: GGUFFile) async {
        // Poll /v1/models for up to 90 s. Weights + mmproj on Apple Silicon
        // usually take 10–30 s; 90 s is the timeout bail-out.
        let url = URL(string: "http://\(config.host):\(config.port)/v1/models")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0

        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            if Task.isCancelled { return }
            do {
                let (_, resp) = try await URLSession.shared.data(for: request)
                if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    await MainActor.run { [weak self] in
                        self?.state = .running(modelName: model.displayLabel)
                    }
                    return
                }
            } catch {
                // still booting
            }
            try? await Task.sleep(nanoseconds: 300_000_000) // 300 ms
        }
        await MainActor.run { [weak self] in
            self?.state = .crashed(reason: "didn't respond within 90 s")
        }
    }

    // MARK: - Log

    private func appendLog(_ line: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.log.append(line)
            if self.log.count > self.maxLogLines {
                self.log.removeFirst(self.log.count - self.maxLogLines)
            }
        }
    }

    // MARK: - Binary discovery

    public static func findBinary() -> URL? {
        #if !os(iOS) && !os(tvOS) && !os(watchOS)
        let candidates = [
            "/opt/homebrew/bin/llama-server",
            "/usr/local/bin/llama-server",
            "/opt/local/bin/llama-server"
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["llama-server"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                         encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : URL(fileURLWithPath: out)
        #else
        return nil
        #endif
    }
}
