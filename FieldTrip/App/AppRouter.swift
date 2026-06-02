import SwiftUI
import Combine

/// Type-safe destinations that the app's NavigationStack knows how to render.
enum Route: Hashable {
    case newEntry
    case myEntries
    case browseAll
    case leaderboard
    case lark
    case settings
    case location(NotificationLocationDestination)
}

/// Tabs shown in the persistent bottom bar.
enum MainTab: String, CaseIterable, Identifiable {
    case new
    case my
    case all
    case board
    case lark

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .new: return "plus.circle"
        case .my: return "person.text.rectangle"
        case .all: return "globe"
        case .board: return "trophy"
        case .lark: return "bird"
        }
    }

    var label: String {
        switch self {
        case .new: return "New"
        case .my: return "My"
        case .all: return "All"
        case .board: return "Board"
        case .lark: return "Lark"
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var path: [Route] = []
    @Published var selectedTab: MainTab? = nil

    func goHome() {
        path.removeAll()
        selectedTab = nil
    }

    func go(to route: Route, tab: MainTab? = nil) {
        path = [route]
        selectedTab = tab
    }

    func tapTab(_ tab: MainTab) {
        switch tab {
        case .new:
            go(to: .newEntry, tab: .new)
        case .my:
            go(to: .myEntries, tab: .my)
        case .all:
            go(to: .browseAll, tab: .all)
        case .board:
            go(to: .leaderboard, tab: .board)
        case .lark:
            go(to: .lark, tab: .lark)
        }
    }
}
