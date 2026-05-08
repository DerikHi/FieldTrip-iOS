import Foundation
import CoreLocation
import UIKit
import SwiftUI
import Network

@MainActor
final class InsightEntryViewModel: NSObject, ObservableObject {
    // MARK: - Published

    @Published var draft = InsightDraft()
    @Published var currentStep: Step = .location
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isSuccess = false

    // Location
    @Published var locationAuthStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var coordinatePasteInput = ""
    @Published var coordinatePasteError: String?
    @Published var isGettingLocation = false

    // Categories
    @Published var facilityTypes: [FacilityType] = []
    @Published var featureCategories: [FeatureCategory] = []

    // Network
    @Published var isOffline = false

    enum Step: Int, CaseIterable {
        case location = 0
        case facilityType = 1
        case ratings = 2
        case comment = 3
        case photos = 4
        case review = 5

        var title: String {
            switch self {
            case .location: return "Location"
            case .facilityType: return "Facility Type"
            case .ratings: return "Rate Features"
            case .comment: return "Comment"
            case .photos: return "Photos"
            case .review: return "Review & Submit"
            }
        }
    }

    private let locationManager = CLLocationManager()
    private let networkMonitor = NWPathMonitor()
    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://your-app.vercel.app"

    override init() {
        super.init()
        locationManager.delegate = self
        startNetworkMonitoring()
        Task { await loadCategories() }
    }

    // MARK: - Navigation

    var canAdvance: Bool {
        switch currentStep {
        case .location: return draft.hasValidCoordinates
        case .facilityType: return !draft.facilityTypeId.isEmpty
        case .ratings, .comment, .photos: return true
        case .review: return true
        }
    }

    func advance() {
        guard let nextIndex = Step.allCases.firstIndex(of: currentStep).map({ $0 + 1 }),
              nextIndex < Step.allCases.count else { return }
        currentStep = Step.allCases[nextIndex]
    }

    func goBack() {
        guard let prevIndex = Step.allCases.firstIndex(of: currentStep).map({ $0 - 1 }),
              prevIndex >= 0 else { return }
        currentStep = Step.allCases[prevIndex]
    }

    // MARK: - Location

    func requestLocation() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isGettingLocation = true
            locationManager.requestLocation()
        case .denied, .restricted:
            errorMessage = "Location access denied. Enable it in Settings or paste coordinates manually."
        @unknown default:
            break
        }
    }

    func parseCoordinatePaste() {
        coordinatePasteError = nil
        let trimmed = coordinatePasteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let coords = ValidationService.parseCoordinates(from: trimmed) {
            draft.latitude = coords.lat
            draft.longitude = coords.lng
            coordinatePasteError = nil
        } else {
            coordinatePasteError = "Could not parse coordinates. Try 'lat, lng' format or paste a Google/Apple Maps URL."
        }
    }

    // MARK: - Feature Ratings

    func initializeRatings() {
        draft.featureRatings = featureCategories.map { category in
            FeatureRatingInput(id: UUID().uuidString, category: category, rating: 3)
        }
    }

    // MARK: - Submit

    func submit() async {
        guard draft.hasValidCoordinates, !draft.facilityTypeId.isEmpty else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if isOffline {
            saveToOfflineQueue()
            isSuccess = true
            return
        }

        do {
            let token = KeychainService.retrieve(for: .authToken) ?? ""
            let insightId = try await submitInsight(token: token)
            await uploadPendingPhotos(insightId: insightId, token: token)
            isSuccess = true
        } catch {
            errorMessage = "Failed to submit: \(error.localizedDescription). Saving offline."
            saveToOfflineQueue()
        }
    }

    private func submitInsight(token: String) async throws -> String {
        guard let url = URL(string: "\(apiBaseURL)/api/insights") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "latitude": draft.latitude!,
            "longitude": draft.longitude!,
            "locationName": draft.locationName,
            "facilityTypeId": draft.facilityTypeId,
            "comment": draft.comment,
            "isPublic": draft.isPublic,
            "featureRatings": draft.featureRatings.map {
                ["featureCategoryId": $0.category.id, "rating": $0.rating]
            }
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder.apiDecoder.decode(APIResponse<Insight>.self, from: data)
        return response.data.id
    }

    private func uploadPendingPhotos(insightId: String, token: String) async {
        guard let url = URL(string: "\(apiBaseURL)/api/upload") else { return }

        for (i, wrapper) in draft.photos.enumerated() {
            guard !wrapper.uploaded, let jpeg = wrapper.image.jpegData(compressionQuality: 0.7) else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let boundary = UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"insightId\"\r\n\r\n\(insightId)\r\n".data(using: .utf8)!)
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"photo_\(i).jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(jpeg)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body

            _ = try? await URLSession.shared.data(for: request)
            draft.photos[i].uploaded = true
        }
    }

    // MARK: - Offline Queue

    private func saveToOfflineQueue() {
        guard let lat = draft.latitude, let lng = draft.longitude else { return }

        let pending = PendingInsight(
            id: UUID(),
            draft: .init(
                latitude: lat,
                longitude: lng,
                locationName: draft.locationName,
                facilityTypeId: draft.facilityTypeId,
                comment: draft.comment,
                isPublic: draft.isPublic,
                featureRatings: draft.featureRatings.map {
                    .init(featureCategoryId: $0.category.id, rating: $0.rating)
                }
            ),
            createdAt: Date()
        )

        var queue = loadOfflineQueue()
        queue.append(pending)
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: "offline_insight_queue")
        }
    }

    func loadOfflineQueue() -> [PendingInsight] {
        guard let data = UserDefaults.standard.data(forKey: "offline_insight_queue"),
              let queue = try? JSONDecoder().decode([PendingInsight].self, from: data) else { return [] }
        return queue
    }

    func syncOfflineQueue() async {
        guard !isOffline else { return }
        var queue = loadOfflineQueue()
        guard !queue.isEmpty else { return }

        let token = KeychainService.retrieve(for: .authToken) ?? ""
        var synced: Set<UUID> = []

        for item in queue {
            // Reconstruct and submit
            draft.latitude = item.draft.latitude
            draft.longitude = item.draft.longitude
            draft.locationName = item.draft.locationName
            draft.facilityTypeId = item.draft.facilityTypeId
            draft.comment = item.draft.comment
            draft.isPublic = item.draft.isPublic

            if let _ = try? await submitInsight(token: token) {
                synced.insert(item.id)
            }
        }

        queue.removeAll { synced.contains($0.id) }
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: "offline_insight_queue")
        }
    }

    // MARK: - Categories

    private func loadCategories() async {
        guard let url = URL(string: "\(apiBaseURL)/api/categories") else { return }
        let token = KeychainService.retrieve(for: .authToken) ?? ""
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder.apiDecoder.decode(APIResponse<CategoriesResponse>.self, from: data)
            facilityTypes = response.data.facilityTypes
            featureCategories = response.data.featureCategories
        } catch {
            // Use cached data if available
        }
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOffline = self?.isOffline ?? false
                self?.isOffline = path.status != .satisfied

                // Back online — sync queue
                if wasOffline && path.status == .satisfied {
                    Task { await self?.syncOfflineQueue() }
                }
            }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .background))
    }
}

// MARK: - CLLocationManagerDelegate

extension InsightEntryViewModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location.coordinate
            draft.latitude = location.coordinate.latitude
            draft.longitude = location.coordinate.longitude
            isGettingLocation = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            isGettingLocation = false
            errorMessage = "Could not get location: \(error.localizedDescription)"
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            locationAuthStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse {
                isGettingLocation = true
                manager.requestLocation()
            }
        }
    }
}
