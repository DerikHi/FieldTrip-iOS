import SwiftUI

struct ForgotPasswordView: View {
    @StateObject private var vm = ForgotPasswordViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "lock.rotation")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                VStack(spacing: 8) {
                    Text("Reset Password")
                        .font(.title.bold())
                    Text("Enter your email and we'll send a reset link.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

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
                .padding(.horizontal, 24)

                if let error = vm.errorMessage {
                    ErrorBanner(message: error)
                        .padding(.horizontal, 24)
                }

                if let success = vm.successMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(success)
                            .font(.subheadline)
                    }
                    .foregroundStyle(.green)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal, 24)
                }

                VStack(spacing: 16) {
                    Button(action: {
                        Task { await vm.sendResetLink() }
                    }) {
                        Group {
                            if vm.isLoading {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                            } else {
                                Text("Send Reset Link").fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!vm.canSubmit)
                    .padding(.horizontal, 24)

                    Button("Back to Login") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                }

                Spacer()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ForgotPasswordView()
}
