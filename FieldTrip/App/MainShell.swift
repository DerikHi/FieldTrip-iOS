import SwiftUI

/// The authenticated-user app shell. Owns the NavigationStack and ensures
/// the persistent bottom tab bar is visible on every screen.
struct MainShell: View {
    let user: AuthUser
    @StateObject private var router = AppRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            LandingView(user: user)
                .navigationDestination(for: Route.self) { route in
                    destinationView(for: route)
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MainTabBar()
        }
        .sheet(isPresented: $router.showAddNew) {
            InsightEntryView()
        }
        .environmentObject(router)
    }

    @ViewBuilder
    private func destinationView(for route: Route) -> some View {
        switch route {
        case .myEntries:
            MyInsightsView(user: user)
        case .browseAll:
            BrowseInsightsView()
        case .leaderboard:
            LeaderboardView()
        case .lark:
            LarkView()
        case .settings:
            SettingsView(user: user)
        case .location(let dest):
            LocationDetailView(
                locationId: dest.locationId,
                locationName: dest.locationName,
                latitude: dest.latitude,
                longitude: dest.longitude
            )
        }
    }
}

/// Modifier that adds a Home (house icon) button at the top-left of the
/// toolbar on every destination. Tapping it returns to the Welcome screen.
struct HomeToolbarModifier: ViewModifier {
    @EnvironmentObject private var router: AppRouter

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { router.goHome() }) {
                        Image(systemName: "house.fill")
                            .font(.body.weight(.medium))
                    }
                    .accessibilityLabel("Home")
                }
            }
            .navigationBarBackButtonHidden(true)
    }
}

extension View {
    /// Adds the standard Home toolbar button. Apply to every pushed
    /// destination that should show "Home" instead of the system back arrow.
    func withHomeToolbar() -> some View {
        modifier(HomeToolbarModifier())
    }
}
