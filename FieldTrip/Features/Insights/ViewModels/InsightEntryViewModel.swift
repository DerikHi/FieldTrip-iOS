import Foundation
import CoreLocation
import UIKit
import SwiftUI
import Network
import Combine

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

    // Reverse geocoding
    @Published var nearestTown: String?

    // Network
    @Published var isOffline = false

    enum Step: Int, CaseIterable {
        case location = 0
        case ratings = 1
        case comment = 2
        case photos = 3
        case review = 4

        var title: String {
            switch self {
            case .location: return "Location"
            case .ratings: return "Rate Features"
            case .comment: return "Comment"
            case .photos: return "Photos"
            case .review: return "Review & Submit"
            }
        }
    }

    private let locationManager = CLLocationManager()
    private let networkMonitor = NWPathMonitor()
    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"
    private var userRequestedLocation = false

    override init() {
        super.init()
        locationManager.delegate = self
        startNetworkMonitoring()
        Task { await loadCategories() }
    }

    // MARK: - Navigation

    var selectedFacilityTypeName: String {
        facilityTypes.first(where: { $0.id == draft.facilityTypeId })?.name ?? "—"
    }

    var canAdvance: Bool {
        switch currentStep {
        case .location: return draft.hasValidCoordinates
        case .ratings, .comment, .photos: return true
        case .review: return true
        }
    }

    func advance() {
        guard let nextIndex = Step.allCases.firstIndex(of: currentStep).map({ $0 + 1 }),
              nextIndex < Step.allCases.count else { return }

        errorMessage = nil

        if currentStep == .location && !draft.locationName.isEmpty {
            let result = ContentModerationService.checkText(draft.locationName)
            if !result.isClean {
                errorMessage = result.message
                return
            }
        }

        if currentStep == .comment && !draft.comment.isEmpty {
            let result = ContentModerationService.checkText(draft.comment)
            if !result.isClean {
                errorMessage = result.message
                return
            }
        }

        let nextStep = Step.allCases[nextIndex]
        if nextStep == .ratings && draft.attributeEntries.isEmpty {
            let attrs = attributesForSelectedFacilityType()
            draft.attributeEntries = attrs.map { AttributeEntry(name: $0) }
        }
        currentStep = nextStep
    }

    private func attributesForSelectedFacilityType() -> [String] {
        let name = facilityTypes.first(where: { $0.id == draft.facilityTypeId })?.name ?? ""
        if name.localizedCaseInsensitiveContains("hotel") {
            return Self.hotelAttributes
        }
        return Self.defaultAttributes
    }

    private static let hotelAttributes = [
        "Clean Room", "Clean Bathroom", "Feels Safe", "Friendly Staff",
        "Price", "Breakfast", "Gov Rate Available",
        "Pet Friendly", "LGBTQ+ Friendly"
    ]

    private static let defaultAttributes = [
        "Clean", "Clean Bathroom", "Feels Safe", "Friendly Staff",
        "Price", "Food Options", "Pet Friendly", "LGBTQ+ Friendly"
    ]

    private func placeTypeForFacility(_ name: String) -> String {
        switch name {
        case "Hotels":
            return "Hotel"
        case "Restaurants", "Coffee Shops", "Breweries/Wineries", "Bakeries":
            return "Restaurant"
        case "Gas Stations", "Truck Stops", "EV Charging Stations",
             "Grocery Stores", "Convenience Stores", "Pharmacies",
             "Outdoor/Camping Supply Stores", "Laundromats",
             "Hospitals/Urgent Care", "Pet Boarding/Vet Clinics", "Post Offices":
            return "Convenience Store"
        default:
            return "Rest Area"
        }
    }

    func goBack() {
        guard let prevIndex = Step.allCases.firstIndex(of: currentStep).map({ $0 - 1 }),
              prevIndex >= 0 else { return }
        currentStep = Step.allCases[prevIndex]
    }

    // MARK: - Location

    func requestLocation() {
        userRequestedLocation = true
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
            reverseGeocode(latitude: coords.lat, longitude: coords.lng)
            return
        }

        Task {
            // Try Plus Code first (e.g. "849VCWC8+R9" or "CWC8+R9 Springfield, IL")
            if PlusCodeService.looksLikePlusCode(trimmed),
               let coords = await PlusCodeService.decode(trimmed) {
                draft.latitude = coords.latitude
                draft.longitude = coords.longitude
                coordinatePasteError = nil
                reverseGeocode(latitude: coords.latitude, longitude: coords.longitude)
                return
            }

            // Fall back to forward-geocoding a place/town name
            let geocoder = CLGeocoder()
            do {
                guard let placemark = try await geocoder.geocodeAddressString(trimmed).first,
                      let location = placemark.location else {
                    coordinatePasteError = "Could not find that location. Try 'lat, lng', a map link, a Plus Code, or a town name like 'Springfield, IL'."
                    return
                }
                draft.latitude = location.coordinate.latitude
                draft.longitude = location.coordinate.longitude
                coordinatePasteError = nil
                reverseGeocode(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            } catch {
                coordinatePasteError = "Could not find that location. Try 'lat, lng', a map link, a Plus Code, or a town name like 'Springfield, IL'."
            }
        }
    }

    func reverseGeocode(latitude: Double, longitude: Double) {
        nearestTown = nil
        let location = CLLocation(latitude: latitude, longitude: longitude)
        Task {
            let geocoder = CLGeocoder()
            guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return }
            let town = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
            if let town, let state = placemark.administrativeArea, state != town {
                nearestTown = "\(town), \(state)"
            } else if let town {
                nearestTown = town
            }
        }
    }

    // MARK: - Photo Moderation

    func addPhotoIfAppropriate(_ image: UIImage) async -> String? {
        let result = await ContentModerationService.checkImage(image)
        if result.isClean {
            guard draft.photos.count < 2 else { return nil }
            draft.photos.append(UIImageWrapper(image: image))
            return nil
        }
        return result.message
    }

    // MARK: - Feature Ratings

    func initializeRatings() {
        draft.featureRatings = featureCategories.map { category in
            FeatureRatingInput(id: UUID().uuidString, category: category, rating: 3)
        }
    }

    // MARK: - Submit

    func submit() async {
        guard draft.hasValidCoordinates else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        for text in [draft.locationName, draft.comment] where !text.isEmpty {
            let result = ContentModerationService.checkText(text)
            if !result.isClean {
                errorMessage = result.message
                return
            }
        }

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

        var body: [String: Any] = [
            "latitude": draft.latitude!,
            "longitude": draft.longitude!,
            "locationName": draft.locationName,
            "comment": draft.comment,
            "isPublic": draft.isPublic,
            "starRating": draft.starRating,
            "attributeRatings": draft.attributeEntries
                .filter { $0.rating != .na }
                .map {
                    ["attributeName": $0.name, "rating": $0.rating == .good ? "good" : "bad"]
                }
        ]

        if let town = nearestTown, !town.isEmpty {
            body["town"] = town
        }

        if !draft.facilityTypeId.isEmpty {
            if draft.facilityTypeId.hasPrefix("fb-") {
                body["placeType"] = placeTypeForFacility(selectedFacilityTypeName)
                body["facilityTypeName"] = selectedFacilityTypeName
            } else {
                body["facilityTypeId"] = draft.facilityTypeId
            }
        } else if let placeType = draft.placeType?.rawValue {
            body["placeType"] = placeType
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "InsightAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errorBody])
        }

        let decoded = try JSONDecoder.apiDecoder.decode(APIResponse<InsightIDResponse>.self, from: data)
        return decoded.data.id
    }

    private struct InsightIDResponse: Decodable {
        let id: String
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
                placeType: draft.placeType?.rawValue ?? "",
                starRating: draft.starRating,
                comment: draft.comment,
                isPublic: draft.isPublic,
                featureRatings: draft.featureRatings.map {
                    .init(featureCategoryId: $0.category.id, rating: $0.rating)
                },
                attributeRatings: draft.attributeEntries
                    .filter { $0.rating != .na }
                    .map {
                        .init(attributeName: $0.name, rating: $0.rating == .good ? "good" : "bad")
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
            draft.latitude = item.draft.latitude
            draft.longitude = item.draft.longitude
            draft.locationName = item.draft.locationName
            draft.facilityTypeId = item.draft.facilityTypeId
            draft.placeType = PlaceType(rawValue: item.draft.placeType)
            draft.starRating = item.draft.starRating
            draft.comment = item.draft.comment
            draft.isPublic = item.draft.isPublic
            draft.attributeEntries = item.draft.attributeRatings.map {
                var entry = AttributeEntry(name: $0.attributeName)
                entry.rating = AttributeRating(rawValue: $0.rating.capitalized) ?? .na
                return entry
            }

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

    func loadCategoriesIfNeeded() async {
        guard facilityTypes.isEmpty else { return }
        await loadCategories()
    }

    private func loadCategories() async {
        facilityTypes = Self.fallbackFacilityTypes

        guard let url = URL(string: "\(apiBaseURL)/api/categories") else { return }
        let token = KeychainService.retrieve(for: .authToken) ?? ""
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder.apiDecoder.decode(APIResponse<CategoriesResponse>.self, from: data)
            featureCategories = response.data.featureCategories
        } catch {
            // API unavailable or returned unexpected format
        }
    }

    static let fallbackFacilityTypes: [FacilityType] = [
        FacilityType(id: "fb-1", name: "Bakeries", category: "facility", icon: "birthday.cake", description: nil),
        FacilityType(id: "fb-2", name: "Beaches", category: "natural_space", icon: "beach.umbrella", description: nil),
        FacilityType(id: "fb-3", name: "Boat Launches", category: "natural_space", icon: "water.waves", description: nil),
        FacilityType(id: "fb-4", name: "Breweries/Wineries", category: "facility", icon: "wineglass", description: nil),
        FacilityType(id: "fb-5", name: "Campgrounds", category: "natural_space", icon: "tent.fill", description: nil),
        FacilityType(id: "fb-6", name: "Coffee Shops", category: "facility", icon: "cup.and.saucer.fill", description: nil),
        FacilityType(id: "fb-7", name: "Convenience Stores", category: "facility", icon: "basket.fill", description: nil),
        FacilityType(id: "fb-8", name: "EV Charging Stations", category: "facility", icon: "bolt.car.fill", description: nil),
        FacilityType(id: "fb-9", name: "Gas Stations", category: "facility", icon: "fuelpump.fill", description: nil),
        FacilityType(id: "fb-10", name: "Grocery Stores", category: "facility", icon: "cart.fill", description: nil),
        FacilityType(id: "fb-11", name: "Highway Rest Areas", category: "facility", icon: "car.fill", description: nil),
        FacilityType(id: "fb-12", name: "Historic Sites", category: "facility", icon: "building.columns", description: nil),
        FacilityType(id: "fb-13", name: "Hospitals/Urgent Care", category: "facility", icon: "cross.case.fill", description: nil),
        FacilityType(id: "fb-14", name: "Hotels", category: "facility", icon: "building.2", description: nil),
        FacilityType(id: "fb-15", name: "Laundromats", category: "facility", icon: "washer.fill", description: nil),
        FacilityType(id: "fb-16", name: "Museums", category: "facility", icon: "building.columns.fill", description: nil),
        FacilityType(id: "fb-17", name: "Outdoor/Camping Supply Stores", category: "facility", icon: "backpack.fill", description: nil),
        FacilityType(id: "fb-18", name: "Pet Boarding/Vet Clinics", category: "facility", icon: "pawprint.fill", description: nil),
        FacilityType(id: "fb-19", name: "Pharmacies", category: "facility", icon: "pills.fill", description: nil),
        FacilityType(id: "fb-20", name: "Post Offices", category: "facility", icon: "envelope.fill", description: nil),
        FacilityType(id: "fb-21", name: "Public Restrooms", category: "facility", icon: "toilet", description: nil),
        FacilityType(id: "fb-22", name: "Restaurants", category: "facility", icon: "fork.knife", description: nil),
        FacilityType(id: "fb-23", name: "Roadside Attractions", category: "facility", icon: "star.fill", description: nil),
        FacilityType(id: "fb-24", name: "RV Parks", category: "natural_space", icon: "bus.fill", description: nil),
        FacilityType(id: "fb-25", name: "Scenic Overlooks", category: "natural_space", icon: "binoculars.fill", description: nil),
        FacilityType(id: "fb-26", name: "State/National Parks", category: "natural_space", icon: "leaf.fill", description: nil),
        FacilityType(id: "fb-27", name: "Trailheads", category: "natural_space", icon: "figure.hiking", description: nil),
        FacilityType(id: "fb-28", name: "Truck Stops", category: "facility", icon: "truck.box.fill", description: nil),
        FacilityType(id: "fb-29", name: "Welcome Centers/Visitor Centers", category: "facility", icon: "info.circle.fill", description: nil),
    ]

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
            reverseGeocode(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
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
            if manager.authorizationStatus == .authorizedWhenInUse && userRequestedLocation {
                isGettingLocation = true
                manager.requestLocation()
            }
        }
    }
}
