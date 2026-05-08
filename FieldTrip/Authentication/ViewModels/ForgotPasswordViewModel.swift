import Foundation
import SwiftUI

@MainActor
final class ForgotPasswordViewModel: ObservableObject {
    @Published var email = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    private let authService: AuthServiceProtocol
    private let haptics = UINotificationFeedbackGenerator()

    init(authService: AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }

    var emailError: String? {
        guard !email.isEmpty else { return nil }
        return ValidationService.isValidEmail(email) ? nil : "Enter a valid email address."
    }

    var canSubmit: Bool {
        ValidationService.isValidEmail(email) && !isLoading
    }

    func sendResetLink() async {
        guard canSubmit else { return }
        haptics.prepare()

        isLoading = true
        errorMessage = nil
        successMessage = nil

        defer { isLoading = false }

        do {
            try await authService.sendPasswordReset(email: email.lowercased().trimmingCharacters(in: .whitespaces))
            successMessage = "Reset link sent to \(email). Check your inbox."
        } catch {
            haptics.notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
}
