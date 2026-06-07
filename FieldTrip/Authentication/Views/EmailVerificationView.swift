import SwiftUI
import Combine
import FirebaseAuth

extension Notification.Name {
    /// Posted when the user successfully verifies their email on the
    /// EmailVerificationView screen. LoginView listens for this so the
    /// registration sheet (which contains EmailVerificationView) can be
    /// dismissed back to the login form.
    static let emailVerificationSucceeded = Notification.Name("FTP.emailVerificationSucceeded")
}

struct EmailVerificationView: View {
    @StateObject private var vm = EmailVerificationViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showSuccess = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Illustration
            Image(systemName: showSuccess ? "checkmark.seal.fill" : "envelope.badge.fill")
                .font(.system(size: 80))
                .foregroundStyle(showSuccess ? Color.green : Color.accentColor)
                .symbolEffect(.pulse, isActive: !showSuccess)

            // Text
            VStack(spacing: 12) {
                Text(showSuccess ? "Email Verified" : "Check Your Email")
                    .font(.title.bold())

                if showSuccess {
                    Text("You're all set. Sign in to continue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("We sent a verification link to\n\(vm.email)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Auto-poll status
            if vm.isPolling {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                    Text("Waiting for verification…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Error
            if let error = vm.errorMessage {
                ErrorBanner(message: error)
                    .padding(.horizontal)
            }

            // Actions
            VStack(spacing: 16) {
                Button(action: {
                    Task { await vm.checkVerification() }
                }) {
                    Group {
                        if vm.isCheckingManually {
                            ProgressView().progressViewStyle(.circular).tint(.white)
                        } else {
                            Text("I've Verified — Continue")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isCheckingManually)

                Button(action: {
                    Task { await vm.resendEmail() }
                }) {
                    if vm.resendCooldown > 0 {
                        Text("Resend in \(vm.resendCooldown)s")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(vm.isResending ? "Sending…" : "Resend Email")
                    }
                }
                .frame(minHeight: 44)
                .disabled(vm.resendCooldown > 0 || vm.isResending)

                Button("Back to Login") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .onAppear { vm.startPolling() }
        .onDisappear { vm.stopPolling() }
        .onChange(of: vm.isVerified) { _, verified in
            guard verified else { return }
            // Sign out so the next signIn() mints a fresh ID token that
            // carries the new email_verified claim, then pop back to the
            // login screen. Brief success state shown before dismissing.
            showSuccess = true
            try? AuthService.shared.signOut()
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                NotificationCenter.default.post(name: .emailVerificationSucceeded, object: nil)
                dismiss()
            }
        }
    }
}

@MainActor
final class EmailVerificationViewModel: ObservableObject {
    @Published var isVerified = false
    @Published var isPolling = false
    @Published var isCheckingManually = false
    @Published var isResending = false
    @Published var resendCooldown = 0
    @Published var errorMessage: String?

    var email: String {
        AuthService.shared.currentFirebaseUser?.email ?? "your email"
    }

    private var pollingTask: Task<Void, Never>?
    private var cooldownTask: Task<Void, Never>?
    private let authService: AuthServiceProtocol

    init(authService: AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }

    func startPolling() {
        isPolling = true
        pollingTask = Task {
            for _ in 0..<10 { // max 10 attempts
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }

                let verified = try? await authService.reloadUser()
                if verified == true {
                    isPolling = false
                    isVerified = true
                    return
                }
            }
            isPolling = false
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func checkVerification() async {
        isCheckingManually = true
        errorMessage = nil
        defer { isCheckingManually = false }

        let verified = (try? await authService.reloadUser()) ?? false
        if verified {
            isVerified = true
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = "Email not yet verified. Check your inbox and click the link."
        }
    }

    func resendEmail() async {
        guard resendCooldown == 0 else { return }
        isResending = true
        defer { isResending = false }

        do {
            try await authService.sendEmailVerification()
            startCooldown()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startCooldown() {
        resendCooldown = 60
        cooldownTask?.cancel()
        cooldownTask = Task {
            while resendCooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { resendCooldown -= 1 }
            }
        }
    }
}
