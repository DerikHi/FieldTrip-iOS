import SwiftUI
import FirebaseAuth

struct SplashRouterView: View {
    @State private var authState: AuthState = .loading
    @State private var currentUser: AuthUser?

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
                // TODO: Replace with MainTabView(user: user)
                Text("Welcome, \(user.fullName)")
                    .font(.largeTitle)
            }
        }
        .onAppear { checkAuthState() }
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

            // Fetch user profile from API
            Task { @MainActor in
                do {
                    let token = try await firebaseUser.getIDToken()
                    KeychainService.store(token, for: .authToken)

                    guard let url = URL(string: "\(apiBaseURL)/api/auth/me") else {
                        authState = .unauthenticated
                        return
                    }

                    var request = URLRequest(url: url)
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (data, _) = try await URLSession.shared.data(for: request)
                    let user = try JSONDecoder.apiDecoder.decode(APIResponse<AuthUser>.self, from: data).data
                    authState = .authenticated(user)
                } catch {
                    authState = .unauthenticated
                }
            }
        }
    }

    private var apiBaseURL: String {
        ProcessInfo.processInfo.environment["API_URL"] ?? "https://your-app.vercel.app"
    }
}

#Preview {
    SplashRouterView()
}
