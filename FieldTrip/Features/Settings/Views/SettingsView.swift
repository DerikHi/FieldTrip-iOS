import SwiftUI

struct SettingsView: View {
    let user: AuthUser
    @State private var showClearDataConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var showAdminPhotoSelector = false
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Button(action: openContact) {
                    Label("Contact", systemImage: "envelope.fill")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)

                DisclosureGroup {
                    PrivacyPolicyContent()
                        .padding(.top, 8)
                } label: {
                    Label("Privacy", systemImage: "lock.shield")
                        .font(.subheadline.weight(.semibold))
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)

                if let message = statusMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(statusIsError ? .red : .green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background((statusIsError ? Color.red : Color.green).opacity(0.1))
                        .cornerRadius(10)
                }

                if user.isAdmin {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Admin")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Button {
                            showAdminPhotoSelector = true
                        } label: {
                            Label("Choose Photo of the Week", systemImage: "photo.on.rectangle.angled")
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                }

                Button(role: .destructive, action: { showClearDataConfirm = true }) {
                    Label("Clear Data", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)

                Button(role: .destructive, action: { showDeleteAccountConfirm = true }) {
                    Label("Delete Account", systemImage: "person.crop.circle.badge.xmark")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isWorking)

                Spacer(minLength: 32)
            }
            .padding()
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .withHomeToolbar()
        .sheet(isPresented: $showAdminPhotoSelector) {
            AdminPhotoSelectorView()
        }
        .overlay {
            if isWorking {
                Color.black.opacity(0.2).ignoresSafeArea()
                ProgressView("Working…")
                    .padding(20)
                    .background(.thickMaterial)
                    .cornerRadius(12)
            }
        }
        .confirmationDialog(
            "Clear all your data?",
            isPresented: $showClearDataConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear Data", role: .destructive) { Task { await clearData() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all your ratings, check-ins, and photos. Your account stays active.")
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $showDeleteAccountConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your login. Place ratings and photos you added remain anonymously for the community.")
        }
    }

    private func openContact() {
        let subject = "[FieldTrip Feedback]"
        let to = "info@fieldtrippro.com"
        if let url = URL(string: "mailto:\(to)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            UIApplication.shared.open(url)
        }
    }

    private func clearData() async {
        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(apiBaseURL)/api/account/clear-data") else {
            setStatus("Please sign in again.", isError: true)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                setStatus("Your data has been cleared.", isError: false)
            } else {
                setStatus("Could not clear data. Please try again later.", isError: true)
            }
        } catch {
            setStatus("Could not clear data. Please try again later.", isError: true)
        }
    }

    private func deleteAccount() async {
        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(apiBaseURL)/api/account") else {
            setStatus("Please sign in again.", isError: true)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                try? AuthService.shared.signOut()
            } else {
                setStatus("Could not delete account. Please try again later.", isError: true)
            }
        } catch {
            setStatus("Could not delete account. Please try again later.", isError: true)
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

private struct PrivacyPolicyContent: View {
    private let effectiveDate = "May 25, 2026"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("As of \(effectiveDate)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Field Trip Pro is committed to protecting your privacy. This policy explains what data we collect, how we use it, and how we safeguard your information on the app.")
                .font(.subheadline)

            section(
                title: "Information We Collect",
                isHeading: true,
                body: nil
            )
            section(
                title: "Account Information",
                isHeading: false,
                body: "When you create an account we collect sign-in credentials (email and password) and the user name that you specify."
            )
            section(
                title: "User-Generated Content",
                isHeading: false,
                body: "We collect the names, locations, images, comments on, and ratings of the places you add to the app. When other users use the app they will see the User Name you have selected attached to the places you have rated."
            )
            section(
                title: "Social Features",
                isHeading: false,
                body: "We do not collect information (email address, phone number, name, etc.) of the people to whom you send a rated place. Field Trip Pro is not integrated with or in any way feeding information to social media apps."
            )
            section(
                title: "Marketing and Advertising",
                isHeading: false,
                body: "Field Trip Pro does not sell your information, including usage statistics, but may use an aggregate of non-specific user activity to demonstrate to advertisers how the app is being used."
            )
            section(
                title: "How We Use Your Information",
                isHeading: false,
                body: "Field Trip Pro uses Firebase (authentication), Prisma (database), Vercel (application hosting), and GitHub (code repository) to operate the app. Each of these services has their own privacy policies."
            )
            section(
                title: "Data Sharing",
                isHeading: false,
                body: "Field Trip Pro shares your User Name with other users only in connection with the places you have rated. We share only the necessary information with third-party services in order to operate the app. We will only share information in other ways as required by law."
            )
            section(
                title: "Data Retention",
                isHeading: false,
                body: "Your data (User Name, email address) and place ratings are stored in the app and related third-party services only for the time that you are a user. If you should delete your account, only the place ratings and images you have provided will persist for the use of the Field Trip Pro community."
            )
            section(
                title: "Your Rights",
                isHeading: false,
                body: "You have the right to access, correct, delete, and request portability of your data. Please contact us to exercise these rights."
            )
            section(
                title: "Data Security",
                isHeading: false,
                body: "We implement industry standard protocols for ensuring data security, primarily through the third-party applications that support application functionality."
            )
            section(
                title: "Children's Policy",
                isHeading: false,
                body: "Field Trip Pro is not intended as a tool for users under 18. We do not knowingly collect the information of minors."
            )
            section(
                title: "Changes to This Policy",
                isHeading: false,
                body: "We may make changes to this policy. If we do, you will be notified at the email address you used to sign up for the app and with a notification in the app."
            )
        }
    }

    @ViewBuilder
    private func section(title: String, isHeading: Bool, body: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(isHeading ? .title3.bold() : .subheadline.bold())
            if let body {
                Text(body)
                    .font(.subheadline)
            }
        }
        .padding(.top, 8)
    }
}
