import Foundation
import FirebaseAuth

/// Errors surfaced by `APIClient`. `errorDescription` is user-presentable.
enum APIError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case http(status: Int, body: String?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You're signed out. Please sign in again."
        case .invalidURL:
            return "Something went wrong preparing the request."
        case .http(let status, let body):
            return body?.isEmpty == false ? body : "Server error (\(status))."
        case .decoding:
            return "We couldn't read the server's response."
        }
    }
}

/// Single entry point for backend calls. Injects a **freshly-minted** Firebase
/// ID token on every request (Firebase auto-refreshes it when near expiry), so
/// callers never depend on a possibly-stale token cached in the Keychain.
/// Centralizes the base URL, headers, and the standard `APIResponse` decoding.
struct APIClient {
    static let shared = APIClient()

    private let baseURL = ProcessInfo.processInfo.environment["API_URL"]
        ?? "https://backend-nine-kappa-58.vercel.app"
    private let session: URLSession = .shared

    private init() {}

    // MARK: - Auth

    /// A current `Bearer` header, refreshing the ID token if it's near expiry.
    private func authorizationHeader() async throws -> String {
        guard let user = Auth.auth().currentUser else { throw APIError.notAuthenticated }
        let token = try await user.getIDToken()
        return "Bearer \(token)"
    }

    // MARK: - Low-level

    /// Performs a request and returns the raw body. Throws `APIError.http` for
    /// any status >= 400 (with the response body attached for messaging).
    @discardableResult
    func data(
        _ method: String = "GET",
        _ path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        contentType: String? = nil,
        requiresAuth: Bool = true
    ) async throws -> Data {
        guard var components = URLComponents(string: baseURL + path) else { throw APIError.invalidURL }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        if requiresAuth {
            request.setValue(try await authorizationHeader(), forHTTPHeaderField: "Authorization")
        }
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(status: -1, body: nil)
        }
        guard (200..<400).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return data
    }

    // MARK: - JSON convenience

    /// GET a path and decode the response as `T` (pass `APIResponse<Foo>.self`
    /// or a custom envelope type).
    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], decode type: T.Type) async throws -> T {
        try decode(type, from: try await data("GET", path, query: query))
    }

    /// Send a JSON dictionary body and decode the response as `T`.
    @discardableResult
    func send<T: Decodable>(
        _ method: String,
        _ path: String,
        json: [String: Any],
        decode type: T.Type
    ) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: json)
        return try decode(type, from: try await data(method, path, body: body, contentType: "application/json"))
    }

    /// Send a JSON dictionary body where only success/failure matters.
    func send(_ method: String, _ path: String, json: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: json)
        _ = try await data(method, path, body: body, contentType: "application/json")
    }

    /// A request (e.g. DELETE) whose only success signal is the HTTP status.
    func send(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws {
        _ = try await data(method, path, query: query)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder.apiDecoder.decode(type, from: data) }
        catch { throw APIError.decoding(error) }
    }
}
