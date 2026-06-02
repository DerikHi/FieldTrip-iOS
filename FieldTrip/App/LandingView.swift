import SwiftUI

struct LandingView: View {
    let user: AuthUser
    @State private var showPriming = false
    @State private var showNearbyStatus = false
    @State private var useAlternateWelcomeImage = false
    @ObservedObject private var alerts = LocationAlertService.shared
    @EnvironmentObject private var notifications: NotificationCoordinator
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        GeometryReader { geo in
            Image(useAlternateWelcomeImage ? "NewWelcomeImage" : "LogoWelcome")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .ignoresSafeArea(edges: .bottom)
        .navigationTitle("Welcome, \(user.fullName.components(separatedBy: " ").first ?? user.fullName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    try? AuthService.shared.signOut()
                }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.body.weight(.medium))
                }
                .accessibilityLabel("Sign out")
            }
            ToolbarItem(placement: .principal) {
                Button(action: {
                    withAnimation { useAlternateWelcomeImage.toggle() }
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body.weight(.medium))
                }
                .accessibilityLabel("Swap welcome image")
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
                Button(action: { router.go(to: .settings) }) {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showPriming) {
            LocationPrimingView(userId: user.id) { }
        }
        .sheet(isPresented: $showNearbyStatus) {
            NearbyStatusView()
        }
        .onAppear {
            router.selectedTab = nil
            alerts.incrementLaunchCount()
            if alerts.shouldShowPriming(for: user.id) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showPriming = true
                }
            } else {
                alerts.startIfPossible()
            }
            handlePendingNotification()
        }
        .onChange(of: notifications.pendingLocationId) { _, _ in
            handlePendingNotification()
        }
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
        router.path = [.location(destination)]

        if opensMap, let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lng)\(name.map { "&q=\($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" } ?? "")") {
            UIApplication.shared.open(url)
        }
    }
}

struct NotificationLocationDestination: Hashable, Identifiable {
    let locationId: String
    let locationName: String?
    let latitude: Double
    let longitude: Double
    var id: String { locationId }
}

#Preview {
    SplashRouterView()
}
