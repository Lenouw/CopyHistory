import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPrefsTab()
                .tabItem { Label("Général", systemImage: "gear") }
                .tag(0)

            IgnoredAppsView()
                .tabItem { Label("Apps ignorées", systemImage: "nosign") }
                .tag(1)
        }
        .frame(width: 500, height: 380)
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
