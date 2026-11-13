import Foundation
import Security

// Provider-neutral token storage. The Keychain service/account identifiers are GitHub-era
// constants kept verbatim so existing stored tokens continue to load.

protocol TokenStoring: Sendable {
    func load() throws -> StoredToken?
    func save(_ token: StoredToken) throws
    func delete() throws
}

enum TokenStore {
    static func makeDefault() -> any TokenStoring {
        #if DEBUG
            return DevelopmentFileTokenStore()
        #else
            return KeychainTokenStore()
        #endif
    }
}

final class KeychainTokenStore: TokenStoring {
    static let legacyAccount = "github-app-user-token"

    private let service = "com.osuritz.hubber.github-auth"
    private let account: String

    init(account: String = KeychainTokenStore.legacyAccount) {
        self.account = account
    }

    func load() throws -> StoredToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CodeHostAuthError.keychain(status)
        }
        guard let data = item as? Data else {
            throw CodeHostAuthError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredToken.self, from: data)
    }

    func save(_ token: StoredToken) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(token)
        var query = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw CodeHostAuthError.keychain(status)
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CodeHostAuthError.keychain(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CodeHostAuthError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

final class DevelopmentFileTokenStore: TokenStoring {
    private let tokenURL: URL

    init(tokenURL: URL = DevelopmentFileTokenStore.defaultTokenURL) {
        self.tokenURL = tokenURL
    }

    func load() throws -> StoredToken? {
        guard FileManager.default.fileExists(atPath: tokenURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: tokenURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredToken.self, from: data)
    }

    func save(_ token: StoredToken) throws {
        try FileManager.default.createDirectory(
            at: tokenURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(token)
        try data.write(to: tokenURL, options: [.atomic])
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: tokenURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: tokenURL)
    }

}
