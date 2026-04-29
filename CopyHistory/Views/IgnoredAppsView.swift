import SwiftUI
import AppKit

// Modèle persisté dans UserDefaults
struct IgnoredApp: Codable, Identifiable, Hashable {
    let id: String      // bundle ID
    let name: String
}

// Helpers UserDefaults
extension UserDefaults {
    static let ignoredAppsKey = "ignoredAppsData"

    func ignoredApps() -> [IgnoredApp] {
        guard let data = data(forKey: Self.ignoredAppsKey),
              let apps = try? JSONDecoder().decode([IgnoredApp].self, from: data) else { return [] }
        return apps
    }

    func saveIgnoredApps(_ apps: [IgnoredApp]) {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        set(data, forKey: Self.ignoredAppsKey)
    }
}

// MARK: - Vue principale

struct IgnoredAppsView: View {
    @State private var ignoredApps: [IgnoredApp] = UserDefaults.standard.ignoredApps()
    @State private var selection: Set<String> = []
    @State private var showingPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ces applications ne seront jamais enregistrées dans l'historique.")
                .font(.callout)
                .foregroundColor(.secondary)

            List(ignoredApps, selection: $selection) { app in
                HStack(spacing: 10) {
                    appIcon(for: app.id)
                        .frame(width: 20, height: 20)
                    Text(app.name)
                    Spacer()
                    Text(app.id)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .tag(app.id)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 180)

            HStack(spacing: 6) {
                Button { showingPicker = true } label: {
                    Image(systemName: "plus")
                }
                .help("Ajouter une application")

                Button { removeSelected() } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection.isEmpty)
                .help("Retirer les applications sélectionnées")

                Spacer()

                if !ignoredApps.isEmpty {
                    Text("\(ignoredApps.count) app\(ignoredApps.count > 1 ? "s" : "") ignorée\(ignoredApps.count > 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingPicker) {
            AppPickerSheet { app in
                addApp(app)
            }
        }
    }

    private func removeSelected() {
        ignoredApps.removeAll { selection.contains($0.id) }
        selection = []
        UserDefaults.standard.saveIgnoredApps(ignoredApps)
    }

    private func addApp(_ app: IgnoredApp) {
        guard !ignoredApps.contains(where: { $0.id == app.id }) else { return }
        ignoredApps.append(app)
        ignoredApps.sort { $0.name < $1.name }
        UserDefaults.standard.saveIgnoredApps(ignoredApps)
    }

    @ViewBuilder
    private func appIcon(for bundleID: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.dashed")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Picker sheet (liste des apps en cours d'exécution)

struct AppPickerSheet: View {
    var onSelect: (IgnoredApp) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var runningApps: [RunningAppInfo] = []
    @State private var search = ""

    var filtered: [RunningAppInfo] {
        guard !search.isEmpty else { return runningApps }
        return runningApps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choisir une application")
                    .font(.headline)
                Spacer()
                Button("Annuler") { dismiss() }
                    .buttonStyle(.plain)
            }
            .padding()

            Divider()

            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Rechercher…", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            List(filtered) { app in
                Button {
                    onSelect(IgnoredApp(id: app.bundleID, name: app.name))
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).font(.system(size: 13))
                            Text(app.bundleID).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .frame(width: 380, height: 420)
        .onAppear { loadRunningApps() }
    }

    private func loadRunningApps() {
        let mine = Bundle.main.bundleIdentifier ?? ""
        runningApps = NSWorkspace.shared.runningApplications
            .filter { app in
                guard let bid = app.bundleIdentifier, !bid.isEmpty else { return false }
                guard let name = app.localizedName, !name.isEmpty else { return false }
                guard bid != mine else { return false }
                guard app.activationPolicy == .regular else { return false }
                return true
            }
            .map { app in
                RunningAppInfo(
                    bundleID: app.bundleIdentifier!,
                    name: app.localizedName!,
                    icon: app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
                )
            }
            .sorted { $0.name < $1.name }
    }
}

struct RunningAppInfo: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage
    var id: String { bundleID }
}
