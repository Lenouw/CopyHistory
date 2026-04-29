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
    private var clipMonitor: ClipboardMonitor?
    private var hotEdge: HotEdgeTrigger?
    private var modelContainer: ModelContainer?

    // App active AVANT l'ouverture du panel — pour Direct Paste
    private var previousApp: NSRunningApplication?

    // Dimensions et position du panel (bas-gauche, au-dessus du Dock)
    private let panelWidth:  CGFloat = 420
    private let panelHeight: CGFloat = 560
    private let panelMarginLeft: CGFloat = 0   // collé au bord gauche

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupModelContainer()
        setupStatusItem()
        setupClipboardMonitor()
        setupHotEdgeTrigger()
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
        clipMonitor = ClipboardMonitor()
        clipMonitor?.onNewItem = { [weak self] data in
            self?.saveClip(data)
        }
        clipMonitor?.start()
    }

    private func setupHotEdgeTrigger() {
        hotEdge = HotEdgeTrigger()
        hotEdge?.onScrollUp = { [weak self] in
            guard let self else { return }
            if self.panel?.isVisible == true {
                self.hidePanel()
            } else {
                self.previousApp = NSWorkspace.shared.frontmostApplication
                self.showPanel()
            }
        }
        hotEdge?.start()
    }

    private func setupHotkey() {
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.togglePanel()
        }
    }

    private func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Panel management

    @objc func togglePanel() {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            previousApp = NSWorkspace.shared.frontmostApplication
            showPanel()
        }
    }

    private func showPanel() {
        buildPanelIfNeeded()
        guard let panel else { return }

        let finalFrame = panelFrame()

        // Départ : panel caché sous le bord bas de l'écran
        let startFrame = NSRect(
            x: finalFrame.minX,
            y: finalFrame.minY - finalFrame.height,
            width: finalFrame.width,
            height: finalFrame.height
        )

        panel.setFrame(startFrame, display: false)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        // Slide-up animation
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    private func hidePanel() {
        guard let panel else { return }
        let hiddenY = panel.frame.minY - panel.frame.height

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrameOrigin(NSPoint(x: panel.frame.minX, y: hiddenY))
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // Calcule la frame finale du panel : bas-gauche, juste au-dessus du Dock
    private func panelFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame   // exclut menu bar + Dock
        return NSRect(
            x: visible.minX + panelMarginLeft,
            y: visible.minY,
            width: panelWidth,
            height: panelHeight
        )
    }

    private func buildPanelIfNeeded() {
        guard panel == nil, let container = modelContainer else { return }
        panel = FloatingPanel()
        let view = ContentView(onPaste: { [weak self] item in
            self?.directPaste(item)
        })
        .modelContainer(container)
        panel?.contentViewController = NSHostingController(rootView: view)
    }

    // MARK: - Direct Paste

    private func directPaste(_ item: ClipboardItem) {
        copyToClipboard(item)
        let appToRestore = previousApp
        hidePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
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

        if data.type != .image {
            var descriptor = FetchDescriptor<ClipboardItem>(
                sortBy: [SortDescriptor(\ClipboardItem.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            if let last = try? context.fetch(descriptor).first,
               last.textContent == data.text { return }
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
