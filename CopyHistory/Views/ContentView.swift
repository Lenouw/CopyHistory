import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]

    @State private var searchText = ""
    @State private var selectedID: UUID?

    var onPaste: ((ClipboardItem) -> Void)?

    private var filteredItems: [ClipboardItem] {
        let pool = searchText.isEmpty ? Array(items.prefix(300)) : items
        guard !searchText.isEmpty else { return pool }
        return pool.filter { item in
            item.displayText.localizedCaseInsensitiveContains(searchText)
            || (item.customLabel?.localizedCaseInsensitiveContains(searchText) == true)
            || (item.appName?.localizedCaseInsensitiveContains(searchText) == true)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            clipList
            Divider()
            footer
        }
        .frame(minWidth: 380, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 13))
            TextField("Rechercher dans l'historique…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var clipList: some View {
        if filteredItems.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: searchText.isEmpty ? "clipboard" : "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text(searchText.isEmpty ? "Aucun élément" : "Aucun résultat pour « \(searchText) »")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredItems, id: \.id) { item in
                        ClipRowView(item: item, isSelected: selectedID == item.id)
                            .onTapGesture {
                                selectedID = item.id
                                onPaste?(item)
                            }
                            .contextMenu { contextMenu(for: item) }
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(items.count) élément\(items.count > 1 ? "s" : "")")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Button("Tout effacer") { clearAll() }
                .font(.system(size: 10))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for item: ClipboardItem) -> some View {
        Button("Coller") { onPaste?(item) }
        Button("Copier seulement") { copyToClipboard(item) }
        Divider()
        Button(item.isPinned ? "Retirer des favoris" : "Épingler aux favoris") {
            item.isPinned.toggle()
        }
        Divider()
        Button("Supprimer", role: .destructive) {
            modelContext.delete(item)
        }
    }

    // MARK: - Actions

    func copyToClipboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.clipType {
        case .text, .url, .rtf, .file:
            pb.setString(item.textContent ?? item.filePath ?? "", forType: .string)
        case .image:
            if let data = item.imageData, let img = NSImage(data: data) {
                pb.writeObjects([img])
            }
        }
    }

    private func clearAll() {
        for item in items where !item.isPinned {
            modelContext.delete(item)
        }
    }
}
