import SwiftUI

/// The Welcome screen — presented as a sheet from the Home toolbar button
/// (and automatically when the user first signs in). Shows the brand image
/// plus Logout, Nearby, Settings, and the swap-image test toggle.
struct LandingView: View {
    let user: AuthUser
    @State private var showSettings = false
    @State private var showNearbyStatus = false
    @State private var useAlternateWelcomeImage = false
    @ObservedObject private var alerts = LocationAlertService.shared

    var body: some View {
      NavigationStack {
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
                    VStack(spacing: 1) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.body.weight(.medium))
                        Text("Logout")
                            .font(.system(size: 9, weight: .medium))
                    }
                }
                .accessibilityLabel("Logout")
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
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                }
                .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(user: user)
            }
        }
        .sheet(isPresented: $showNearbyStatus) {
            NearbyStatusView()
        }
      }
    }
}
