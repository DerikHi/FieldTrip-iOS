import Foundation
import CoreLocation
import UserNotifications
import UIKit
import Combine

@MainActor
final class LocationAlertService: NSObject, ObservableObject {
    static let shared = LocationAlertService()

    enum PrimingChoice: String {
        case yes
        case maybeLater
        case no
    }

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var notificationsAuthorized: Bool = false
    @Published private(set) var isMonitoring: Bool = false

    private let manager = CLLocationManager()
    private var nearbyLocations: [NearbyLocation] = []
    private var lastFetchedFrom: CLLocation?
    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"
    private let alertRadiusMiles: Double = 5.0
    private let cooldownInterval: TimeInterval = 24 * 60 * 60
    private let refreshDistanceMeters: CLLocationDistance = 1609 // ~1 mile

    // Keys
    private let primingChoiceKey = "locationPrimingChoice"
    private let primingUserIdKey = "locationPrimingUserId"
    private let launchCountKey = "locationLaunchCount"
    private let cooldownsKey = "locationAlertCooldowns"

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 500
    }

    // MARK: - Priming

    var primingChoice: PrimingChoice? {
        guard let raw = UserDefaults.standard.string(forKey: primingChoiceKey) else { return nil }
        return PrimingChoice(rawValue: raw)
    }

    var primingUserId: String? {
        UserDefaults.standard.string(forKey: primingUserIdKey)
    }

    func recordPrimingChoice(_ choice: PrimingChoice, for userId: String) {
        UserDefaults.standard.set(choice.rawValue, forKey: primingChoiceKey)
        UserDefaults.standard.set(userId, forKey: primingUserIdKey)
    }

    var launchCount: Int {
        UserDefaults.standard.integer(forKey: launchCountKey)
    }

    func incrementLaunchCount() {
        UserDefaults.standard.set(launchCount + 1, forKey: launchCountKey)
    }

    /// Should the priming screen show right now?
    /// - shows if user has never made a choice
    /// - shows on every 5th launch if previous choice was .maybeLater
    func shouldShowPriming(for userId: String) -> Bool {
        if primingChoice == nil { return true }
        if primingUserId != userId { return true }
        if primingChoice == .maybeLater && launchCount > 0 && launchCount % 5 == 0 {
            return true
        }
        return false
    }

    // MARK: - Permissions

    func requestLocationPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            notificationsAuthorized = granted
            return granted
        } catch {
            return false
        }
    }

    func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    var locationPermissionGranted: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var systemLocationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }

    // MARK: - Monitoring

    func startIfPossible() {
        guard locationPermissionGranted, primingChoice == .yes else { return }
        manager.startUpdatingLocation()
        isMonitoring = true
    }

    func stop() {
        manager.stopUpdatingLocation()
        isMonitoring = false
    }

    /// User explicitly opted out of nearby alerts.
    /// Stops location monitoring and records the choice so we don't re-prompt.
    func disableNearbyAlerts() {
        stop()
        let userId = primingUserId ?? ""
        UserDefaults.standard.set(PrimingChoice.no.rawValue, forKey: primingChoiceKey)
        UserDefaults.standard.set(userId, forKey: primingUserIdKey)
    }

    // MARK: - Nearby fetch

    private func refreshNearby(at location: CLLocation) async {
        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(apiBaseURL)/api/locations/nearby?lat=\(location.coordinate.latitude)&lng=\(location.coordinate.longitude)&radius=\(alertRadiusMiles)") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoded = try JSONDecoder().decode(NearbyResponse.self, from: data)
            nearbyLocations = decoded.data.results
            lastFetchedFrom = location
        } catch {
            // Silently fail — will retry on next significant move
        }
    }

    // MARK: - Notifications

    private func cooldowns() -> [String: TimeInterval] {
        UserDefaults.standard.dictionary(forKey: cooldownsKey) as? [String: TimeInterval] ?? [:]
    }

    private func setCooldown(for locationId: String, at time: TimeInterval) {
        var existing = cooldowns()
        existing[locationId] = time
        UserDefaults.standard.set(existing, forKey: cooldownsKey)
    }

    private func isCoolingDown(_ locationId: String) -> Bool {
        guard let last = cooldowns()[locationId] else { return false }
        return Date().timeIntervalSince1970 - last < cooldownInterval
    }

    private func fireAlert(for location: NearbyLocation) {
        guard !isCoolingDown(location.locationId) else { return }
        setCooldown(for: location.locationId, at: Date().timeIntervalSince1970)

        let content = UNMutableNotificationContent()
        content.title = "FieldTrip Pro location alert"
        content.body = "You are approaching a location that you or other users have rated in FTP"
        content.sound = .default
        content.userInfo = [
            "locationId": location.locationId,
            "locationName": location.locationName ?? "",
            "latitude": location.latitude,
            "longitude": location.longitude,
            "facilityTypeName": location.facilityTypeName,
        ]
        content.categoryIdentifier = "LOCATION_ALERT"

        let request = UNNotificationRequest(
            identifier: "location-\(location.locationId)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Register the notification category once at app launch
    func registerNotificationCategory() {
        let open = UNNotificationAction(
            identifier: "OPEN_MAP",
            title: "Open Map",
            options: [.foreground]
        )
        let dismiss = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: "LOCATION_ALERT",
            actions: [open, dismiss],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationAlertService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if locationPermissionGranted && primingChoice == .yes {
                startIfPossible()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await handleLocationUpdate(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    @MainActor
    private func handleLocationUpdate(_ location: CLLocation) async {
        if lastFetchedFrom == nil || (lastFetchedFrom?.distance(from: location) ?? .infinity) > refreshDistanceMeters {
            await refreshNearby(at: location)
        }

        for nearby in nearbyLocations where nearby.distanceMiles <= alertRadiusMiles {
            let target = CLLocation(latitude: nearby.latitude, longitude: nearby.longitude)
            let distMiles = location.distance(from: target) / 1609.34
            if distMiles <= alertRadiusMiles {
                fireAlert(for: nearby)
            }
        }
    }
}

// MARK: - Models

struct NearbyResponse: Decodable {
    let data: NearbyData
}

struct NearbyData: Decodable {
    let results: [NearbyLocation]
}

struct NearbyLocation: Decodable {
    let locationId: String
    let locationName: String?
    let latitude: Double
    let longitude: Double
    let facilityTypeName: String
    let distanceMiles: Double
}
