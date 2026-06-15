import SwiftUI
import CoreLocation

struct SettingsView: View {
    let user: AuthUser
    @State private var showClearDataConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var showAdminPhotoSelector = false
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @ObservedObject private var alerts = LocationAlertService.shared

    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Button(action: openContact) {
                    Label("Contact", systemImage: "envelope.fill")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)

                Button(action: { try? AuthService.shared.signOut() }) {
                    Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)

                locationServicesCard

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
        .presentationDragIndicator(.visible)
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
            Text("This permanently deletes your account, your User Name, your email address, and every rating, comment, and photo you have added. Nothing can be recovered.")
        }
    }

    /// In-app Location Services toggle + a read-out of the current iOS
    /// system permission state, so the user can both see and change their
    /// location setting without leaving Settings.
    @ViewBuilder
    private var locationServicesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Location Services", systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { alerts.locationPermissionGranted },
                    set: { newValue in
                        if newValue {
                            // notDetermined → request prompt; .denied → only
                            // recoverable through iOS Settings, send them there.
                            switch alerts.authorizationStatus {
                            case .notDetermined:
                                alerts.enableNearbyAlerts()
                            case .denied, .restricted:
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            default:
                                break
                            }
                        } else {
                            // Programmatic revoke isn't possible — point the
                            // user at iOS Settings so they can flip it there.
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                ))
                .labelsHidden()
            }

            HStack(spacing: 6) {
                Image(systemName: systemIcon)
                    .foregroundStyle(systemColor)
                Text("iOS setting: \(systemStatusLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if alerts.authorizationStatus == .denied || alerts.authorizationStatus == .restricted {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open iOS Settings to enable location")
                        .font(.caption.weight(.medium))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private var systemStatusLabel: String {
        switch alerts.authorizationStatus {
        case .notDetermined: return "Not Set"
        case .denied: return "Never"
        case .restricted: return "Restricted"
        case .authorizedWhenInUse: return "While Using the App"
        case .authorizedAlways: return "Always"
        @unknown default: return "Unknown"
        }
    }

    private var systemIcon: String {
        switch alerts.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return "checkmark.circle.fill"
        case .denied, .restricted: return "xmark.circle.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private var systemColor: Color {
        switch alerts.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return .green
        case .denied, .restricted: return .orange
        default: return .secondary
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
            setStatus("An error has occurred, please log in again.", isError: true)
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
                setStatus("An error has occurred, please log in again.", isError: true)
            }
        } catch {
            setStatus("An error has occurred, please log in again.", isError: true)
        }
    }

    private func deleteAccount() async {
        isWorking = true
        statusMessage = nil
        defer { isWorking = false }

        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(apiBaseURL)/api/account") else {
            setStatus("An error has occurred, please log in again.", isError: true)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                wipeLocalUserData()
                try? AuthService.shared.signOut()
            } else {
                setStatus("An error has occurred, please log in again.", isError: true)
            }
        } catch {
            setStatus("An error has occurred, please log in again.", isError: true)
        }
    }

    /// Removes every trace of the user from this device after the backend
    /// confirms the account has been deleted. Wipes all keychain items
    /// (including saved biometric credentials) and every UserDefaults key
    /// the app writes.
    private func wipeLocalUserData() {
        KeychainService.wipeEverything()
        let defaults = UserDefaults.standard
        let keysToClear = [
            "biometric_login_enabled",
            "remembered_email",
            "offline_insight_queue",
            "locationPrimingChoice",
            "locationPrimingUserId",
            "locationLaunchCount",
            "locationAlertCooldowns",
        ]
        keysToClear.forEach { defaults.removeObject(forKey: $0) }
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
                body: "Your data (User Name, email address), ratings, comments, and photos are stored in databases outside of the app and used by the app only while you have a user account. Should you decide to delete your account via the Delete Account button on the Settings menu, all content you have added to the app, your User Name, and your email address will be deleted."
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
