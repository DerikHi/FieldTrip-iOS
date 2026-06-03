import SwiftUI
import Combine

/// Type passed via NotificationCoordinator / URL deep links.
struct NotificationLocationDestination: Hashable, Identifiable {
    let locationId: String
    let locationName: String?
    let latitude: Double
    let longitude: Double
    var id: String { locationId }
}

extension Color {
    /// The green tint used for the active tab and other accents.
    static let tabSelected = Color(red: 0.13, green: 0.66, blue: 0.27)
}

/// Top-level tabs shown in the standard SwiftUI TabView at the bottom of every screen.
enum MainTab: String, CaseIterable, Identifiable, Hashable {
    case my
    case all
    case new
    case board
    case lark

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .my: return "person.text.rectangle"
        case .all: return "globe"
        case .new: return "plus.circle.fill"
        case .board: return "trophy"
        case .lark: return "bird"
        }
    }

    var label: String {
        switch self {
        case .my: return "My"
        case .all: return "All"
        case .new: return "New"
        case .board: return "Board"
        case .lark: return "Lark"
        }
    }
}

/// Wrapper destinations that can be pushed within each tab's NavigationStack.
struct LocationRoute: Hashable {
    let destination: NotificationLocationDestination
}

@MainActor
final class AppRouter: ObservableObject {
    /// Active bottom tab. The Welcome screen is presented as a separate sheet
    /// triggered by the Home icon in each tab's navigation bar.
    @Published var selectedTab: MainTab = .all

    /// Whether the Welcome screen sheet is currently presented.
    @Published var showWelcome: Bool = true

    /// Each tab carries its own NavigationStack path so back-swipe works
    /// independently per tab.
    @Published var myPath: [LocationRoute] = []
    @Published var allPath: [LocationRoute] = []
    @Published var boardPath: [LocationRoute] = []
    @Published var larkPath: [LocationRoute] = []

    /// Open a specific location detail. Routes through the All tab.
    func openLocation(_ destination: NotificationLocationDestination) {
        selectedTab = .all
        allPath = [LocationRoute(destination: destination)]
    }
}
