import Foundation
@preconcurrency import Security

enum KeychainError: Error {
    case saveFailed(OSStatus)
    case readFailed(OSStatus)
    case deleteFailed(OSStatus)
    case itemNotFound
    case invalidData
    case accessControlFailed
}

protocol KeychainStore: Sendable {
    func storeVaultKey(_ key: Data) throws
    func loadVaultKey() throws -> Data
    func storeSecret(_ data: Data, for secretRef: String) throws
    func loadSecret(for secretRef: String) throws -> Data
    func deleteSecret(for secretRef: String) throws
}

final class KeychainStoreImpl: KeychainStore, Sendable {
    private let serviceName = "PwdSafe.Secret"
    private let vaultKeyAccount = "PwdSafe.VaultKey"
    private let vaultKeyAccessControl: SecAccessControl = {
        SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            nil
        )!
    }()

    func storeVaultKey(_ key: Data) throws {
        _ = deleteGenericPassword(account: vaultKeyAccount)
        let status = saveGenericPassword(account: vaultKeyAccount, data: key, accessControl: vaultKeyAccessControl)
        if status == errSecDuplicateItem {
            _ = updateGenericPassword(account: vaultKeyAccount, data: key, accessControl: vaultKeyAccessControl)
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func loadVaultKey() throws -> Data {
        let status = readGenericPassword(account: vaultKeyAccount)
        switch status {
        case .success(let data): return data
        case .notFound: throw KeychainError.itemNotFound
        case .error(let code): throw KeychainError.readFailed(code)
        }
    }

    func storeSecret(_ data: Data, for secretRef: String) throws {
        _ = deleteGenericPassword(account: secretRef)
        let status = saveGenericPassword(account: secretRef, data: data)
        if status == errSecDuplicateItem {
            _ = updateGenericPassword(account: secretRef, data: data)
            return
        }
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func loadSecret(for secretRef: String) throws -> Data {
        let status = readGenericPassword(account: secretRef)
        switch status {
        case .success(let data): return data
        case .notFound: throw KeychainError.itemNotFound
        case .error(let code): throw KeychainError.readFailed(code)
        }
    }

    func deleteSecret(for secretRef: String) throws {
        let status = deleteGenericPassword(account: secretRef)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }

    private enum ReadResult {
        case success(Data)
        case notFound
        case error(OSStatus)
    }

    private func saveGenericPassword(account: String, data: Data, accessControl: SecAccessControl? = nil) -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        if let ac = accessControl {
            query[kSecAttrAccessControl as String] = ac
        }
        return SecItemAdd(query as CFDictionary, nil)
    }

    private func updateGenericPassword(account: String, data: Data, accessControl: SecAccessControl? = nil) -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        if let ac = accessControl {
            query[kSecAttrAccessControl as String] = ac
        }
        let attrs: [String: Any] = [kSecValueData as String: data]
        return SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
    }

    private func readGenericPassword(account: String) -> ReadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { return .notFound }
        guard status == errSecSuccess else { return .error(status) }
        guard let data = item as? Data else { return .error(errSecDecode) }
        return .success(data)
    }

    private func deleteGenericPassword(account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary)
    }
}
