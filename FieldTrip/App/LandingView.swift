import SwiftUI

struct LandingView: View {
    let user: AuthUser
    @State private var showSpotAPlate = false
    @State private var showAddNew = false
    @State private var showMyEntries = false
    @State private var showBrowseAll = false
    @State private var showLeaderboard = false
    @State private var showFeedback = false
    @State private var showPriming = false
    @State private var showNearbyStatus = false
    @State private var notificationLocation: NotificationLocationDestination?
    @ObservedObject private var alerts = LocationAlertService.shared
    @EnvironmentObject private var notifications: NotificationCoordinator

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                Image("WelcomeScreen")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }

            Divider()

            HStack {
                BottomBarButton(icon: "plus.circle", label: "New") {
                    showAddNew = true
                }
                BottomBarButton(icon: "person.text.rectangle", label: "My") {
                    showMyEntries = true
                }
                BottomBarButton(icon: "globe", label: "All") {
                    showBrowseAll = true
                }
                BottomBarButton(icon: "trophy", label: "Board") {
                    showLeaderboard = true
                }
                BottomBarButton(icon: "car.rear", label: "Plates") {
                    showSpotAPlate = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
        .navigationTitle("Welcome, \(user.fullName.components(separatedBy: " ").first ?? user.fullName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color(.systemBackground), for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    try? AuthService.shared.signOut()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.medium))
                }
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
                Button(action: { showFeedback = true }) {
                    Image(systemName: "envelope")
                        .font(.body.weight(.medium))
                }
            }
        }
        .navigationDestination(isPresented: $showLeaderboard) {
            LeaderboardView()
        }
        .navigationDestination(isPresented: $showSpotAPlate) {
            SpotAPlateView()
        }
        .navigationDestination(isPresented: $showMyEntries) {
            MyInsightsView(user: user)
        }
        .navigationDestination(isPresented: $showBrowseAll) {
            BrowseInsightsView()
        }
        .sheet(isPresented: $showAddNew) {
            InsightEntryView()
        }
        .onChange(of: showFeedback) { _, show in
            if show {
                showFeedback = false
                let subject = "[FieldTrip Feedback]"
                let to = "info@fieldtrippro.com"
                if let url = URL(string: "mailto:\(to)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                    UIApplication.shared.open(url)
                }
            }
        }
        .sheet(isPresented: $showPriming) {
            LocationPrimingView(userId: user.id) { }
        }
        .sheet(isPresented: $showNearbyStatus) {
            NearbyStatusView()
        }
        .navigationDestination(item: $notificationLocation) { dest in
            LocationDetailView(
                locationId: dest.locationId,
                locationName: dest.locationName,
                latitude: dest.latitude,
                longitude: dest.longitude
            )
        }
        .onAppear {
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
}

extension LandingView {
    private func handlePendingNotification() {
        guard let id = notifications.pendingLocationId,
              let lat = notifications.pendingLatitude,
              let lng = notifications.pendingLongitude else { return }
        let name = notifications.pendingLocationName
        let opensMap = notifications.pendingOpensMap
        notifications.clearPending()

        notificationLocation = NotificationLocationDestination(
            locationId: id,
            locationName: name?.isEmpty == false ? name : nil,
            latitude: lat,
            longitude: lng
        )

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

private struct BottomBarButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        LandingView(user: AuthUser(
            id: "preview",
            email: "jane@example.com",
            fullName: "Jane Smith",
            role: .user,
            organization: nil,
            createdAt: Date()
        ))
    }
}
