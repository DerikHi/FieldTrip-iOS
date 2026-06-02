import SwiftUI
import FirebaseAuth

struct SplashRouterView: View {
    @State private var authState: AuthState = .loading
    @State private var currentUser: AuthUser?
    @State private var pendingBiometricUser: AuthUser?

    enum AuthState {
        case loading
        case unauthenticated
        case authenticated(AuthUser)
    }

    var body: some View {
        Group {
            switch authState {
            case .loading:
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .accessibilityLabel("Loading")

            case .unauthenticated:
                LoginView()

            case .authenticated(let user):
                if pendingBiometricUser != nil {
                    // Stay on a neutral background while the alert is up so the
                    // user sees the prompt without the home shell flashing first.
                    Color(.systemBackground)
                        .ignoresSafeArea()
                        .alert(
                            "Enable \(BiometricService.availableBiometry.displayName)?",
                            isPresented: Binding(
                                get: { pendingBiometricUser != nil },
                                set: { if !$0 { pendingBiometricUser = nil } }
                            )
                        ) {
                            Button("Enable") { enableBiometricAndProceed() }
                            Button("Not Now", role: .cancel) { skipBiometricAndProceed() }
                        } message: {
                            Text("Use \(BiometricService.availableBiometry.displayName) to sign in faster next time.")
                        }
                } else {
                    MainShell(user: user)
                }
            }
        }
        .onAppear { checkAuthState() }
    }

    private func enableBiometricAndProceed() {
        if let creds = BiometricService.pendingCredentials {
            BiometricService.enable(email: creds.email, password: creds.password)
        }
        BiometricService.pendingCredentials = nil
        pendingBiometricUser = nil
    }

    private func skipBiometricAndProceed() {
        BiometricService.pendingCredentials = nil
        pendingBiometricUser = nil
    }

    private func checkAuthState() {
        Auth.auth().addStateDidChangeListener { _, firebaseUser in
            guard let firebaseUser else {
                authState = .unauthenticated
                return
            }

            // Check email verified
            guard firebaseUser.isEmailVerified else {
                try? Auth.auth().signOut()
                KeychainService.clearAll()
                authState = .unauthenticated
                return
            }

            // Fetch or create user profile from API
            Task { @MainActor in
                do {
                    let token = try await firebaseUser.getIDToken()
                    KeychainService.store(token, for: .authToken)

                    guard let meURL = URL(string: "\(apiBaseURL)/api/auth/me") else {
                        authState = .unauthenticated
                        return
                    }

                    var request = URLRequest(url: meURL)
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (data, response) = try await URLSession.shared.data(for: request)
                    let http = response as! HTTPURLResponse

                    if http.statusCode == 200 {
                        let user = try JSONDecoder.apiDecoder.decode(APIResponse<AuthUser>.self, from: data).data
                        if BiometricService.pendingCredentials != nil
                            && BiometricService.availableBiometry != .none
                            && !BiometricService.isEnabled {
                            pendingBiometricUser = user
                        }
                        authState = .authenticated(user)
                    } else if http.statusCode == 404 {
                        guard let regURL = URL(string: "\(apiBaseURL)/api/auth/register") else {
                            authState = .unauthenticated
                            return
                        }
                        var regRequest = URLRequest(url: regURL)
                        regRequest.httpMethod = "POST"
                        regRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        regRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                        let body: [String: String] = [
                            "firebaseUid": firebaseUser.uid,
                            "email": firebaseUser.email ?? "",
                            "fullName": firebaseUser.displayName ?? "User"
                        ]
                        regRequest.httpBody = try JSONEncoder().encode(body)
                        let (regData, _) = try await URLSession.shared.data(for: regRequest)
                        let user = try JSONDecoder.apiDecoder.decode(APIResponse<AuthUser>.self, from: regData).data
                        if BiometricService.pendingCredentials != nil
                            && BiometricService.availableBiometry != .none
                            && !BiometricService.isEnabled {
                            pendingBiometricUser = user
                        }
                        authState = .authenticated(user)
                    } else {
                        authState = .unauthenticated
                    }
                } catch {
                    authState = .unauthenticated
                }
            }
        }
    }

    private var apiBaseURL: String {
        ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"
    }
}

#Preview {
    SplashRouterView()
}
