import Foundation
import Security

class KeychainHelper {
    static let shared = KeychainHelper()

    private let service = "com.maseratiobd.app"
    private let accessTokenKey = "accessToken"
    private let refreshTokenKey = "refreshToken"
    private let userIdKey = "userId"

    private init() {}

    // MARK: - Save

    func saveAccessToken(_ token: String) {
        save(key: accessTokenKey, value: token)
    }

    func saveRefreshToken(_ token: String) {
        save(key: refreshTokenKey, value: token)
    }

    func saveUserId(_ userId: String) {
        save(key: userIdKey, value: userId)
    }

    // MARK: - Get

    func getAccessToken() -> String? {
        get(key: accessTokenKey)
    }

    func getRefreshToken() -> String? {
        get(key: refreshTokenKey)
    }

    func getUserId() -> String? {
        get(key: userIdKey)
    }

    // MARK: - Delete

    func deleteAll() {
        delete(key: accessTokenKey)
        delete(key: refreshTokenKey)
        delete(key: userIdKey)
    }

    // MARK: - Private Methods

    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)

        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
