import Foundation
import SwiftUI
import Combine

@MainActor
final class RegistrationViewModel: ObservableObject {
    @Published var fullName = ""
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var showPassword = false
    @Published var showConfirmPassword = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var navigateToVerification = false

    private let authService: AuthServiceProtocol
    private let haptics = UINotificationFeedbackGenerator()

    init(authService: AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }

    // MARK: - Validation

    var nameError: String? {
        guard !fullName.isEmpty else { return nil }
        if !ValidationService.isValidName(fullName) { return "Name must be at least 2 characters." }
        let moderation = ContentModerationService.checkText(fullName)
        if !moderation.isClean { return moderation.message }
        return nil
    }

    var emailError: String? {
        guard !email.isEmpty else { return nil }
        return ValidationService.isValidEmail(email) ? nil : "Enter a valid email address."
    }

    var passwordStrength: PasswordStrength {
        ValidationService.passwordStrength(password)
    }

    var passwordError: String? {
        guard !password.isEmpty else { return nil }
        if password.count < 8 { return "Password must be at least 8 characters." }
        if !password.contains(where: \.isUppercase) { return "Add at least one uppercase letter." }
        if !password.contains(where: \.isNumber) { return "Add at least one number." }
        if password.range(of: #"[!@#$%^&*()_+\-=\[\]{}|;':",.<>?/\\`~]"#, options: .regularExpression) == nil {
            return "Add at least one special character."
        }
        return nil
    }

    var confirmPasswordError: String? {
        guard !confirmPassword.isEmpty else { return nil }
        return ValidationService.passwordsMatch(password, confirmPassword) ? nil : "Passwords do not match."
    }

    var isFormValid: Bool {
        nameError == nil && !fullName.isEmpty &&
        emailError == nil && !email.isEmpty &&
        passwordError == nil && !password.isEmpty &&
        confirmPasswordError == nil && !confirmPassword.isEmpty
    }

    // MARK: - Actions

    func createAccount() async {
        guard isFormValid, !isLoading else { return }
        haptics.prepare()

        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            _ = try await authService.register(
                email: email.lowercased().trimmingCharacters(in: .whitespaces),
                password: password,
                fullName: fullName.trimmingCharacters(in: .whitespaces)
            )
            navigateToVerification = true
        } catch {
            haptics.notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
}
