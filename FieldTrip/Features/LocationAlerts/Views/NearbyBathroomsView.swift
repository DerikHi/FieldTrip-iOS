import SwiftUI
import CoreLocation

/// Lists nearby (≤5 mi) places of the allowed facility types whose
/// dominant Clean Bathroom rating is Good or Great. Replaces the old
/// alert-based flow — no push notifications are scheduled.
struct NearbyBathroomsView: View {
    @State private var locator = OneShotLocator()
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var alerts = LocationAlertService.shared
    @State private var results: [NearbyLocation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"

    /// Facility types eligible for the bathroom-quality list.
    private let allowedFacilityTypes: Set<String> = [
        "Restaurants",
        "Gas Stations",
        "Coffee Shops",
        "Convenience Stores",
        "Hotels",
        "Public Restrooms",
        "Truck Stops",
        "Welcome Centers/Visitor Centers",
    ]

    var body: some View {
        Group {
            if let error = errorMessage {
                ContentUnavailableView(
                    "Couldn't Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if isLoading {
                ProgressView("Finding nearby spots…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredResults.isEmpty {
                ContentUnavailableView(
                    "Nothing Within 5 Miles",
                    systemImage: "mappin.slash",
                    description: Text("No qualifying locations rated Good or Great were found near you.")
                )
            } else {
                List {
                    ForEach(groupedResults, id: \.facilityType) { group in
                        Section {
                            ForEach(group.locations, id: \.locationId) { loc in
                                HStack(spacing: 12) {
                                    Image(systemName: ratingIcon(loc.cleanBathroomRating))
                                        .foregroundStyle(ratingColor(loc.cleanBathroomRating))
                                        .font(.title3)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(loc.locationName ?? "Unnamed Location")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(String(format: "%.1f mi", loc.distanceMiles))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        Text((loc.cleanBathroomRating ?? "").capitalized)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(ratingColor(loc.cleanBathroomRating))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            Text(group.facilityType)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Nearby Bathrooms Rated Good or Great")
        .navigationBarTitleDisplayMode(.inline)
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { Task { await load() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { await load() }
    }

    private var filteredResults: [NearbyLocation] {
        results.filter { loc in
            allowedFacilityTypes.contains(loc.facilityTypeName)
                && (loc.cleanBathroomRating?.lowercased() == "good" || loc.cleanBathroomRating?.lowercased() == "great")
        }
    }

    /// Buckets the filtered results by facility type so the screen can
    /// render one section per category, in alphabetical order, with each
    /// section's locations sorted by distance.
    private var groupedResults: [FacilityGroup] {
        let buckets = Dictionary(grouping: filteredResults) { $0.facilityTypeName }
        return buckets.keys.sorted().map { type in
            FacilityGroup(
                facilityType: type,
                locations: (buckets[type] ?? []).sorted { $0.distanceMiles < $1.distanceMiles }
            )
        }
    }

    private func ratingIcon(_ rating: String?) -> String {
        switch rating?.lowercased() {
        case "great": return "star.fill"
        case "good": return "checkmark.seal.fill"
        default: return "mappin.circle.fill"
        }
    }

    private func ratingColor(_ rating: String?) -> Color {
        switch rating?.lowercased() {
        case "great": return .green
        case "good": return .mint
        default: return .secondary
        }
    }

    private func load() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        // Make sure location access has been requested. If denied, point the user at Settings.
        guard alerts.authorizationStatus == .authorizedWhenInUse
                || alerts.authorizationStatus == .authorizedAlways else {
            errorMessage = "Location access is off. Turn on Location Services in the Settings screen to see nearby spots."
            return
        }

        let location: CLLocation
        do {
            location = try await locator.fetch()
        } catch {
            errorMessage = "We couldn't determine your location. Try again in a moment."
            return
        }

        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(apiBaseURL)/api/locations/nearby?lat=\(location.coordinate.latitude)&lng=\(location.coordinate.longitude)&radius=5") else {
            errorMessage = "An error has occurred, please log in again."
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(NearbyResponse.self, from: data)
            results = decoded.data.results
        } catch {
            errorMessage = "An error has occurred, please log in again."
        }
    }
}

private struct FacilityGroup {
    let facilityType: String
    let locations: [NearbyLocation]
}

/// One-shot CLLocationManager that resolves a single fresh fix. Lets the
/// NearbyBathroomsView ask for the user's current location without bringing
/// up a long-running monitoring session.
@MainActor
final class OneShotLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func fetch() async throws -> CLLocation {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        return try await withCheckedThrowingContinuation { cont in
            continuation = cont
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            continuation?.resume(returning: loc)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
