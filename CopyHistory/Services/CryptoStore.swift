import Foundation
import CryptoKit
import Security

/// Chiffrement AES-256-GCM avec clé stockée dans le Keychain macOS.
/// La clé est générée aléatoirement au premier lancement et persistée dans le
/// trousseau de l'utilisateur (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly).
/// Elle ne quitte jamais la machine (pas d'iCloud Keychain : `ThisDevice`).
enum CryptoStore {
    private static let service = "com.florianbonin.CopyHistory"
    private static let account = "history-encryption-key-v1"

    /// Clé symétrique 256-bit, chargée depuis le Keychain ou générée si absente.
    static let key: SymmetricKey = {
        if let existing = loadKey() { return existing }
        let new = SymmetricKey(size: .bits256)
        saveKey(new)
        return new
    }()

    // MARK: - Encryption / Decryption

    static func encrypt(_ data: Data) -> Data? {
        guard !data.isEmpty else { return data }
        return try? AES.GCM.seal(data, using: key).combined
    }

    static func decrypt(_ data: Data) -> Data? {
        guard !data.isEmpty else { return data }
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    /// Chiffre une chaîne UTF-8 et renvoie le résultat en base64.
    static func encryptString(_ s: String) -> String? {
        guard let data = s.data(using: .utf8), let enc = encrypt(data) else { return nil }
        return enc.base64EncodedString()
    }

    /// Déchiffre une chaîne base64 vers du texte UTF-8.
    static func decryptString(_ s: String) -> String? {
        guard let data = Data(base64Encoded: s), let dec = decrypt(data) else { return nil }
        return String(data: dec, encoding: .utf8)
    }

    // MARK: - Keychain plumbing

    private static func loadKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    private static func saveKey(_ key: SymmetricKey) {
        let data = key.withUnsafeBytes { Data($0) }
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        // On supprime une éventuelle ancienne entrée puis on insère la nouvelle
        SecItemDelete(attrs as CFDictionary)
        SecItemAdd(attrs as CFDictionary, nil)
    }

    /// Supprime la clé du Keychain. À utiliser uniquement lors d'un "tout effacer"
    /// si l'utilisateur veut être certain qu'aucune donnée chiffrée orpheline ne reste lisible.
    static func deleteKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
