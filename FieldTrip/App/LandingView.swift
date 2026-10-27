import SwiftUI

/// The Welcome screen — presented as a sheet from the Home toolbar button
/// (and automatically when the user first signs in). Shows the brand image
/// plus Logout, Nearby, and Settings.
struct LandingView: View {
    let user: AuthUser
    @State private var showSettings = false
    @State private var showNearbyBathrooms = false

    var body: some View {
      NavigationStack {
        GeometryReader { geo in
            Image("NewWelcomeImage")
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showNearbyBathrooms = true }) {
                    Image(systemName: "mappin")
                        .font(.body.weight(.medium))
                }
                .accessibilityLabel("Nearby Bathrooms")
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
        .sheet(isPresented: $showNearbyBathrooms) {
            NavigationStack {
                NearbyBathroomsView()
            }
        }
      }
    }
}
