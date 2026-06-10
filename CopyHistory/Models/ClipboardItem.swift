import Foundation
import SwiftData

enum ClipType: String, Codable, CaseIterable {
    case text
    case rtf
    case image
    case url
    case file
}

@Model
final class ClipboardItem {
    var id: UUID
    var rawType: String
    /// Texte chiffré (base64) si `isEncrypted == true`, sinon clair (legacy < 1.1.0).
    var textContent: String?
    /// Données image chiffrées si `isEncrypted == true`, sinon brutes (legacy < 1.1.0).
    var imageData: Data?
    var filePath: String?
    var appBundleID: String?
    var appName: String?
    var createdAt: Date
    var isPinned: Bool
    var customLabel: String?
    /// Indique si `textContent` et `imageData` sont chiffrés via CryptoStore.
    /// Default `false` pour la compatibilité avec les enregistrements créés avant la 1.1.0.
    var isEncrypted: Bool = false

    var clipType: ClipType {
        ClipType(rawValue: rawType) ?? .text
    }

    /// Cache mémoire EXTERNE du texte déchiffré, keyé par id.
    /// IMPORTANT : ne PAS stocker le cache sur le @Model (même en @Transient) — toute
    /// mutation d'une propriété du modèle pendant le rendu déclenche l'observation
    /// SwiftData et fait re-render la liste en boucle (latence énorme au clic, v1.2.0).
    private static let textCache = NSCache<NSString, NSString>()

    /// Texte en clair (déchiffré une seule fois puis mis en cache mémoire externe).
    var decryptedText: String? {
        guard let raw = textContent else { return nil }
        guard isEncrypted else { return raw }
        let key = id.uuidString as NSString
        if let cached = Self.textCache.object(forKey: key) { return cached as String }
        guard let decrypted = CryptoStore.decryptString(raw) else { return nil }
        Self.textCache.setObject(decrypted as NSString, forKey: key)
        return decrypted
    }

    /// Invalide le cache (à appeler si textContent/isEncrypted changent, ex. migration).
    func invalidateTextCache() {
        Self.textCache.removeObject(forKey: id.uuidString as NSString)
    }

    /// Données image brutes (déchiffrées à la volée si nécessaire).
    var decryptedImageData: Data? {
        guard let raw = imageData else { return nil }
        if isEncrypted {
            return CryptoStore.decrypt(raw)
        }
        return raw
    }

    var displayText: String {
        switch clipType {
        case .text, .rtf, .url:
            return decryptedText ?? ""
        case .image:
            return "[Image]"
        case .file:
            return filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "[Fichier]"
        }
    }

    var characterCount: Int {
        decryptedText?.count ?? 0
    }

    init(
        type: ClipType,
        text: String? = nil,
        imageData: Data? = nil,
        filePath: String? = nil,
        appBundleID: String? = nil,
        appName: String? = nil,
        encrypt: Bool = true
    ) {
        self.id = UUID()
        self.rawType = type.rawValue
        self.filePath = filePath
        self.appBundleID = appBundleID
        self.appName = appName
        self.createdAt = Date()
        self.isPinned = false

        if encrypt {
            // Chiffre le contenu via CryptoStore
            if let t = text, let enc = CryptoStore.encryptString(t) {
                self.textContent = enc
                self.imageData = imageData.flatMap { CryptoStore.encrypt($0) }
                self.isEncrypted = true
            } else if let img = imageData, let enc = CryptoStore.encrypt(img) {
                self.textContent = nil
                self.imageData = enc
                self.isEncrypted = true
            } else {
                // Échec du chiffrement : fallback en clair pour ne pas perdre la donnée
                self.textContent = text
                self.imageData = imageData
                self.isEncrypted = false
            }
        } else {
            self.textContent = text
            self.imageData = imageData
            self.isEncrypted = false
        }
    }
}
