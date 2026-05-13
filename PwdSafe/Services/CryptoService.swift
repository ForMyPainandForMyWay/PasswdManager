import CryptoKit
import Foundation

enum CryptoError: Error {
    case keyCreationFailed
    case encryptionFailed
    case decryptionFailed
    case invalidData
}

protocol CryptoService: Sendable {
    func createVaultKey() throws -> SymmetricKey
    func encrypt(_ payload: SecretPayload, itemID: UUID, vaultKey: SymmetricKey) throws -> EncryptedSecret
    func decrypt(_ encrypted: EncryptedSecret, itemID: UUID, vaultKey: SymmetricKey) throws -> SecretPayload
}

final class AESCryptoService: CryptoService, Sendable {
    private let algorithmName = "AES-256-GCM"

    func createVaultKey() throws -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    func encrypt(_ payload: SecretPayload, itemID: UUID, vaultKey: SymmetricKey) throws -> EncryptedSecret {
        let payloadData: Data
        do {
            payloadData = try JSONEncoder().encode(payload)
        } catch {
            throw CryptoError.encryptionFailed
        }

        let derivedKey = deriveItemKey(vaultKey: vaultKey, itemID: itemID)
        let nonce = try AES.GCM.Nonce()

        let aad = makeAAD(itemID: itemID, version: 1)
        guard let sealedBox = try? AES.GCM.seal(payloadData, using: derivedKey, nonce: nonce, authenticating: aad) else {
            throw CryptoError.encryptionFailed
        }

        return EncryptedSecret(
            version: 1,
            algorithm: algorithmName,
            keyID: vaultKey.hashValueHex(),
            nonce: Data(nonce),
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )
    }

    func decrypt(_ encrypted: EncryptedSecret, itemID: UUID, vaultKey: SymmetricKey) throws -> SecretPayload {
        guard encrypted.version == 1,
              encrypted.algorithm == algorithmName else {
            throw CryptoError.invalidData
        }

        let derivedKey = deriveItemKey(vaultKey: vaultKey, itemID: itemID)

        guard let nonce = try? AES.GCM.Nonce(data: encrypted.nonce) else {
            throw CryptoError.invalidData
        }

        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: encrypted.ciphertext,
            tag: encrypted.tag
        )

        let aad = makeAAD(itemID: itemID, version: encrypted.version)
        let decryptedData: Data
        do {
            decryptedData = try AES.GCM.open(sealedBox, using: derivedKey, authenticating: aad)
        } catch {
            throw CryptoError.decryptionFailed
        }

        do {
            return try JSONDecoder().decode(SecretPayload.self, from: decryptedData)
        } catch {
            throw CryptoError.decryptionFailed
        }
    }

    private func deriveItemKey(vaultKey: SymmetricKey, itemID: UUID) -> SymmetricKey {
        let idData = withUnsafeBytes(of: itemID.uuid) { Data($0) }
        let derived = HMAC<SHA256>.authenticationCode(for: idData, using: SymmetricKey(data: vaultKey.withUnsafeBytes { Data($0) }))
        return SymmetricKey(data: derived)
    }

    private func makeAAD(itemID: UUID, version: Int) -> Data {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: version) { Data($0) })
        let idBytes = withUnsafeBytes(of: itemID.uuid) { Data($0) }
        data.append(idBytes)
        return data
    }
}

private extension SymmetricKey {
    func hashValueHex() -> String {
        let hash = SHA256.hash(data: self.withUnsafeBytes { Data($0) })
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}