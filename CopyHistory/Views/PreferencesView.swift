import SwiftUI
import ServiceManagement
import AppKit

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPrefsTab()
                .tabItem { Label("Général", systemImage: "gear") }
                .tag(0)

            IgnoredAppsView()
                .tabItem { Label("Apps ignorées", systemImage: "nosign") }
                .tag(1)

            PrivacyPrefsTab()
                .tabItem { Label("Confidentialité", systemImage: "lock.shield") }
                .tag(2)
        }
        .frame(width: 520, height: 420)
        .padding(20)
    }
}

// MARK: - Général

struct GeneralPrefsTab: View {
    @AppStorage("ignorePasswords") private var ignorePasswords: Bool = true
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        Form {
            Section {
                Toggle("Ignorer les mots de passe et données sensibles", isOn: $ignorePasswords)
                    .help("Les champs de mot de passe et données masquées ne seront pas enregistrés dans l'historique.")

                Toggle("Lancer CopyHistory au démarrage", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !enabled  // revert on error
                        }
                    }
            }

            Spacer()

            Section {
                HStack {
                    Text("Raccourci global")
                    Spacer()
                    Text("⇧⌘V")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, design: .monospaced))
                }
                .padding(.vertical, 2)

                HStack {
                    Text("Déclencheur bord bas")
                    Spacer()
                    Text("Scroll ↑ sur le bord bas de l'écran")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Confidentialité

struct PrivacyPrefsTab: View {
    @State private var showEraseConfirmation = false

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Historique chiffré")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Tous les éléments de l'historique sont chiffrés en AES-256-GCM. La clé est stockée dans le Trousseau macOS de votre session et ne quitte jamais votre Mac.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Emplacement de la base")
                            .font(.system(size: 12, weight: .medium))
                        Text("~/Library/Application Support/CopyHistory/")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button("Ouvrir") { openStoreFolder() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Zone dangereuse")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red)

                    Button(role: .destructive) {
                        showEraseConfirmation = true
                    } label: {
                        Label("Effacer tout l'historique", systemImage: "trash.fill")
                    }
                    .controlSize(.regular)

                    Text("Supprime définitivement tous les éléments enregistrés, y compris les éléments épinglés. Cette action est irréversible.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Effacer tout l'historique ?",
            isPresented: $showEraseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Tout effacer", role: .destructive) {
                eraseAll()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Tous les éléments du presse-papiers seront supprimés définitivement, y compris les épinglés. Cette action ne peut pas être annulée.")
        }
    }

    private func eraseAll() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.eraseAllHistory()
        }
    }

    private func openStoreFolder() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let url = appSupport.appendingPathComponent("CopyHistory", isDirectory: true)
        NSWorkspace.shared.open(url)
    }
}
