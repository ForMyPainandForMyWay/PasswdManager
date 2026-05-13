import Foundation
import Security
import LocalAuthentication

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
    func deleteVaultKey() throws
    func storeSecret(_ data: Data, for secretRef: String) throws
    func loadSecret(for secretRef: String) throws -> Data
    func deleteSecret(for secretRef: String) throws
}

final class KeychainStoreImpl: KeychainStore, Sendable {
    private let serviceName = "PwdSafe.Secret"
    private let vaultKeyAccount = "PwdSafe.VaultKey"

    func storeVaultKey(_ key: Data) throws {
        try deleteVaultKey()
        let status = saveGenericPassword(
            account: vaultKeyAccount,
            data: key,
            useAccessControl: true
        )
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func loadVaultKey() throws -> Data {
        let status = readGenericPassword(account: vaultKeyAccount)
        switch status {
        case .success(let data):
            return data
        case .notFound:
            throw KeychainError.itemNotFound
        case .error(let code):
            throw KeychainError.readFailed(code)
        }
    }

    func deleteVaultKey() throws {
        let status = deleteGenericPassword(account: vaultKeyAccount)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.deleteFailed(status)
        }
    }

    func storeSecret(_ data: Data, for secretRef: String) throws {
        try deleteSecret(for: secretRef)
        let status = saveGenericPassword(
            account: secretRef,
            data: data,
            useAccessControl: false
        )
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func loadSecret(for secretRef: String) throws -> Data {
        let status = readGenericPassword(account: secretRef)
        switch status {
        case .success(let data):
            return data
        case .notFound:
            throw KeychainError.itemNotFound
        case .error(let code):
            throw KeychainError.readFailed(code)
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

    private func saveGenericPassword(account: String, data: Data, useAccessControl: Bool) -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        if useAccessControl {
            guard let access = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet,
                nil
            ) else {
                return errSecAuthFailed
            }
            query[kSecAttrAccessControl as String] = access
            query[kSecUseAuthenticationContext as String] = LAContext()
        }

        return SecItemAdd(query as CFDictionary, nil)
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