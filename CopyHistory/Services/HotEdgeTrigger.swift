import AppKit
import CoreGraphics

// Déclenche l'action quand la souris est sur le bord bas de l'écran
// et que l'utilisateur fait défiler vers le haut avec deux doigts.
// Utilise CGEventTap (si Accessibility accordée) ou NSEvent global monitor en fallback.
final class HotEdgeTrigger {
    var onScrollUp: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var nsMonitor: Any?

    private var accumulator: CGFloat = 0
    private var lastTriggerTime: Date = .distantPast

    // Zone chaude : 80 derniers pixels physiques du bas de l'écran
    // (couvre tout le Dock + un peu de marge)
    private let hotZoneY: CGFloat = 80
    private let triggerThreshold: CGFloat = 12
    private let cooldown: TimeInterval = 0.8

    func start() {
        if AXIsProcessTrusted() {
            startCGEventTap()
        } else {
            // Fallback : NSEvent global monitor (scroll ne nécessite pas Accessibility)
            startNSEventMonitor()
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        if let m = nsMonitor {
            NSEvent.removeMonitor(m)
            nsMonitor = nil
        }
    }

    // MARK: - CGEventTap (primary)

    private func startCGEventTap() {
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotEdgeTapCallback,
            userInfo: selfPtr
        )

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("[HotEdge] CGEventTap démarré ✓")
        } else {
            print("[HotEdge] CGEventTap échoué → fallback NSEvent")
            startNSEventMonitor()
        }
    }

    // MARK: - NSEvent fallback

    private func startNSEventMonitor() {
        nsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return }
            let loc = NSEvent.mouseLocation
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8
            let isMomentum = !event.momentumPhase.isEmpty
            self.process(nsY: loc.y, deltaY: delta, isMomentum: isMomentum)
        }
        print("[HotEdge] NSEvent global monitor démarré ✓")
    }

    // MARK: - CGEvent handler (appelé depuis le callback C)

    fileprivate func handleCGEvent(_ event: CGEvent) {
        guard let screen = NSScreen.main else { return }

        // CGEvent : (0,0) = haut-gauche → on convertit en coordonnées NS (0,0) = bas-gauche
        let cgY = event.location.y
        let nsY = screen.frame.height - cgY

        // scrollWheelEventPointDeltaAxis1 = delta précis trackpad, axe vertical
        let rawDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)

        // Exclure le momentum (inertiel)
        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        let isMomentum = momentumPhase != 0

        print("[HotEdge] nsY=\(Int(nsY)) Δ=\(Int(rawDelta)) momentum=\(isMomentum) phase=\(phase) acc=\(Int(accumulator))")

        process(nsY: nsY, deltaY: CGFloat(rawDelta), isMomentum: isMomentum)
    }

    // MARK: - Logique commune

    private func process(nsY: CGFloat, deltaY: CGFloat, isMomentum: Bool) {
        guard !isMomentum else { return }

        // Zone chaude : bord bas de l'écran
        guard nsY < hotZoneY else {
            if accumulator > 0 { accumulator = 0 }
            return
        }

        // Scroll vers le haut = deltaY > 0 (doigts qui montent, natural scrolling activé)
        // On accepte aussi le sens inverse au cas où natural scrolling serait désactivé
        let magnitude: CGFloat
        if deltaY > 0 {
            magnitude = deltaY
            accumulator += magnitude
        } else if deltaY < 0 {
            // Peut-être que natural scrolling est désactivé → on prend la valeur absolue
            magnitude = abs(deltaY)
            accumulator += magnitude
        } else {
            return
        }

        guard Date().timeIntervalSince(lastTriggerTime) > cooldown else { return }

        if accumulator >= triggerThreshold {
            print("[HotEdge] 🚀 DÉCLENCHÉ acc=\(Int(accumulator))")
            accumulator = 0
            lastTriggerTime = Date()
            DispatchQueue.main.async { [weak self] in
                self?.onScrollUp?()
            }
        }
    }
}

// MARK: - C callback pour CGEventTap (doit être une fonction globale ou let)

private let hotEdgeTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard type == .scrollWheel, let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let trigger = Unmanaged<HotEdgeTrigger>.fromOpaque(userInfo).takeUnretainedValue()
    trigger.handleCGEvent(event)
    return Unmanaged.passUnretained(event)
}
