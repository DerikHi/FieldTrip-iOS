import SwiftUI

struct LoginView: View {
    @StateObject private var vm = LoginViewModel()
    @State private var showForgotPassword = false
    @State private var showRegistration = false
    @State private var didAttemptBiometrics = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo / Header
                    VStack(spacing: 12) {
                        Image("LogoLogin")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 112, height: 112)
                            .background(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .fill(.thinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.6),
                                                Color.white.opacity(0.1),
                                                Color.black.opacity(0.1),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
                            .accessibilityLabel("Field Trip Pro logo")

                        Text("Field Trip Pro")
                            .font(.largeTitle.bold())
                    }
                    .padding(.top, 48)

                    // Form
                    VStack(spacing: 16) {
                        // Email
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Email address", text: $vm.email)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                                .accessibilityLabel("Email address")

                            if let error = vm.emailError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.horizontal, 4)
                            }
                        }

                        // Password
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if vm.showPassword {
                                    TextField("Password", text: $vm.password)
                                        .textContentType(.password)
                                } else {
                                    SecureField("Password", text: $vm.password)
                                        .textContentType(.password)
                                }

                                Button(action: { vm.showPassword.toggle() }) {
                                    Image(systemName: vm.showPassword ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityLabel(vm.showPassword ? "Hide password" : "Show password")
                                .frame(minWidth: 44, minHeight: 44)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }

                        // Remember Me + Forgot Password
                        HStack {
                            Toggle("Remember me", isOn: $vm.rememberMe)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .accessibilityLabel("Remember me toggle")

                            Text("Remember me")
                                .font(.subheadline)
                                .foregroundStyle(.primary)

                            Spacer()

                            Button("Forgot password?") {
                                showForgotPassword = true
                            }
                            .font(.subheadline)
                            .frame(minHeight: 44)
                        }
                    }

                    // Error message
                    if let error = vm.errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(error)
                                .font(.subheadline)
                        }
                        .foregroundStyle(.red)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
                    }

                    // Sign In button
                    Button(action: {
                        Task { await vm.signIn() }
                    }) {
                        Group {
                            if vm.isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!vm.isFormValid || vm.isLoading)
                    .accessibilityLabel("Sign in button")

                    // Biometric login
                    let biometry = BiometricService.availableBiometry
                    if biometry != .none && BiometricService.isEnabled {
                        Button(action: { Task { await vm.signInWithBiometrics() } }) {
                            Label("Sign in with \(biometry.displayName)", systemImage: biometry.iconName)
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.bordered)
                        .disabled(vm.isLoading)
                    }

                    // Register link
                    HStack {
                        Text("Don't have an account?")
                            .foregroundStyle(.secondary)
                        Button("Create one") { showRegistration = true }
                            .frame(minHeight: 44)
                    }
                    .font(.subheadline)
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView()
            }
            .sheet(isPresented: $showRegistration) {
                RegistrationView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .emailVerificationSucceeded)) { _ in
                // Verification completed inside the registration sheet —
                // dismiss it so the user lands on the login form and can
                // sign in with their fresh verified credentials.
                showRegistration = false
            }
            .onAppear {
                // Auto-trigger biometric sign-in the first time the Login screen
                // appears, if the user has previously enabled it. Wrapped in a Task
                // with a brief delay so the system prompt fires after the window
                // is fully active (LAContext.evaluatePolicy is unreliable mid-launch).
                // Only attempt once per appearance so a cancel doesn't loop.
                guard !didAttemptBiometrics else { return }
                didAttemptBiometrics = true
                guard BiometricService.availableBiometry != .none,
                      BiometricService.isEnabled else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 350_000_000) // 0.35s
                    await vm.signInWithBiometrics()
                }
            }
        }
    }
}

#Preview {
    LoginView()
}
