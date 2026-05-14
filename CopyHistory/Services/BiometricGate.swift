import Foundation
import LocalAuthentication

/// Biometric gate to protect access to the clipboard panel.
/// When enabled, requires Touch ID (or macOS password fallback) before opening the panel
/// if more than `timeoutMinutes` have elapsed since the last successful authentication.
@MainActor
final class BiometricGate {

    static let shared = BiometricGate()

    private let keyEnabled  = "biometricEnabled"
    private let keyTimeout  = "biometricTimeoutMinutes"

    // In-memory only — must re-auth at every app launch
    private var lastAuthDate: Date?

    private init() {
        // Defaults: enabled, 15 min
        UserDefaults.standard.register(defaults: [
            keyEnabled: true,
            keyTimeout: 15
        ])
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: keyEnabled)
    }

    var timeoutMinutes: Int {
        UserDefaults.standard.integer(forKey: keyTimeout)
    }

    /// True if biometric gate is enabled AND grace period has expired (or never authenticated).
    func requiresAuth() -> Bool {
        guard isEnabled else { return false }
        guard let last = lastAuthDate else { return true }
        // Timeout 0 = "Always" — every panel open requires auth
        if timeoutMinutes == 0 { return true }
        let elapsed = Date().timeIntervalSince(last)
        return elapsed > TimeInterval(timeoutMinutes * 60)
    }

    /// Prompt Touch ID (with password fallback). Resolves with true on success.
    /// Falls back gracefully if no biometric hardware: uses macOS password.
    func authenticate(reason: String = "Déverrouiller votre historique CopyHistory",
                      completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedFallbackTitle = "Saisir le mot de passe"

        // .deviceOwnerAuthentication = Touch ID with macOS password fallback
        // (works on Macs without Touch ID — directly prompts password)
        var error: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: &error) else {
            // No auth available at all — fail closed (don't show panel)
            NSLog("[BiometricGate] Cannot evaluate policy: \(error?.localizedDescription ?? "unknown")")
            completion(false)
            return
        }

        context.evaluatePolicy(policy, localizedReason: reason) { [weak self] success, evalError in
            DispatchQueue.main.async {
                if success {
                    self?.lastAuthDate = Date()
                    completion(true)
                } else {
                    NSLog("[BiometricGate] Auth failed: \(evalError?.localizedDescription ?? "user cancelled")")
                    completion(false)
                }
            }
        }
    }

    /// Reset grace period — next panel open will require auth again.
    /// Useful when user disables and re-enables the gate.
    func resetGracePeriod() {
        lastAuthDate = nil
    }
}
