import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var debouncedSearch = ""
    @State private var debounceWork: DispatchWorkItem?
    @State private var totalCount = 0

    var onPaste: ((ClipboardItem) -> Void)?
    var onToggleQueue: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            // Liste isolée : construit son propre @Query (limité hors recherche).
            // Le @Query reste DANS cette sous-vue pour ne pas matérialiser tout
            // l'historique à chaque re-render de ContentView.
            ClipListView(search: debouncedSearch,
                         onPaste: onPaste)
            Divider()
            footer
        }
        .frame(minWidth: 380, minHeight: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear(perform: refreshCount)
    }

    private func refreshCount() {
        totalCount = (try? modelContext.fetchCount(FetchDescriptor<ClipboardItem>())) ?? 0
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
                .onChange(of: searchText) { _, new in
                    // Debounce : on ne relance le fetch « tout l'historique »
                    // qu'après 0.2s d'inactivité de frappe.
                    debounceWork?.cancel()
                    let trimmed = new.trimmingCharacters(in: .whitespaces)
                    let work = DispatchWorkItem { debouncedSearch = trimmed }
                    debounceWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    debounceWork?.cancel()
                    debouncedSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(totalCount) élément\(totalCount > 1 ? "s" : "")")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Spacer()

            PasteQueueToggle(onActivate: onToggleQueue)

            Divider().frame(height: 12)

            Button("Tout effacer") { clearAll() }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func clearAll() {
        // Supprime tous les non-épinglés sans matérialiser la liste dans la vue :
        // fetch ponctuel + delete.
        let descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { !$0.isPinned })
        if let all = try? modelContext.fetch(descriptor) {
            all.forEach { modelContext.delete($0) }
            try? modelContext.save()
        }
        refreshCount()
    }
}

// MARK: - Clip list (owns the bounded @Query)

private struct ClipListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [ClipboardItem]

    let search: String
    var onPaste: ((ClipboardItem) -> Void)?

    /// Nombre d'items chargés en vue par défaut (hors recherche).
    private static let defaultLimit = 150

    init(search: String, onPaste: ((ClipboardItem) -> Void)?) {
        self.search = search
        self.onPaste = onPaste

        var descriptor = FetchDescriptor<ClipboardItem>(
            sortBy: [SortDescriptor(\ClipboardItem.createdAt, order: .reverse)]
        )
        // Hors recherche : on ne charge que les N plus récents.
        // En recherche : pas de limite → on fouille tout l'historique.
        if search.isEmpty {
            descriptor.fetchLimit = Self.defaultLimit
        }
        _items = Query(descriptor)
    }

    /// Filtrage en mémoire (le texte est chiffré sur disque, impossible à pousser
    /// dans un #Predicate SwiftData). Déchiffrement caché → une seule passe par item.
    private var displayed: [ClipboardItem] {
        guard !search.isEmpty else { return items }
        return items.filter { item in
            item.displayText.localizedCaseInsensitiveContains(search)
            || (item.customLabel?.localizedCaseInsensitiveContains(search) == true)
            || (item.appName?.localizedCaseInsensitiveContains(search) == true)
        }
    }

    var body: some View {
        if displayed.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: search.isEmpty ? "clipboard" : "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text(search.isEmpty ? "Aucun élément" : "Aucun résultat pour « \(search) »")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayed, id: \.id) { item in
                        ClipRowView(item: item, isSelected: false)
                            .onTapGesture { onPaste?(item) }
                            .contextMenu { contextMenu(for: item) }
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClipboardItem) -> some View {
        Button("Copier") { onPaste?(item) }
        Divider()
        Button(item.isPinned ? "Retirer des favoris" : "Épingler aux favoris") {
            item.isPinned.toggle()
        }
        Divider()
        Button("Supprimer", role: .destructive) {
            modelContext.delete(item)
        }
    }
}

// MARK: - Paste Queue Toggle

private struct PasteQueueToggle: View {
    @ObservedObject private var qm = PasteQueueManager.shared
    var onActivate: (() -> Void)?

    private var remaining: Int { max(0, qm.queue.count - qm.nextIndex) }

    var body: some View {
        Button(action: {
            let wasActive = qm.isActive
            qm.toggle()
            if !wasActive { onActivate?() }
        }) {
            HStack(spacing: 5) {
                Image(systemName: qm.isActive ? "tray.full.fill" : "tray.full")
                    .font(.system(size: 12))
                    .foregroundColor(qm.isActive ? .accentColor : .secondary)

                if qm.isActive {
                    Text("\(remaining) restant\(remaining > 1 ? "s" : "")")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                } else {
                    Text("File de collage")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(qm.isActive ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: qm.isActive)
        .help(qm.isActive
              ? "File de collage active — \(qm.queue.count) éléments. Cliquer pour annuler."
              : "Activer la file de collage : copiez plusieurs textes, puis collez-les un par un avec ⌘V")
    }
}
