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

    // MARK: - Monitoring (now a no-op)

    /// Background location monitoring was removed when the Clean Bathroom
    /// push alerts were retired. The on-demand Nearby Bathrooms screen
    /// requests location via its own one-shot locator.
    func startIfPossible() {}

    func stop() {
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

    /// User explicitly opted in to nearby alerts from inside the app
    /// (i.e. without going through the priming sheet, typically because
    /// they had already granted iOS location permission for another
    /// feature). Records the choice, requests the iOS prompt if needed,
    /// and starts monitoring when possible.
    func enableNearbyAlerts() {
        let userId = primingUserId ?? ""
        UserDefaults.standard.set(PrimingChoice.yes.rawValue, forKey: primingChoiceKey)
        UserDefaults.standard.set(userId, forKey: primingUserIdKey)

        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startIfPossible()
        default:
            break
        }
    }

    /// Register the notification category once at app launch. Kept as a
    /// no-op for now — the Clean Bathroom push alerts have been removed;
    /// users browse the Nearby Bathrooms screen explicitly instead.
    func registerNotificationCategory() {}
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
        // Background monitoring no longer fires push alerts. Users access
        // the Nearby Bathrooms screen on demand; this delegate exists only
        // so the system permission updates above are picked up.
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
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
    /// Dominant Clean Bathroom rating across this location's insights,
    /// returned as the lowercase apiValue ("great", "good", "meh", etc.).
    /// nil when the location has no Clean Bathroom ratings yet.
    let cleanBathroomRating: String?
}
