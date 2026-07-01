import SwiftUI

/// Shows the signed-in user's account details and lets them edit their public
/// User Name. Saving updates the backend (which every entry / leaderboard /
/// search result reads via a join) and the Firebase display name.
struct AccountInfoView: View {
    let user: AuthUser

    @Environment(\.dismiss) private var dismiss

    @State private var userName: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSave = false

    init(user: AuthUser) {
        self.user = user
        _userName = State(initialValue: user.fullName)
    }

    private var trimmedName: String {
        userName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nameError: String? {
        guard !trimmedName.isEmpty else { return nil }
        if !ValidationService.isValidName(trimmedName) {
            return "User Name must be at least 2 characters."
        }
        let moderation = ContentModerationService.checkText(trimmedName)
        if !moderation.isClean { return moderation.message }
        return nil
    }

    private var canSave: Bool {
        nameError == nil && !trimmedName.isEmpty && trimmedName != user.fullName && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("User Name", text: $userName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    if let nameError {
                        Text(nameError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("User Name")
                } footer: {
                    Text("This is the name shown on your entries, the Check In Leaderboard, Photo of the Week, and anywhere your contributions appear. Changing it updates them everywhere.")
                }

                Section("Account") {
                    LabeledContent("Email", value: user.email)
                    if let org = user.organization, !org.isEmpty {
                        LabeledContent("Organization", value: org)
                    }
                    LabeledContent("Member Since",
                                   value: user.createdAt.formatted(date: .abbreviated, time: .omitted))
                }

                if didSave {
                    Text("User Name updated.")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Account Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Saving…")
                        .padding(20)
                        .background(.thickMaterial)
                        .cornerRadius(12)
                }
            }
        }
    }

    private func save() async {
        errorMessage = nil
        didSave = false

        // Re-check moderation at submit time (the live check drives the button,
        // this guards against races / whitespace-only edits).
        let moderation = ContentModerationService.checkText(trimmedName)
        guard moderation.isClean else {
            errorMessage = moderation.message
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await AuthService.shared.updateDisplayName(trimmedName)
            didSave = true
        } catch {
            errorMessage = "Could not update your User Name. Please try again."
        }
    }
}
