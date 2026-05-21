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
}
