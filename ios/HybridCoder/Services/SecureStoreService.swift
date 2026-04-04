import Foundation
import Security
import OSLog

actor SecureStoreService {
    nonisolated enum SecureStoreError: Error, LocalizedError, Sendable {
        case encodingFailed
        case saveFailed(OSStatus)
        case readFailed(OSStatus)
        case deleteFailed(OSStatus)
        case unexpectedData

        nonisolated var errorDescription: String? {
            switch self {
            case .encodingFailed: return "Failed to encode value for Keychain storage."
            case .saveFailed(let status): return "Keychain save failed: \(Self.statusMessage(status))"
            case .readFailed(let status): return "Keychain read failed: \(Self.statusMessage(status))"
            case .deleteFailed(let status): return "Keychain delete failed: \(Self.statusMessage(status))"
            case .unexpectedData: return "Unexpected data format from Keychain."
            }
        }

        private static func statusMessage(_ status: OSStatus) -> String {
            if let msg = SecCopyErrorMessageString(status, nil) as String? {
                return msg
            }
            return "OSStatus \(status)"
        }
    }

    private let serviceName: String
    private let accessGroup: String?
    private let logger = Logger(subsystem: "com.hybridcoder.app", category: "SecureStoreService")

    init(serviceName: String = "com.hybridcoder.app", accessGroup: String? = nil) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
    }

    func setString(_ key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecureStoreError.encodingFailed
        }
        try setData(key, value: data)
    }

    func getString(_ key: String) throws -> String? {
        guard let data = try getData(key) else { return nil }
        guard let str = String(data: data, encoding: .utf8) else {
            throw SecureStoreError.unexpectedData
        }
        return str
    }

    func setData(_ key: String, value: Data) throws {
        try? deleteItem(key)

        var query = baseQuery(for: key)
        query[kSecValueData as String] = value
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStoreError.saveFailed(status)
        }
    }

    func getData(_ key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw SecureStoreError.readFailed(status)
        }
        guard let data = result as? Data else {
            throw SecureStoreError.unexpectedData
        }
        return data
    }

    func deleteItem(_ key: String) throws {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.deleteFailed(status)
        }
    }

    func setObject<T: Encodable & Sendable>(_ key: String, value: T) throws {
        let data = try JSONEncoder().encode(value)
        try setData(key, value: data)
    }

    func getObject<T: Decodable & Sendable>(_ key: String, as type: T.Type) throws -> T? {
        guard let data = try getData(key) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func contains(_ key: String) throws -> Bool {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = false

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else {
            throw SecureStoreError.readFailed(status)
        }
        return true
    }

    func deleteAll() throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.deleteFailed(status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }
}
