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

    func fetchTallies() async throws -> [PlateTally] {
        try await APIClient.shared.get("/api/plate-sightings", decode: APIResponse<[PlateTally]>.self).data
    }

    func recordSighting(state: String) async throws -> PlateSightingResponse {
        try await APIClient.shared.send(
            "POST", "/api/plate-sightings",
            json: ["state": state],
            decode: APIResponse<PlateSightingResponse>.self
        ).data
    }

    /// Removes one sighting for the given state. Returns the new count for that state.
    func decrementSighting(state: String) async throws -> PlateSightingResponse {
        let data = try await APIClient.shared.data(
            "DELETE", "/api/plate-sightings",
            query: [URLQueryItem(name: "state", value: state)]
        )
        return try JSONDecoder.apiDecoder.decode(APIResponse<PlateSightingResponse>.self, from: data).data
    }

    /// Clears all of the user's plate sightings.
    func clearAllSightings() async throws {
        try await APIClient.shared.send("DELETE", "/api/plate-sightings")
    }
}
