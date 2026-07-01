import SwiftUI

struct LeaderboardView: View {
    @State private var topUsers: [LeaderboardUser] = []
    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Unable to Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if entries.isEmpty {
                ContentUnavailableView(
                    "No Check-ins Yet",
                    systemImage: "mappin.and.ellipse",
                    description: Text("Check in at locations to see them on the leaderboard.")
                )
            } else {
                List {
                    if !topUsers.isEmpty {
                        Section {
                            ForEach(Array(topUsers.enumerated()), id: \.element.userId) { index, user in
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.headline)
                                        .foregroundStyle(.yellow)
                                        .frame(width: 28, alignment: .center)

                                    Text(user.fullName)
                                        .font(.subheadline.weight(.medium))

                                    Spacer()

                                    HStack(spacing: 4) {
                                        Image(systemName: "figure.walk")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                        Text("\(user.checkInCount)")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        } header: {
                            Text("Top Explorers")
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                                .textCase(nil)
                        }
                    }

                    Section {
                    let filtered = entries.filter { $0.checkInCount > 0 }
                    ForEach(Array(filtered.enumerated()), id: \.element.locationId) { index, entry in
                        NavigationLink(destination: LocationDetailView(
                            locationId: entry.locationId,
                            locationName: entry.locationName,
                            latitude: entry.latitude,
                            longitude: entry.longitude
                        )) {
                            HStack(spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .center)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.locationName ?? "Unnamed Location")
                                        .font(.headline)
                                    HStack(spacing: 0) {
                                        Text(entry.facilityTypeName)
                                        if let town = entry.town, !town.isEmpty {
                                            Text(" - \(town)")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                HStack(spacing: 4) {
                                    Image(systemName: "figure.walk")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                    Text("\(entry.checkInCount)")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    } header: {
                        Text("Top Spots")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Check In Leaderboard")
        .task { await loadLeaderboard() }
    }

    private func loadLeaderboard() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let decoded = try await APIClient.shared.get(
                "/api/checkins/leaderboard",
                decode: APIResponse<LeaderboardPage>.self
            )
            topUsers = decoded.data.topUsers
            entries = decoded.data.results
        } catch {
            errorMessage = "An error has occurred, please log in again."
        }
    }
}

struct LeaderboardPage: Decodable {
    let topUsers: [LeaderboardUser]
    let results: [LeaderboardEntry]
}

struct LeaderboardUser: Decodable {
    let userId: String
    let fullName: String
    let checkInCount: Int
}

struct LeaderboardEntry: Decodable {
    let locationId: String
    let locationName: String?
    let town: String?
    let facilityTypeName: String
    let latitude: Double
    let longitude: Double
    let checkInCount: Int
}

#Preview {
    NavigationStack {
        LeaderboardView()
    }
}
