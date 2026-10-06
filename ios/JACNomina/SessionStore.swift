import Foundation
import Security

protocol SessionStoring: AnyObject {
    func load() throws -> String?
    func save(_ token: String) throws
    func clear() throws
}

final class KeychainSessionStore: SessionStoring {
    private let service = "co.jacmusic.nomina.session"
    private let account: String
    init(account: String) { self.account = account }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func load() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw APIError.message("No se pudo leer la sesión segura de este iPhone.")
        }
        return value
    }
    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw APIError.message("No se pudo guardar la sesión de forma segura.") }
        } else if status != errSecSuccess {
            throw APIError.message("No se pudo actualizar la sesión segura.")
        }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIError.message("No se pudo cerrar la sesión local.") }
    }
}
