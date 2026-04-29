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

    private let panelWidth:  CGFloat = 420
    private let panelHeight: CGFloat = 560

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
            let mouseX = NSEvent.mouseLocation.x
            showPanel(centeredAt: mouseX)
        }
    }

    private func showPanel(centeredAt mouseX: CGFloat = -1) {
        buildPanelIfNeeded()
        guard let panel else { return }

        let finalFrame = panelFrame(centeredAt: mouseX)

        // Départ : panel caché sous le bord bas de l'écran, transparent
        let startFrame = NSRect(
            x: finalFrame.minX,
            y: finalFrame.minY - finalFrame.height,
            width: finalFrame.width,
            height: finalFrame.height
        )

        panel.alphaValue = 0
        panel.setFrame(startFrame, display: false)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()

        // Animation spring : slide-up rapide + léger overshoot + settle
        let overshootFrame = NSRect(
            x: finalFrame.minX,
            y: finalFrame.minY + 10,
            width: finalFrame.width,
            height: finalFrame.height
        )

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
            panel.alphaValue = 1  // reset pour le prochain affichage
        })
    }

    // Calcule la frame finale du panel, centré horizontalement sur mouseX
    private func panelFrame(centeredAt mouseX: CGFloat = -1) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame  // exclut menu bar + Dock

        // Centrer sur la position X de la souris (ou centrer sur l'écran si non spécifié)
        let referenceX = mouseX >= 0 ? mouseX : visible.midX
        var x = referenceX - panelWidth / 2

        // Clamp pour ne pas sortir de l'écran
        x = max(visible.minX, min(x, visible.maxX - panelWidth))

        return NSRect(x: x, y: visible.minY, width: panelWidth, height: panelHeight)
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
