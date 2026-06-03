import SwiftUI

/// The authenticated-user app shell. Renders the Welcome screen or the
/// active tab's content above a persistent standard-styled tab bar.
struct MainShell: View {
    let user: AuthUser
    @StateObject private var router = AppRouter()
    @EnvironmentObject private var notifications: NotificationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if router.showWelcome {
                    LandingView(user: user)
                } else {
                    tabContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            MainTabBarView()
        }
        .environmentObject(router)
        .onAppear { handlePendingNotification() }
        .onChange(of: notifications.pendingLocationId) { _, _ in
            handlePendingNotification()
        }
    }

    // MARK: - Active tab content

    @ViewBuilder
    private var tabContent: some View {
        switch router.selectedTab {
        case .my:
            NavigationStack(path: $router.myPath) {
                MyInsightsView(user: user)
                    .modifier(TabRootToolbar(user: user))
                    .navigationDestination(for: LocationRoute.self) { route in
                        locationDetail(for: route.destination)
                    }
            }
        case .all:
            NavigationStack(path: $router.allPath) {
                BrowseInsightsView()
                    .modifier(TabRootToolbar(user: user))
                    .navigationDestination(for: LocationRoute.self) { route in
                        locationDetail(for: route.destination)
                    }
            }
        case .new:
            NavigationStack {
                InsightEntryView()
                    .modifier(TabRootToolbar(user: user))
            }
        case .board:
            NavigationStack(path: $router.boardPath) {
                LeaderboardView()
                    .modifier(TabRootToolbar(user: user))
                    .navigationDestination(for: LocationRoute.self) { route in
                        locationDetail(for: route.destination)
                    }
            }
        case .lark:
            NavigationStack(path: $router.larkPath) {
                LarkView()
                    .modifier(TabRootToolbar(user: user))
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func locationDetail(for destination: NotificationLocationDestination) -> some View {
        LocationDetailView(
            locationId: destination.locationId,
            locationName: destination.locationName,
            latitude: destination.latitude,
            longitude: destination.longitude
        )
    }

    private func handlePendingNotification() {
        guard let id = notifications.pendingLocationId,
              let lat = notifications.pendingLatitude,
              let lng = notifications.pendingLongitude else { return }
        let name = notifications.pendingLocationName
        let opensMap = notifications.pendingOpensMap
        notifications.clearPending()

        let destination = NotificationLocationDestination(
            locationId: id,
            locationName: name?.isEmpty == false ? name : nil,
            latitude: lat,
            longitude: lng
        )
        router.openLocation(destination)

        if opensMap, let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lng)\(name.map { "&q=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" } ?? "")") {
            UIApplication.shared.open(url)
        }
    }
}

/// Persistent bottom bar. Standard system tab-bar look (opaque background,
/// system separator, blue/green accent for selected, secondary gray otherwise).
struct MainTabBarView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    router.showWelcome = false
                    router.selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 22))
                        Text(tab.label)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(isSelected(tab) ? Color.tabSelected : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(isSelected(tab) ? .isSelected : [])
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea(edges: .bottom))
    }

    private func isSelected(_ tab: MainTab) -> Bool {
        !router.showWelcome && router.selectedTab == tab
    }
}

/// Adds top-leading Home (returns to Welcome), top-trailing Nearby +
/// Settings buttons to every tab's root view.
struct TabRootToolbar: ViewModifier {
    let user: AuthUser
    @ObservedObject private var alerts = LocationAlertService.shared
    @EnvironmentObject private var router: AppRouter
    @State private var showNearbyStatus = false
    @State private var showSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { router.showWelcome = true }) {
                        Image(systemName: "house.fill")
                            .font(.body.weight(.medium))
                    }
                    .accessibilityLabel("Home")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showNearbyStatus = true }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.body.weight(.medium))
                            if alerts.locationPermissionGranted && alerts.primingChoice == .yes {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 3, y: -2)
                            }
                        }
                    }
                    .accessibilityLabel("Nearby")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .font(.body.weight(.medium))
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showNearbyStatus) {
                NearbyStatusView()
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView(user: user)
                }
            }
    }
}
