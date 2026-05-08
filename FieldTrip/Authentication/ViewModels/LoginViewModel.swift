import Foundation
import SwiftUI

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var rememberMe = false
    @Published var showPassword = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var navigateToHome = false

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

        do {
            _ = try await authService.signIn(email: email.lowercased().trimmingCharacters(in: .whitespaces), password: password)
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
