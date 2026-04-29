import AppKit
import SwiftUI
import SwiftData
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.shift, .command]))
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: FloatingPanel?
    private var monitor: ClipboardMonitor?
    private var modelContainer: ModelContainer?

    // App active AVANT l'ouverture du panel — pour Direct Paste
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupModelContainer()
        setupStatusItem()
        setupClipboardMonitor()
        setupHotkey()
        requestAccessibilityIfNeeded()
    }

    // MARK: - Setup

    private func setupModelContainer() {
        let schema = Schema([ClipboardItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        modelContainer = try? ModelContainer(for: schema, configurations: config)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let btn = statusItem?.button
        btn?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "CopyHistory")
        btn?.action = #selector(togglePanel)
        btn?.target = self
    }

    private func setupClipboardMonitor() {
        monitor = ClipboardMonitor()
        monitor?.onNewItem = { [weak self] data in
            self?.saveClip(data)
        }
        monitor?.start()
    }

    private func setupHotkey() {
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
    }

    private func requestAccessibilityIfNeeded() {
        // Demande les permissions Accessibility pour pouvoir simuler ⌘V
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
            AXIsProcessTrustedWithOptions(options)
        }
    }

    // MARK: - Panel management

    @objc func togglePanel() {
        if let panel = panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            previousApp = NSWorkspace.shared.frontmostApplication
            showPanel()
        }
    }

    private func showPanel() {
        if panel == nil, let container = modelContainer {
            panel = FloatingPanel()
            let view = ContentView(onPaste: { [weak self] item in
                self?.directPaste(item)
            })
            .modelContainer(container)
            panel?.contentViewController = NSHostingController(rootView: view)
        }

        positionPanelNearMenuBar()
        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
    }

    private func positionPanelNearMenuBar() {
        guard let screen = NSScreen.main, let panel = panel else { return }
        let screenRect = screen.visibleFrame
        let panelWidth: CGFloat = 420
        let panelHeight: CGFloat = 560
        let x = (screenRect.width - panelWidth) / 2 + screenRect.minX
        let y = screenRect.maxY - panelHeight - 8
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }

    // MARK: - Direct Paste

    private func directPaste(_ item: ClipboardItem) {
        // 1. Copier dans le presse-papier
        copyToClipboard(item)

        // 2. Fermer le panel
        panel?.orderOut(nil)

        // 3. Réactiver l'app précédente et simuler ⌘V
        let appToRestore = previousApp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            appToRestore?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.simulatePaste()
            }
        }
    }

    private func copyToClipboard(_ item: ClipboardItem) {
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

    private func simulatePaste() {
        guard AXIsProcessTrusted() else { return }
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 0x09
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags   = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Persistence

    private func saveClip(_ data: NewClipData) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)

        // Dédoublonnage : ne pas enregistrer si identique au dernier clip texte
        if data.type != .image {
            var descriptor = FetchDescriptor<ClipboardItem>(
                sortBy: [SortDescriptor(\ClipboardItem.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            if let last = try? context.fetch(descriptor).first,
               last.textContent == data.text {
                return
            }
        }

        let item = ClipboardItem(
            type: data.type,
            text: data.text,
            imageData: data.imageData,
            filePath: data.filePath,
            appBundleID: data.appBundleID,
            appName: data.appName
        )
        context.insert(item)
        try? context.save()

        trimHistory(context: context)
    }

    private func trimHistory(context: ModelContext) {
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\ClipboardItem.createdAt, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor), all.count > 1000 else { return }
        all.dropFirst(1000).forEach { context.delete($0) }
        try? context.save()
    }
}
