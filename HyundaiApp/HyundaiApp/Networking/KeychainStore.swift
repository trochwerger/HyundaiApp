import Foundation
import Security

public enum KeychainStore {
    private static let service = "com.tomas.hyundaiapp"
    private static let backendURLAccount = "backendURL"
    private static let apiKeyAccount = "apiKey"

    public enum KeychainError: Error {
        case osStatus(OSStatus)
    }

    public static func setBackendURL(_ url: String) throws {
        try setValue(url, account: backendURLAccount)
    }

    public static func getBackendURL() -> String? {
        getValue(account: backendURLAccount)
    }

    public static func setAPIKey(_ key: String) throws {
        try setValue(key, account: apiKeyAccount)
    }

    public static func getAPIKey() -> String? {
        getValue(account: apiKeyAccount)
    }

    public static func clear() throws {
        try deleteValue(account: backendURLAccount)
        try deleteValue(account: apiKeyAccount)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func setValue(_ value: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.osStatus(errSecParam)
        }

        let query = baseQuery(account: account)
        let status = SecItemCopyMatching(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data,
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.osStatus(updateStatus)
            }
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.osStatus(addStatus)
            }
        default:
            throw KeychainError.osStatus(status)
        }
    }

    private static func getValue(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            return nil
        }
    }

    private static func deleteValue(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.osStatus(status)
        }
    }
}
