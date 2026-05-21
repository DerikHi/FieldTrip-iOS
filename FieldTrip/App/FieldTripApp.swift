import SwiftUI
import FirebaseCore
import UserNotifications
import Combine

@main
struct FieldTripApp: App {
    @StateObject private var notificationCoordinator = NotificationCoordinator.shared

    init() {
        FirebaseApp.configure()
        LocationAlertService.shared.registerNotificationCategory()
        UNUserNotificationCenter.current().delegate = NotificationCoordinator.shared
    }

    var body: some Scene {
        WindowGroup {
            SplashRouterView()
                .environmentObject(notificationCoordinator)
                .onOpenURL { url in
                    notificationCoordinator.handleDeepLink(url)
                }
        }
    }
}

@MainActor
final class NotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    @Published var pendingLocationId: String?
    @Published var pendingLocationName: String?
    @Published var pendingLatitude: Double?
    @Published var pendingLongitude: Double?
    @Published var pendingOpensMap = false

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier
        Task { @MainActor in
            if actionId == "DISMISS" {
                completionHandler()
                return
            }
            pendingLocationId = info["locationId"] as? String
            pendingLocationName = info["locationName"] as? String
            pendingLatitude = info["latitude"] as? Double
            pendingLongitude = info["longitude"] as? Double
            pendingOpensMap = (actionId == "OPEN_MAP")
            completionHandler()
        }
    }

    func clearPending() {
        pendingLocationId = nil
        pendingLocationName = nil
        pendingLatitude = nil
        pendingLongitude = nil
        pendingOpensMap = false
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "fieldtrippro",
              url.host == "location",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return }

        let map = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (String, String)? in
            guard let value = item.value else { return nil }
            return (item.name, value)
        })
        guard let id = map["id"],
              let latString = map["lat"], let lat = Double(latString),
              let lngString = map["lng"], let lng = Double(lngString) else { return }

        pendingLocationId = id
        pendingLocationName = map["name"]
        pendingLatitude = lat
        pendingLongitude = lng
        pendingOpensMap = false
    }

    static func deepLinkURL(id: String, name: String?, lat: Double, lng: Double) -> URL? {
        var components = URLComponents()
        components.scheme = "fieldtrippro"
        components.host = "location"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
        ]
        if let name, !name.isEmpty {
            items.append(URLQueryItem(name: "name", value: name))
        }
        components.queryItems = items
        return components.url
    }
}
