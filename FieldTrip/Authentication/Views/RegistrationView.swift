import SwiftUI

struct RegistrationView: View {
    @StateObject private var vm = RegistrationViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Create Account")
                            .font(.largeTitle.bold())
                        Text("Join the FieldTrip community")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    VStack(spacing: 16) {
                        // User Name
                        FormField(
                            title: "User Name",
                            placeholder: "Jane Doe, FieldStar, or whatever you'd like",
                            text: $vm.fullName,
                            contentType: .name,
                            keyboardType: .default,
                            error: vm.nameError
                        )

                        // Email
                        FormField(
                            title: "Email",
                            placeholder: "jane@university.edu",
                            text: $vm.email,
                            contentType: .emailAddress,
                            keyboardType: .emailAddress,
                            error: vm.emailError,
                            autocapitalize: false
                        )

                        // Password
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Password")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            PasswordField(text: $vm.password, show: $vm.showPassword, placeholder: "Create password")

                            if let error = vm.passwordError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 4)
                            }

                            // Password strength indicator
                            if !vm.password.isEmpty {
                                PasswordStrengthView(strength: vm.passwordStrength)
                            }
                        }

                        // Confirm Password
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Confirm Password")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            PasswordField(text: $vm.confirmPassword, show: $vm.showConfirmPassword, placeholder: "Repeat password")

                            if let error = vm.confirmPasswordError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 4)
                            }
                        }
                    }

                    // Error
                    if let error = vm.errorMessage {
                        ErrorBanner(message: error)
                    }

                    // Create Account
                    Button(action: {
                        Task { await vm.createAccount() }
                    }) {
                        Group {
                            if vm.isLoading {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                            } else {
                                Text("Create Account").fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!vm.isFormValid || vm.isLoading)

                    Button("Already have an account? Sign in") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(isPresented: $vm.navigateToVerification) {
                EmailVerificationView()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Sub-components

private struct FormField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let contentType: UITextContentType
    let keyboardType: UIKeyboardType
    let error: String?
    var autocapitalize: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textContentType(contentType)
                .autocapitalization(autocapitalize ? .words : .none)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .accessibilityLabel(title)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct PasswordField: View {
    @Binding var text: String
    @Binding var show: Bool
    let placeholder: String

    var body: some View {
        HStack {
            if show {
                TextField(placeholder, text: $text).textContentType(.password)
            } else {
                SecureField(placeholder, text: $text).textContentType(.password)
            }

            Button(action: { show.toggle() }) {
                Image(systemName: show ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel(show ? "Hide password" : "Show password")
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

struct PasswordStrengthView: View {
    let strength: PasswordStrength

    var color: Color {
        switch strength {
        case .weak: return .red
        case .fair: return .orange
        case .strong: return .green
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * strength.progress, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: strength)
                }
            }
            .frame(height: 6)

            Text(strength.displayName)
                .font(.caption.bold())
                .foregroundStyle(color)
                .frame(width: 50, alignment: .trailing)
        }
        .padding(.horizontal, 4)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .font(.subheadline)
        }
        .foregroundStyle(.red)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    RegistrationView()
}
