import Foundation

struct PlateTally: Decodable {
    let state: String
    let count: Int
}

struct PlateSightingResponse: Decodable {
    let state: String
    let count: Int
}

final class PlateService {
    static let shared = PlateService()
    private init() {}

    private var baseURL: String {
        ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"
    }

    func fetchTallies() async throws -> [PlateTally] {
        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(baseURL)/api/plate-sightings") else {
            throw AuthError.serverError("Unable to connect")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse

        guard http.statusCode == 200 else {
            throw AuthError.serverError("Server error \(http.statusCode)")
        }

        return try JSONDecoder.apiDecoder.decode(APIResponse<[PlateTally]>.self, from: data).data
    }

    func recordSighting(state: String) async throws -> PlateSightingResponse {
        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(baseURL)/api/plate-sightings") else {
            throw AuthError.serverError("Unable to connect")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["state": state])

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse

        guard http.statusCode == 201 else {
            throw AuthError.serverError("Server error \(http.statusCode)")
        }

        return try JSONDecoder.apiDecoder.decode(APIResponse<PlateSightingResponse>.self, from: data).data
    }
}
