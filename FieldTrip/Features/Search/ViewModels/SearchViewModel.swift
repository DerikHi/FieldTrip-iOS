import Foundation
import CoreLocation
import MapKit

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var selectedFacilityTypeId: String?
    @Published var radiusMiles: Double = 25
    @Published var coordinatePaste = ""
    @Published var minRating: Double = 1

    @Published var results: [SearchResult] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 47.0, longitude: -120.0),
        span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2)
    )

    @Published var facilityTypes: [FacilityType] = []
    @Published var selectedResult: SearchResult?

    // For "near me" quick search
    @Published var nearMeResults: [SearchResult] = []
    @Published var isLoadingNearMe = false

    private let locationManager = CLLocationManager()
    private var searchDebounceTask: Task<Void, Never>?
    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://your-app.vercel.app"

    struct SearchResult: Identifiable, Decodable {
        let locationId: String
        let locationName: String?
        let address: String?
        let latitude: Double
        let longitude: Double
        let distanceMiles: Double?
        let facilityTypeName: String
        let facilityTypeCategory: String
        let insightCount: Int
        let avgRating: Double?
        let lastInsightAt: Date?

        var id: String { locationId }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        var displayName: String {
            locationName ?? facilityTypeName
        }

        var distanceText: String? {
            guard let dist = distanceMiles else { return nil }
            return String(format: "%.1f mi away", dist)
        }

        var ratingText: String? {
            guard let rating = avgRating else { return nil }
            return String(format: "%.1f ★", rating)
        }
    }

    init() {
        Task { await loadFacilityTypes() }
    }

    // MARK: - Search

    func triggerSearch() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await performSearch()
        }
    }

    func performSearch() async {
        guard !searchText.isEmpty || selectedFacilityTypeId != nil || !coordinatePaste.isEmpty else {
            results = []
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        var components = URLComponents(string: "\(apiBaseURL)/api/search")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "radiusMiles", value: String(radiusMiles)),
            URLQueryItem(name: "limit", value: "50"),
        ]

        if !searchText.isEmpty {
            queryItems.append(URLQueryItem(name: "locationName", value: searchText))
        }

        if let facilityTypeId = selectedFacilityTypeId {
            queryItems.append(URLQueryItem(name: "facilityTypeId", value: facilityTypeId))
        }

        if minRating > 1 {
            queryItems.append(URLQueryItem(name: "minRating", value: String(Int(minRating))))
        }

        // Parse pasted coordinates
        if !coordinatePaste.isEmpty, let coords = ValidationService.parseCoordinates(from: coordinatePaste) {
            queryItems.append(contentsOf: [
                URLQueryItem(name: "lat", value: String(coords.lat)),
                URLQueryItem(name: "lng", value: String(coords.lng)),
            ])
        }

        // If searching by city name, geocode first
        else if !searchText.isEmpty && searchText.count > 2 {
            if let coords = await geocodeCity(searchText) {
                queryItems.append(contentsOf: [
                    URLQueryItem(name: "lat", value: String(coords.latitude)),
                    URLQueryItem(name: "lng", value: String(coords.longitude)),
                ])
                mapRegion = MKCoordinateRegion(
                    center: coords,
                    span: MKCoordinateSpan(latitudeDelta: radiusMiles / 35.0, longitudeDelta: radiusMiles / 35.0)
                )
            }
        }

        components.queryItems = queryItems
        guard let url = components.url else { return }

        let token = KeychainService.retrieve(for: .authToken) ?? ""
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder.apiDecoder.decode(SearchResponse.self, from: data)
            results = response.data.results
            updateMapRegion()
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }

    func nearMe() async {
        locationManager.requestWhenInUseAuthorization()
        isLoadingNearMe = true
        defer { isLoadingNearMe = false }

        guard let location = locationManager.location else {
            errorMessage = "Location not available. Please enable location access."
            return
        }

        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude

        guard let url = URL(string: "\(apiBaseURL)/api/search?lat=\(lat)&lng=\(lng)&radiusMiles=25&limit=20") else { return }

        let token = KeychainService.retrieve(for: .authToken) ?? ""
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder.apiDecoder.decode(SearchResponse.self, from: data)
            nearMeResults = response.data.results
            mapRegion = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        } catch {
            errorMessage = "Near-me search failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func geocodeCity(_ name: String) async -> CLLocationCoordinate2D? {
        let geocoder = CLGeocoder()
        let placemarks = try? await geocoder.geocodeAddressString(name)
        return placemarks?.first?.location?.coordinate
    }

    private func updateMapRegion() {
        guard !results.isEmpty else { return }
        let latitudes = results.map(\.latitude)
        let longitudes = results.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (latitudes.min()! + latitudes.max()!) / 2,
            longitude: (longitudes.min()! + longitudes.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.1, (latitudes.max()! - latitudes.min()!) * 1.3),
            longitudeDelta: max(0.1, (longitudes.max()! - longitudes.min()!) * 1.3)
        )
        mapRegion = MKCoordinateRegion(center: center, span: span)
    }

    private func loadFacilityTypes() async {
        guard let url = URL(string: "\(apiBaseURL)/api/categories") else { return }
        let token = KeychainService.retrieve(for: .authToken) ?? ""
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder.apiDecoder.decode(APIResponse<CategoriesResponse>.self, from: data)
            facilityTypes = response.data.facilityTypes
        } catch {}
    }
}

private struct SearchResponse: Decodable {
    struct Payload: Decodable {
        let results: [SearchViewModel.SearchResult]
    }
    let data: Payload
}
