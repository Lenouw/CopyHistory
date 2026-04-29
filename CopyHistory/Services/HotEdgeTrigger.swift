import AppKit

// Surveille les scroll events dans le coin bas-gauche de l'écran.
// Quand la souris est dans la zone chaude et que l'utilisateur fait défiler
// vers le haut avec deux doigts, on déclenche l'action.
// Même principe qu'Unclutter qui surveille le coin en haut.
final class HotEdgeTrigger {
    var onScrollUp: (() -> Void)?    // déclencher l'affichage
    var onScrollDown: (() -> Void)?  // déclencher le masquage

    private var monitor: Any?
    private var accumulator: CGFloat = 0
    private var lastTriggerTime: Date = .distantPast

    // Zone chaude : x < hotX pixels depuis le bord gauche
    // (pas de contrainte Y stricte — toute la hauteur côté gauche fonctionne,
    //  sauf le menu bar qui reste réservé à d'autres apps)
    private let hotZoneX: CGFloat = 50
    private let triggerThreshold: CGFloat = 30   // delta accumulé pour déclencher
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
        guard let screen = NSScreen.main else { return }

        // Zone chaude : bord gauche de l'écran
        guard loc.x < hotZoneX else {
            accumulator = 0
            return
        }

        // Exclure le menu bar (zone en haut)
        let menuBarH: CGFloat = 24
        guard loc.y < screen.frame.height - menuBarH else {
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
