import AppKit
import SwiftUI
import SwiftData
import KeyboardShortcuts
import Sparkle

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.shift, .command]))
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: FloatingPanel?
    private var clipMonitor: ClipboardMonitor?
    private var hotEdge: HotEdgeTrigger?
    private var modelContainer: ModelContainer?
    private var saveContext: ModelContext?  // contexte dédié écriture (réutilisé)
    private var updaterController: SPUStandardUpdaterController?
    private var prefsWindowController: NSWindowController?

    // Plafonds historique
    private let maxItemsTotal = 1000
    private let maxImageItems = 50

    private var previousApp: NSRunningApplication?
    private let panelWidth:  CGFloat = 420
    private let panelHeight: CGFloat = 560

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerDefaults()
        setupModelContainer()
        migrateLegacyClipsToEncrypted()
        setupStatusItem()
        setupClipboardMonitor()
        setupHotEdgeTrigger()
        setupHotkey()
        setupSparkle()
        requestAccessibilityIfNeeded()
    }

    // MARK: - Setup

    private func registerDefaults() {
        UserDefaults.standard.register(defaults: ["ignorePasswords": true])
    }

    private func setupModelContainer() {
        let schema = Schema([ClipboardItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: config)
            modelContainer = container
            saveContext = ModelContext(container)
            protectStoreOnDisk()
        } catch {
            NSLog("[CopyHistory] ModelContainer init échoué : \(error)")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Erreur de stockage"
                alert.informativeText = "CopyHistory n'a pas pu initialiser sa base de données. L'historique ne sera pas sauvegardé.\n\n\(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    /// Restreint les permissions du fichier SwiftData au seul utilisateur courant (chmod 600)
    /// + masque le fichier de Time Machine. Le store reste en clair sur disque, mais inaccessible
    /// aux autres utilisateurs locaux et exclu des sauvegardes Time Machine.
    private func protectStoreOnDisk() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let storeDir = appSupport.appendingPathComponent("CopyHistory", isDirectory: true)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: storeDir, includingPropertiesForKeys: nil) else { return }
        for url in files {
            // chmod 600 : lecture/écriture pour le propriétaire uniquement
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            // Exclure de Time Machine
            var u = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? u.setResourceValues(values)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let btn = statusItem?.button
        btn?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "CopyHistory")
        btn?.action = #selector(statusBarButtonClicked(_:))
        btn?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        btn?.target = self
    }

    private func setupClipboardMonitor() {
        clipMonitor = ClipboardMonitor()
        clipMonitor?.onNewItem = { [weak self] data in self?.saveClip(data) }
        clipMonitor?.start()
    }

    private func setupHotEdgeTrigger() {
        hotEdge = HotEdgeTrigger()
        hotEdge?.onScrollUp = { [weak self] mouseX in
            guard let self else { return }
            if self.panel?.isVisible == true {
                self.hidePanel()
            } else {
                self.previousApp = NSWorkspace.shared.frontmostApplication
                self.showPanel(centeredAt: mouseX)
            }
        }
        hotEdge?.start()
    }

    private func setupHotkey() {
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in self?.togglePanel() }
    }

    private func setupSparkle() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Status bar button

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePanel()
        }
    }

    // MARK: - Context menu (clic droit)

    private func showContextMenu() {
        let menu = NSMenu()

        let prefsItem = NSMenuItem(title: "Préférences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let updateItem = NSMenuItem(title: "Vérifier les mises à jour…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quitter CopyHistory", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        // popUp est la seule méthode fiable — pas de statusItem.menu = menu
        // qui bloque tous les clics suivants si menuDidClose ne se déclenche pas
        if let button = statusItem?.button {
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: button.bounds.height + 4),
                       in: button)
        }
    }

    @objc func openPreferences() {
        if prefsWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Préférences CopyHistory"
            window.center()
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreferencesView())
            prefsWindowController = NSWindowController(window: window)
        }
        prefsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController?.checkForUpdates(sender)
    }

    // MARK: - Panel toggle

    @objc func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            previousApp = NSWorkspace.shared.frontmostApplication
            let mouseX = NSEvent.mouseLocation.x
            showPanel(centeredAt: mouseX)
        }
    }

    // MARK: - Panel show/hide avec animation spring

    private func showPanel(centeredAt mouseX: CGFloat = -1) {
        buildPanelIfNeeded()
        guard let panel else { return }

        let finalFrame = panelFrame(centeredAt: mouseX)
        let startFrame = NSRect(x: finalFrame.minX, y: finalFrame.minY - finalFrame.height,
                                width: finalFrame.width, height: finalFrame.height)
        let overshootFrame = NSRect(x: finalFrame.minX, y: finalFrame.minY + 10,
                                    width: finalFrame.width, height: finalFrame.height)

        panel.alphaValue = 0
        panel.setFrame(startFrame, display: false)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(overshootFrame, display: true)
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.6, 1)
                panel.animator().setFrame(finalFrame, display: true)
            }
        })
    }

    private func hidePanel() {
        guard let panel else { return }
        let hiddenOrigin = NSPoint(x: panel.frame.minX, y: panel.frame.minY - panel.frame.height)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(hiddenOrigin)
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    private func panelFrame(centeredAt mouseX: CGFloat = -1) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let referenceX = mouseX >= 0 ? mouseX : visible.midX
        var x = referenceX - panelWidth / 2
        x = max(visible.minX, min(x, visible.maxX - panelWidth))
        return NSRect(x: x, y: visible.minY, width: panelWidth, height: panelHeight)
    }

    private func buildPanelIfNeeded() {
        guard panel == nil, let container = modelContainer else { return }
        panel = FloatingPanel()
        let view = ContentView(onPaste: { [weak self] item in self?.directPaste(item) })
            .modelContainer(container)
        panel?.contentViewController = NSHostingController(rootView: view)
    }

    // MARK: - Direct Paste

    private func directPaste(_ item: ClipboardItem) {
        copyToClipboard(item)
        let appToRestore = previousApp
        hidePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            // Si l'app source a été quittée entretemps, on copie quand même mais on ne paste pas dans le vide
            if let app = appToRestore, !app.isTerminated {
                app.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.simulatePaste() }
            }
        }
    }

    private func copyToClipboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.clipType {
        case .text, .url, .rtf, .file:
            pb.setString(item.decryptedText ?? item.filePath ?? "", forType: .string)
        case .image:
            if let data = item.decryptedImageData, let img = NSImage(data: data) { pb.writeObjects([img]) }
        }
    }

    private func simulatePaste() {
        guard AXIsProcessTrusted() else {
            NSLog("[CopyHistory] Direct Paste indisponible : Accessibilité non accordée")
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 0x09
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags   = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Migration legacy → chiffré (1.0.x → 1.1.0)

    /// Chiffre en place tous les enregistrements créés avant la 1.1.0 (qui sont en clair).
    /// Idempotent : ne touche pas aux items déjà chiffrés.
    private func migrateLegacyClipsToEncrypted() {
        guard let context = saveContext else { return }
        let descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { !$0.isEncrypted })
        guard let legacy = try? context.fetch(descriptor), !legacy.isEmpty else { return }

        var migrated = 0
        for item in legacy {
            if let text = item.textContent, !text.isEmpty {
                if let enc = CryptoStore.encryptString(text) {
                    item.textContent = enc
                } else { continue }
            }
            if let img = item.imageData, !img.isEmpty {
                if let enc = CryptoStore.encrypt(img) {
                    item.imageData = enc
                } else { continue }
            }
            item.isEncrypted = true
            migrated += 1
        }
        try? context.save()
        if migrated > 0 {
            NSLog("[CopyHistory] Migration : \(migrated) éléments chiffrés rétroactivement")
        }
    }

    // MARK: - Effacer tout l'historique

    /// Supprime tous les éléments de l'historique (épinglés inclus).
    /// La clé Keychain est conservée pour ne pas casser les nouveaux items.
    @objc func eraseAllHistory() {
        guard let context = saveContext else { return }
        let descriptor = FetchDescriptor<ClipboardItem>()
        if let all = try? context.fetch(descriptor) {
            all.forEach { context.delete($0) }
            try? context.save()
        }
    }

    // MARK: - Persistence

    private func saveClip(_ data: NewClipData) {
        guard let context = saveContext else { return }
        if data.type != .image {
            var descriptor = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\ClipboardItem.createdAt, order: .reverse)])
            descriptor.fetchLimit = 1
            if let last = try? context.fetch(descriptor).first, last.decryptedText == data.text { return }
        }
        let item = ClipboardItem(type: data.type, text: data.text, imageData: data.imageData,
                                  filePath: data.filePath, appBundleID: data.appBundleID, appName: data.appName)
        context.insert(item)
        try? context.save()
        trimHistory(context: context)
    }

    private func trimHistory(context: ModelContext) {
        // 1) Cap global sur tous les items non-épinglés
        let allDescriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\ClipboardItem.createdAt, order: .reverse)]
        )
        if let all = try? context.fetch(allDescriptor), all.count > maxItemsTotal {
            all.dropFirst(maxItemsTotal).forEach { context.delete($0) }
        }

        // 2) Cap spécifique aux images (TIFF/PNG peuvent peser plusieurs MB chacun)
        let imageRaw = ClipType.image.rawValue
        let imgDescriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned && $0.rawType == imageRaw },
            sortBy: [SortDescriptor(\ClipboardItem.createdAt, order: .reverse)]
        )
        if let imgs = try? context.fetch(imgDescriptor), imgs.count > maxImageItems {
            imgs.dropFirst(maxImageItems).forEach { context.delete($0) }
        }

        try? context.save()
    }
}

