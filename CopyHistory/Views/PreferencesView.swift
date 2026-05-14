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

            SecurityPrefsTab()
                .tabItem { Label("Sécurité", systemImage: "touchid") }
                .tag(2)

            PrivacyPrefsTab()
                .tabItem { Label("Confidentialité", systemImage: "lock.shield") }
                .tag(3)
        }
        .frame(width: 520, height: 460)
        .padding(20)
    }
}

// MARK: - Sécurité (biométrie)

struct SecurityPrefsTab: View {
    @AppStorage("biometricEnabled") private var enabled: Bool = true
    @AppStorage("biometricTimeoutMinutes") private var timeout: Int = 15

    private let timeoutOptions: [(Int, String)] = [
        (0, "Toujours demander"),
        (1, "1 minute"),
        (5, "5 minutes"),
        (15, "15 minutes"),
        (30, "30 minutes"),
        (60, "1 heure")
    ]

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "touchid")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Verrouillage biométrique")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Demande Touch ID (ou le mot de passe de votre Mac) pour ouvrir l'historique après une période d'inactivité. Protège vos clés API, mots de passe et données sensibles si un tiers a un accès physique à votre Mac.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Toggle("Activer le verrouillage biométrique", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in
                        BiometricGate.shared.resetGracePeriod()
                    }

                if enabled {
                    Picker("Redemander après", selection: $timeout) {
                        ForEach(timeoutOptions, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: timeout) { _, _ in
                        BiometricGate.shared.resetGracePeriod()
                    }
                }
            }

            if enabled {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("L'authentification est aussi redemandée à chaque relance de l'application.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
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
