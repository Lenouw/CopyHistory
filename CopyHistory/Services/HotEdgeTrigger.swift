import AppKit

// Surveille les scroll events sur TOUT le bord bas de l'écran.
// Quand la souris est dans les derniers pixels du bas (n'importe où en X)
// et que l'utilisateur fait défiler vers le haut avec deux doigts, on déclenche.
// Même principe qu'Unclutter qui surveille le bord haut.
final class HotEdgeTrigger {
    var onScrollUp: (() -> Void)?

    private var monitor: Any?
    private var accumulator: CGFloat = 0
    private var lastTriggerTime: Date = .distantPast

    // Zone chaude : tout le bas de l'écran, dans les hotZoneY premiers pixels
    private let hotZoneY: CGFloat = 5             // coller au bord bas
    private let triggerThreshold: CGFloat = 30    // delta accumulé pour déclencher
    private let cooldown: TimeInterval = 0.8      // évite les doubles déclenchements

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private func handleScroll(_ event: NSEvent) {
        // mouseLocation : coordonnées écran, (0,0) en bas-gauche
        let loc = NSEvent.mouseLocation
        guard NSScreen.main != nil else { return }

        // Zone chaude : tout le bord bas de l'écran (y proche de 0)
        guard loc.y <= hotZoneY else {
            accumulator = 0
            return
        }

        // Ignorer le momentum (défilement inertiel après le geste)
        guard event.momentumPhase == .none else { return }

        // scrollingDeltaY > 0 = doigts vers le haut (natural scrolling activé)
        // scrollingDeltaY < 0 = doigts vers le bas
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8

        if delta > 0 {
            accumulator += delta
        } else {
            // Réinitialise si l'utilisateur change de direction
            accumulator = max(0, accumulator + delta * 0.5)
        }

        guard Date().timeIntervalSince(lastTriggerTime) > cooldown else { return }

        if accumulator >= triggerThreshold {
            accumulator = 0
            lastTriggerTime = Date()
            DispatchQueue.main.async { [weak self] in
                self?.onScrollUp?()
            }
        }
    }
}
