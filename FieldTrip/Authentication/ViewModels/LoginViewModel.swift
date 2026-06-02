import Foundation
import SwiftUI
import Combine

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var rememberMe = false
    @Published var showPassword = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var navigateToHome = false
    @Published var authenticatedUser: AuthUser?

    private let authService: AuthServiceProtocol
    private let haptics = UINotificationFeedbackGenerator()

    init(authService: AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
        loadRememberedEmail()
    }

    var emailError: String? {
        guard !email.isEmpty else { return nil }
        return ValidationService.isValidEmail(email) ? nil : "Enter a valid email address."
    }

    var isFormValid: Bool {
        ValidationService.isValidEmail(email) && !password.isEmpty
    }

    func signIn() async {
        guard isFormValid, !isLoading else { return }
        haptics.prepare()

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        if rememberMe {
            UserDefaults.standard.set(email, forKey: "remembered_email")
        } else {
            UserDefaults.standard.removeObject(forKey: "remembered_email")
        }

        let normalizedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)

        // Stash credentials before signing in so SplashRouterView can offer
        // to enable biometrics after authentication completes but before
        // navigation to the home shell.
        if BiometricService.availableBiometry != .none && !BiometricService.isEnabled {
            BiometricService.pendingCredentials = (email: normalizedEmail, password: password)
        }

        do {
            let user = try await authService.signIn(email: normalizedEmail, password: password)
            authenticatedUser = user
            navigateToHome = true
        } catch {
            BiometricService.pendingCredentials = nil
            haptics.notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    func signInWithBiometrics() async {
        let kind = BiometricService.availableBiometry
        guard kind != .none, BiometricService.isEnabled, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard let creds = await BiometricService.authenticate(reason: "Sign in to Field Trip Pro") else {
            errorMessage = "Could not authenticate with \(kind.displayName)."
            return
        }
        do {
            let user = try await authService.signIn(email: creds.email, password: creds.password)
            authenticatedUser = user
            navigateToHome = true
        } catch {
            haptics.notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    func forgotPassword() async {
        guard ValidationService.isValidEmail(email) else {
            errorMessage = "Enter your email address first."
            return
        }
        // Navigation handled by the view via sheet/navigation
    }

    private func loadRememberedEmail() {
        if let saved = UserDefaults.standard.string(forKey: "remembered_email") {
            email = saved
            rememberMe = true
        }
    }
}
