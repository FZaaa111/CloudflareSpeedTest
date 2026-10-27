import Foundation
import Security

/// Cloudflare 认证方式
enum CFAuthType: String, Codable, CaseIterable, Identifiable {
    case apiToken
    case globalKey
    var id: String { rawValue }
    var title: String {
        switch self {
        case .apiToken: return "API Token"
        case .globalKey: return "Global API Key"
        }
    }
}

struct CFCredentials: Codable, Equatable {
    var authType: CFAuthType = .apiToken
    var apiToken = ""
    var email = ""
    var globalKey = ""

    var isComplete: Bool {
        switch authType {
        case .apiToken: return !apiToken.trimmingCharacters(in: .whitespaces).isEmpty
        case .globalKey:
            return !email.trimmingCharacters(in: .whitespaces).isEmpty
                && !globalKey.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}

/// 将 Cloudflare 凭证保存在 iOS 钥匙串中
enum KeychainStore {
    private static let service = "CloudflareSpeedTest"
    private static let account = "cloudflare-credentials"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load() -> CFCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(CFCredentials.self, from: data)
    }

    @discardableResult
    static func save(_ credentials: CFCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query.merge(attributes) { $1 }
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
