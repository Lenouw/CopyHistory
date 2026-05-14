import AppKit
import Combine

/// Manages the paste-queue mode.
/// When active: each clipboard copy is added to an ordered queue.
/// Each ⌘V press pops the next item from the queue into NSPasteboard,
/// then lets the event pass through normally so the target app pastes it.
@MainActor
final class PasteQueueManager: ObservableObject {

    static let shared = PasteQueueManager()

    @Published private(set) var isActive = false
    @Published private(set) var queue: [String] = []
    @Published private(set) var nextIndex: Int = 0

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    // MARK: - Toggle

    func activate() {
        guard !isActive else { return }
        queue = []
        nextIndex = 0
        startEventTap()
        // Only set isActive if tap actually started (Accessibility required)
        if eventTap != nil {
            isActive = true
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        queue = []
        nextIndex = 0
        stopEventTap()
    }

    func toggle() {
        isActive ? deactivate() : activate()
    }

    // MARK: - Queue operations

    /// Called by AppDelegate.saveClip when mode is active.
    func enqueue(_ text: String) {
        queue.append(text)
    }

    /// Called synchronously from the CGEventTap callback (main thread).
    /// Sets NSPasteboard to the next item, advances index.
    /// Deactivates when queue is exhausted.
    func pasteNext() {
        guard nextIndex < queue.count else {
            // No more items — deactivate (event still passes through, app pastes whatever was last)
            deactivate()
            return
        }
        let text = queue[nextIndex]
        nextIndex += 1

        // Suppress ClipboardMonitor so this programmatic change isn't re-recorded
        ClipboardMonitor.suppressNext = true

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        if nextIndex >= queue.count {
            // Last item — defer deactivation so the paste event still goes through
            // before we tear down the tap.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.deactivate()
            }
        }
    }

    // MARK: - CGEventTap

    private func startEventTap() {
        guard AXIsProcessTrusted() else {
            NSLog("[PasteQueue] Accessibility not granted — queue mode unavailable")
            // Prompt user to grant accessibility
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
            _ = AXIsProcessTrustedWithOptions(options)
            return
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: pasteQueueTapCallback,
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            NSLog("[PasteQueue] CGEventTap creation failed")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[PasteQueue] EventTap started ✓")
    }

    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        NSLog("[PasteQueue] EventTap stopped")
    }

    // MARK: - Event handler (called synchronously from C callback on main thread)

    fileprivate func handleKeyEvent(_ event: CGEvent) {
        // V key = keycode 9, must have Command, must NOT have Shift (⇧⌘V = CopyHistory hotkey)
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isCmd = flags.contains(.maskCommand)
        let isShift = flags.contains(.maskShift)
        guard keycode == 9, isCmd, !isShift else { return }

        // Set clipboard to next queued item synchronously — must happen before event
        // continues to the target app so the app reads the new pasteboard content.
        pasteNext()
    }
}

// MARK: - C callback (global function required by CGEventTap API)

private let pasteQueueTapCallback: CGEventTapCallBack = { _, type, event, userInfo -> Unmanaged<CGEvent>? in
    guard type == .keyDown, let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let manager = Unmanaged<PasteQueueManager>.fromOpaque(userInfo).takeUnretainedValue()
    // Callback fires on main thread (tap added to CFRunLoopGetMain), so direct call is safe.
    // MainActor isolation: we're already on main, use a synchronous bridge.
    MainActor.assumeIsolated {
        manager.handleKeyEvent(event)
    }
    return Unmanaged.passUnretained(event)
}
