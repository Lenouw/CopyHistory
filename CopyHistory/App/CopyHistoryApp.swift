import SwiftUI

@main
struct CopyHistoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Scene vide requise par SwiftUI — les préférences sont gérées
        // par PreferencesWindowController dans AppDelegate
        Settings { EmptyView() }
    }
}
