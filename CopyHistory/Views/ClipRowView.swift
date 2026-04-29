import SwiftUI
import AppKit

struct ClipRowView: View {
    let item: ClipboardItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            appIcon
                .frame(width: 22, height: 22)

            contentPreview
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            sideInfo
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var appIcon: some View {
        if let bundleID = item.appBundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: iconName(for: item.clipType))
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label = item.customLabel, !label.isEmpty {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.accentColor)
            }

            switch item.clipType {
            case .image:
                if let data = item.decryptedImageData, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 44)
                } else {
                    Text("[Image]").foregroundColor(.secondary)
                }
            default:
                Text(item.displayText)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundColor(item.clipType == .url ? .accentColor : .primary)
            }
        }
    }

    private var sideInfo: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }
            Text(relativeTime(item.createdAt))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            if let badge = typeBadge(item.clipType) {
                Text(badge)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(3)
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 5   { return "À l'instant" }
        if s < 60  { return "\(s)s" }
        if s < 3600 { return "\(s / 60)min" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)j"
    }

    private func iconName(for type: ClipType) -> String {
        switch type {
        case .text, .rtf: return "doc.text"
        case .image: return "photo"
        case .url: return "link"
        case .file: return "doc"
        }
    }

    private func typeBadge(_ type: ClipType) -> String? {
        switch type {
        case .text: return nil
        case .rtf: return "RTF"
        case .image: return "IMG"
        case .url: return "URL"
        case .file: return "FILE"
        }
    }
}
