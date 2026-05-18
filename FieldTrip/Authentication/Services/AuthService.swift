import Foundation
import FirebaseAuth

// MARK: - Protocol (enables mocking in tests)

protocol AuthServiceProtocol {
    func signIn(email: String, password: String) async throws -> AuthUser
    func register(email: String, password: String, fullName: String) async throws -> AuthUser
    func signOut() throws
    func sendPasswordReset(email: String) async throws
    func sendEmailVerification() async throws
    func reloadUser() async throws -> Bool // returns isEmailVerified
    var currentFirebaseUser: User? { get }
}

// MARK: - AuthError

enum AuthError: LocalizedError {
    case invalidCredentials
    case emailAlreadyInUse
    case weakPassword
    case userNotFound
    case tooManyRequests
    case networkError
    case emailNotVerified
    case serverError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Incorrect email or password."
        case .emailAlreadyInUse: return "An account with this email already exists."
        case .weakPassword: return "Password is too weak. Please use a stronger password."
        case .userNotFound: return "No account found with this email address."
        case .tooManyRequests: return "Too many attempts. Please wait a few minutes and try again."
        case .networkError: return "Network error. Please check your connection."
        case .emailNotVerified: return "Please verify your email address before signing in."
        case .serverError(let msg): return msg
        case .unknown(let msg): return msg
        }
    }
}

// MARK: - Implementation

final class AuthService: AuthServiceProtocol {
    static let shared = AuthService()
    private init() {}

    // TODO: Replace baseURL with your deployed Vercel URL
    private let baseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"

    var currentFirebaseUser: User? { Auth.auth().currentUser }

    // MARK: - Sign In

    func signIn(email: String, password: String) async throws -> AuthUser {
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)

            guard result.user.isEmailVerified else {
                try? Auth.auth().signOut()
                throw AuthError.emailNotVerified
            }

            let token = try await result.user.getIDToken()
            KeychainService.store(token, for: .authToken)
            KeychainService.store(result.user.uid, for: .userId)

            return try await fetchOrCreateUser(firebaseUser: result.user, token: token)
        } catch let error as AuthError {
            throw error
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    // MARK: - Register

    func register(email: String, password: String, fullName: String) async throws -> AuthUser {
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)

            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = fullName
            try await changeRequest.commitChanges()

            try await result.user.sendEmailVerification()

            let token = try await result.user.getIDToken()

            // Register in our backend
            let user = try await registerInBackend(
                firebaseUid: result.user.uid,
                email: email,
                fullName: fullName,
                token: token
            )

            KeychainService.store(token, for: .authToken)
            KeychainService.store(result.user.uid, for: .userId)

            return user
        } catch let error as AuthError {
            throw error
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    // MARK: - Sign Out

    func signOut() throws {
        try Auth.auth().signOut()
        KeychainService.clearAll()
    }

    // MARK: - Password Reset

    func sendPasswordReset(email: String) async throws {
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch let error as NSError {
            throw mapFirebaseError(error)
        }
    }

    // MARK: - Email Verification

    func sendEmailVerification() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await user.sendEmailVerification()
    }

    func reloadUser() async throws -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        try await user.reload()
        return user.isEmailVerified
    }

    // MARK: - Backend calls

    private func fetchOrCreateUser(firebaseUser: User, token: String) async throws -> AuthUser {
        guard let url = URL(string: "\(baseURL)/api/auth/me") else {
            throw AuthError.serverError("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse

        if http.statusCode == 200 {
            return try JSONDecoder.apiDecoder.decode(APIResponse<AuthUser>.self, from: data).data
        }

        if http.statusCode == 404 {
            do {
                return try await registerInBackend(
                    firebaseUid: firebaseUser.uid,
                    email: firebaseUser.email ?? "",
                    fullName: firebaseUser.displayName ?? "User",
                    token: token
                )
            } catch AuthError.emailAlreadyInUse {
                // User exists but with a different firebaseUid — retry fetch
                let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
                let retryHttp = retryResponse as! HTTPURLResponse
                guard retryHttp.statusCode == 200 else {
                    throw AuthError.serverError("Server error \(retryHttp.statusCode)")
                }
                return try JSONDecoder.apiDecoder.decode(APIResponse<AuthUser>.self, from: retryData).data
            }
        }

        throw AuthError.serverError("Server error \(http.statusCode)")
    }

    private func registerInBackend(
        firebaseUid: String,
        email: String,
        fullName: String,
        token: String
    ) async throws -> AuthUser {
        guard let url = URL(string: "\(baseURL)/api/auth/register") else {
            throw AuthError.serverError("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = ["firebaseUid": firebaseUid, "email": email, "fullName": fullName]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse

        guard http.statusCode == 201 else {
            if http.statusCode == 409 {
                throw AuthError.emailAlreadyInUse
            }
            throw AuthError.serverError("Registration failed: \(http.statusCode)")
        }

        return try JSONDecoder.apiDecoder.decode(APIResponse<AuthUser>.self, from: data).data
    }

    // MARK: - Error Mapping

    private func mapFirebaseError(_ error: NSError) -> AuthError {
        switch AuthErrorCode(rawValue: error.code) {
        case .wrongPassword, .invalidEmail, .invalidCredential:
            return .invalidCredentials
        case .emailAlreadyInUse:
            return .emailAlreadyInUse
        case .weakPassword:
            return .weakPassword
        case .userNotFound:
            return .userNotFound
        case .tooManyRequests:
            return .tooManyRequests
        case .networkError:
            return .networkError
        default:
            return .unknown(error.localizedDescription)
        }
    }
}

// MARK: - Helpers

struct APIResponse<T: Decodable>: Decodable {
    let data: T
    let error: String?
}

extension JSONDecoder {
    static let apiDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
