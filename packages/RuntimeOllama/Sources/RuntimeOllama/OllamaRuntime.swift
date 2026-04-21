import Foundation
import LLMCore

/// `LLMRuntime` backed by a local Ollama daemon at `http://127.0.0.1:11434`.
public final class OllamaRuntime: LLMRuntime {

    public let id = RuntimeOllama.id
    public let displayName = "Ollama · local daemon"

    private let client: OllamaClient

    public init(endpoint: URL = RuntimeOllama.defaultEndpoint,
                session: URLSession = .shared) {
        self.client = OllamaClient(endpoint: endpoint, session: session)
    }

    /// Testing seam — inject a preconfigured client.
    init(client: OllamaClient) {
        self.client = client
    }

    // MARK: - Availability

    public func isAvailable() async -> Bool {
        await client.isReachable()
    }

    // MARK: - Discovery

    public func discoverModels() async throws -> [ModelInfo] {
        let tags: OllamaDTO.TagsResponse
        do {
            tags = try await client.listTags()
        } catch let err as LLMRuntimeError {
            throw err
        } catch {
            throw LLMRuntimeError.unavailable("ollama unreachable: \(error)")
        }

        let loaded = (try? await client.listLoaded())?.models?.map(\.name) ?? []
        let loadedSet = Set(loaded)

        return tags.models.map { tag in
            let (family, variant) = Self.parseFamily(fromRawName: tag.name,
                                                    reportedFamily: tag.details?.family)
            return ModelInfo(
                id: "\(RuntimeOllama.id):\(tag.name)",
                rawName: tag.name,
                displayName: Self.humanize(tag.name, paramSize: tag.details?.parameter_size),
                runtimeId: RuntimeOllama.id,
                family: family,
                variant: variant,
                sizeBytes: tag.size,
                isLoaded: loadedSet.contains(tag.name),
                capabilities: .textOnly  // ModelRegistry upgrades this.
            )
        }
    }

    // MARK: - Pull

    public func pullModel(_ rawName: String) -> AsyncThrowingStream<PullProgress, Error> {
        let source = client.streamPull(
            OllamaDTO.PullRequestBody(model: rawName, stream: true)
        )
        return AsyncThrowingStream<PullProgress, Error> { continuation in
            let task = Task {
                do {
                    for try await chunk in source {
                        let progress = PullProgress(
                            status: chunk.status,
                            downloadedBytes: chunk.completed,
                            totalBytes: chunk.total,
                            digest: chunk.digest,
                            completed: chunk.status.lowercased().contains("success")
                        )
                        continuation.yield(progress)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Chat

    public func chat(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        // Build wire body up front so errors surface immediately.
        let body: OllamaDTO.ChatRequestBody
        do {
            body = try Self.toWireBody(request)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        let source = client.streamChat(body)

        return AsyncThrowingStream<ChatChunk, Error> { continuation in
            let task = Task {
                do {
                    var totalPrompt: Int? = nil
                    var totalEval: Int? = nil
                    var lastDoneReason: ChatChunk.FinishReason = .stop

                    for try await chunk in source {
                        if let msg = chunk.message {
                            if let text = msg.content, !text.isEmpty {
                                continuation.yield(.text(text))
                            }
                            if let calls = msg.tool_calls {
                                for call in calls {
                                    guard let fn = call.function,
                                          let name = fn.name else { continue }
                                    let argsData = (try? JSONEncoder().encode(fn.arguments)) ?? Data()
                                    continuation.yield(.toolCall(ToolCall(
                                        id: call.id ?? UUID().uuidString,
                                        toolId: name,
                                        argumentsJSON: argsData
                                    )))
                                }
                            }
                        }
                        if chunk.done == true {
                            totalPrompt = chunk.prompt_eval_count
                            totalEval = chunk.eval_count
                            if let reason = chunk.done_reason {
                                lastDoneReason = ChatChunk.FinishReason(rawValue: reason) ?? .stop
                            }
                        }
                    }

                    let usage = ChatChunk.Usage(
                        promptTokens: totalPrompt,
                        completionTokens: totalEval,
                        totalTokens: totalPrompt.flatMap { p in totalEval.map { p + $0 } },
                        latencyMs: nil
                    )
                    continuation.yield(.finish(reason: lastDoneReason, usage: usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    /// Convert an `LLMCore.ChatRequest` into Ollama's wire format. Image parts
    /// are base64-encoded; audio / video are dropped with a comment (Ollama
    /// itself doesn't yet take audio on /api/chat in April 2026 — when it
    /// does, we extend here).
    static func toWireBody(_ req: ChatRequest) throws -> OllamaDTO.ChatRequestBody {
        let messages = req.messages.map { msg -> OllamaDTO.ChatMessage in
            var content = ""
            var images: [String] = []
            for part in msg.parts {
                switch part {
                case .text(let s):
                    content += s
                case .image(let data, _):
                    images.append(data.base64EncodedString())
                case .audio, .video:
                    // Unsupported by current Ollama /api/chat; UI gates this
                    // at the modality-picker level. We silently drop.
                    continue
                }
            }
            return OllamaDTO.ChatMessage(
                role: msg.role.rawValue,
                content: content,
                images: images.isEmpty ? nil : images,
                tool_call_id: msg.toolCallId
            )
        }

        let options = OllamaDTO.ChatOptions(
            temperature: req.sampling.temperature,
            top_p: req.sampling.topP,
            top_k: req.sampling.topK,
            num_predict: req.sampling.maxTokens,
            stop: req.sampling.stop.isEmpty ? nil : req.sampling.stop
        )

        let tools = req.tools.isEmpty ? nil : req.tools.map { tool -> OllamaDTO.ToolSpec in
            let props = tool.parameters.properties.mapValues { p -> OllamaDTO.ToolSpec.PropertySpec in
                OllamaDTO.ToolSpec.PropertySpec(type: p.type, description: p.description, enum: p.enumValues)
            }
            return OllamaDTO.ToolSpec(
                type: "function",
                function: OllamaDTO.ToolSpec.FunctionSpec(
                    name: tool.id,
                    description: tool.description,
                    parameters: OllamaDTO.ToolSpec.ParametersSpec(
                        type: tool.parameters.type,
                        properties: props,
                        required: tool.parameters.required
                    )
                )
            )
        }

        // Strip the runtime prefix if the caller passed a fully-qualified id.
        let modelName: String
        if req.modelId.hasPrefix("\(RuntimeOllama.id):") {
            modelName = String(req.modelId.dropFirst(RuntimeOllama.id.count + 1))
        } else {
            modelName = req.modelId
        }

        return OllamaDTO.ChatRequestBody(
            model: modelName,
            messages: messages,
            stream: req.stream,
            options: options,
            tools: tools
        )
    }

    /// Parse family + variant from an Ollama tag like `gemma-4:e4b`.
    static func parseFamily(fromRawName raw: String,
                            reportedFamily: String?) -> (family: String, variant: String?) {
        let parts = raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let head = String(parts.first ?? "")
        let tail = parts.count > 1 ? String(parts[1]) : nil
        let family = reportedFamily?.isEmpty == false ? reportedFamily! : head
        return (family, tail)
    }

    static func humanize(_ raw: String, paramSize: String?) -> String {
        // "gemma-4:e4b" + "4.5B" → "Gemma 4 · E4B (4.5B)"
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        let base = parts.first?
            .replacingOccurrences(of: "-", with: " ")
            .capitalized ?? raw
        if parts.count > 1 {
            let variant = parts[1].uppercased()
            if let size = paramSize, !size.isEmpty {
                return "\(base) · \(variant) (\(size))"
            }
            return "\(base) · \(variant)"
        }
        return base
    }
}
