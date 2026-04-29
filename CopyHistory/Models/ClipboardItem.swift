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
    var textContent: String?
    var imageData: Data?
    var filePath: String?
    var appBundleID: String?
    var appName: String?
    var createdAt: Date
    var isPinned: Bool
    var customLabel: String?

    var clipType: ClipType {
        ClipType(rawValue: rawType) ?? .text
    }

    var displayText: String {
        switch clipType {
        case .text, .rtf, .url:
            return textContent ?? ""
        case .image:
            return "[Image]"
        case .file:
            return filePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "[Fichier]"
        }
    }

    var characterCount: Int {
        textContent?.count ?? 0
    }

    init(
        type: ClipType,
        text: String? = nil,
        imageData: Data? = nil,
        filePath: String? = nil,
        appBundleID: String? = nil,
        appName: String? = nil
    ) {
        self.id = UUID()
        self.rawType = type.rawValue
        self.textContent = text
        self.imageData = imageData
        self.filePath = filePath
        self.appBundleID = appBundleID
        self.appName = appName
        self.createdAt = Date()
        self.isPinned = false
    }
}
