import SwiftUI

struct LandingView: View {
    let user: AuthUser
    @State private var showSpotAPlate = false
    @State private var showAddNew = false
    @State private var showMyEntries = false
    @State private var showBrowseAll = false
    @State private var showLeaderboard = false
    @State private var showFeedback = false

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
            .background(Color.white)
        }
        .navigationTitle("Welcome, \(user.fullName.components(separatedBy: " ").first ?? user.fullName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.white, for: .navigationBar)
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
                let to = "derik.hickling@gmail.com"
                if let url = URL(string: "mailto:\(to)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
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
