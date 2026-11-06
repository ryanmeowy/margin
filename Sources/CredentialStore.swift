import Foundation
import Security

/// 会话 token 只存本机：Application Support 下的 0600 文件。
/// 早期版本用过 Keychain，这里保留一次性迁移（读到就不再用 Keychain，避免每次重签都弹授权框）。
enum CredentialStore {
    struct CredentialError: Error { var message: String }

    private static let service = "com.ryan.margin.session"
    private static let account = "open-design"

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.ryan.margin", isDirectory: true)
    }

    private static var fileURL: URL { directory.appendingPathComponent("session.token") }

    static func loadToken() -> String? {
        if let token = readFile(), !token.isEmpty { return token }
        if let token = readKeychain(), !token.isEmpty {
            try? saveToken(token)      // 迁移到文件
            deleteKeychain()
            return token
        }
        return nil
    }

    static func saveToken(_ token: String) throws {
        guard !token.isEmpty else { deleteToken(); return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Data(token.utf8).write(to: fileURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func deleteToken() {
        try? FileManager.default.removeItem(at: fileURL)
        deleteKeychain()
    }

    // MARK: 文件

    private static func readFile() -> String? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: 旧版 Keychain（仅迁移用）

    private static var keychainQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func readKeychain() -> String? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    private static func deleteKeychain() {
        SecItemDelete(keychainQuery as CFDictionary)
    }
}
