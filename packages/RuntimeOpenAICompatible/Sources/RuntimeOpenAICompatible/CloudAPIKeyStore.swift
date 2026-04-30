import Foundation
#if canImport(Security)
import Security
#endif

public enum CloudAPIKeyStoreError: Error, Sendable, CustomStringConvertible {
    case keychain(OSStatus)
    case unsupportedPlatform

    public var description: String {
        switch self {
        case .keychain(let status):
            return "keychain error \(status)"
        case .unsupportedPlatform:
            return "keychain is unavailable on this platform"
        }
    }
}

/// Minimal Keychain wrapper for opt-in cloud provider API keys. Values are
/// never written to repo files or the app's JSON persistence store.
public struct CloudAPIKeyStore: Sendable, Hashable {
    public let service: String
    public let account: String
    public let environmentVariable: String

    public init(service: String,
                account: String,
                environmentVariable: String) {
        self.service = service
        self.account = account
        self.environmentVariable = environmentVariable
    }

    public static let deepSeek = CloudAPIKeyStore(
        service: "org.llmab.omega.cloud.deepseek",
        account: "api-key",
        environmentVariable: "DEEPSEEK_API_KEY"
    )

    public func hasAPIKey() -> Bool {
        readAPIKey()?.isEmpty == false
    }

    public func readAPIKey() -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return ProcessInfo.processInfo.environment[environmentVariable]
        }
        return value
        #else
        return ProcessInfo.processInfo.environment[environmentVariable]
        #endif
    }

    public func saveAPIKey(_ value: String) throws {
        #if canImport(Security)
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw CloudAPIKeyStoreError.keychain(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CloudAPIKeyStoreError.keychain(addStatus)
        }
        #else
        throw CloudAPIKeyStoreError.unsupportedPlatform
        #endif
    }

    public func deleteAPIKey() throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CloudAPIKeyStoreError.keychain(status)
        }
        #else
        throw CloudAPIKeyStoreError.unsupportedPlatform
        #endif
    }
}
