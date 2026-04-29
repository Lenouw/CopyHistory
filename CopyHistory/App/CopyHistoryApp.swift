import SwiftUI

@main
struct CopyHistoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Pas de fenêtre principale — tout est géré par AppDelegate (menu bar + NSPanel)
        Settings { EmptyView() }
    }
}
