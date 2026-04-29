import AppKit

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect = NSRect(x: 0, y: 0, width: 420, height: 560)) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = true
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.isReleasedWhenClosed = false
        self.minSize = NSSize(width: 320, height: 400)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
