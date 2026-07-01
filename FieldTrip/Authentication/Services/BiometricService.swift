import Foundation
import LocalAuthentication

@MainActor
enum BiometricService {
    private static let enabledKey = "biometric_login_enabled"

    /// Credentials the user just signed in with, held in memory only so
    /// the splash router can offer to enable biometrics before navigating
    /// to the home shell. Cleared as soon as the prompt is resolved.
    static var pendingCredentials: (email: String, password: String)?

    enum BiometryKind {
        case faceID
        case touchID
        case opticID
        case none

        var displayName: String {
            switch self {
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            case .opticID: return "Optic ID"
            case .none: return "Biometrics"
            }
        }

        var iconName: String {
            switch self {
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            case .opticID: return "opticid"
            case .none: return "lock.shield"
            }
        }
    }

    /// What kind of biometry is available on this device, if any.
    static var availableBiometry: BiometryKind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    /// Whether the user has opted into biometric login. This reads only the
    /// enablement flag — never the protected credentials — so checking it does
    /// not trigger a biometric prompt.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func enable(email: String, password: String) {
        // Stored behind Secure Enclave biometric access control, so the raw
        // password can't be read without a live Face ID / Touch ID match.
        KeychainService.storeBiometricProtected(email, for: .biometricEmail)
        KeychainService.storeBiometricProtected(password, for: .biometricPassword)
        UserDefaults.standard.set(true, forKey: enabledKey)
    }

    static func disable() {
        KeychainService.delete(for: .biometricEmail)
        KeychainService.delete(for: .biometricPassword)
        UserDefaults.standard.set(false, forKey: enabledKey)
    }

    /// Prompt the user for biometric auth and, on success, return saved credentials.
    static func authenticate(reason: String) async -> (email: String, password: String)? {
        let context = LAContext()
        // Let the Keychain reads below reuse this successful evaluation instead
        // of triggering a second biometric prompt.
        context.touchIDAuthenticationAllowableReuseDuration = LATouchIDAuthenticationMaximumAllowableReuseDuration
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            // Reuse the just-authenticated context so the Keychain reads don't
            // prompt a second time.
            guard ok,
                  let email = KeychainService.retrieve(for: .biometricEmail, context: context),
                  let password = KeychainService.retrieve(for: .biometricPassword, context: context) else {
                // Biometry succeeded but the stored credentials are gone or
                // were invalidated (e.g. Face ID / Touch ID was re-enrolled).
                // Clear the stale enablement so the UI stops offering it.
                disable()
                return nil
            }
            // Upgrade credentials saved by an older build (stored without
            // Secure Enclave access control) to protected storage. Idempotent
            // for already-protected items; the write does not prompt.
            KeychainService.storeBiometricProtected(email, for: .biometricEmail)
            KeychainService.storeBiometricProtected(password, for: .biometricPassword)
            return (email, password)
        } catch {
            return nil
        }
    }
}
