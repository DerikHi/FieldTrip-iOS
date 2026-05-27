import SwiftUI

struct SpotAPlateView: View {
    @State private var selectedState = ""
    @State private var tallies: [String: Int] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showClearAllConfirm = false

    private static let usStates = [
        "Alabama", "Alaska", "Arizona", "Arkansas", "California",
        "Colorado", "Connecticut", "Delaware", "District of Columbia",
        "Florida", "Georgia", "Hawaii", "Idaho", "Illinois", "Indiana",
        "Iowa", "Kansas", "Kentucky", "Louisiana", "Maine", "Maryland",
        "Massachusetts", "Michigan", "Minnesota", "Mississippi", "Missouri",
        "Montana", "Nebraska", "Nevada", "New Hampshire", "New Jersey",
        "New Mexico", "New York", "North Carolina", "North Dakota", "Ohio",
        "Oklahoma", "Oregon", "Pennsylvania", "Rhode Island",
        "South Carolina", "South Dakota", "Tennessee", "Texas", "Utah",
        "Vermont", "Virginia", "Washington", "West Virginia", "Wisconsin",
        "Wyoming"
    ]

    var body: some View {
        VStack(spacing: 0) {
            Picker("Select a State", selection: $selectedState) {
                Text("Select a State").tag("")
                ForEach(Self.usStates, id: \.self) { state in
                    Text(state).tag(state)
                }
            }
            .pickerStyle(.menu)
            .disabled(isLoading)
            .padding()

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error)
                        .font(.subheadline)
                }
                .foregroundStyle(.red)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            if isLoading && tallies.isEmpty {
                ProgressView()
                    .padding(.top, 40)
                Spacer()
            } else {
                USMapView(spottedStates: Set(tallies.keys))
                    .aspectRatio(959.0 / 593.0, contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .padding(.top, 8)

                Text("\(tallies.count) of \(Self.usStates.count) spotted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                if !sortedTallies.isEmpty {
                    Button(role: .destructive) {
                        showClearAllConfirm = true
                    } label: {
                        Label("Clear All Spotted Plates", systemImage: "trash")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                if sortedTallies.isEmpty {
                    ContentUnavailableView(
                        "No Plates Spotted",
                        systemImage: "car.side",
                        description: Text("Select a state above to start tracking license plates.")
                    )
                } else {
                    List {
                        ForEach(sortedTallies, id: \.state) { entry in
                            HStack {
                                Text(entry.state)
                                Spacer()
                                Text("\(entry.count)")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                Button {
                                    Task { await decrement(state: entry.state) }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove one \(entry.state) sighting")
                                .padding(.leading, 8)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("Spot A Plate")
        .onChange(of: selectedState) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task { await recordSighting(state: newValue) }
            selectedState = ""
        }
        .task { await fetchTallies() }
        .confirmationDialog(
            "Clear all spotted plates?",
            isPresented: $showClearAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                Task { await clearAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every plate sighting for your account. You'll start with a clean map.")
        }
    }

    private func decrement(state: String) async {
        errorMessage = nil
        let previous = tallies[state] ?? 0
        let optimistic = max(previous - 1, 0)
        if optimistic == 0 {
            tallies.removeValue(forKey: state)
        } else {
            tallies[state] = optimistic
        }

        do {
            let response = try await PlateService.shared.decrementSighting(state: state)
            if response.count == 0 {
                tallies.removeValue(forKey: response.state)
            } else {
                tallies[response.state] = response.count
            }
        } catch {
            tallies[state] = previous
            errorMessage = "Could not remove sighting."
        }
    }

    private func clearAll() async {
        errorMessage = nil
        let snapshot = tallies
        tallies = [:]

        do {
            try await PlateService.shared.clearAllSightings()
        } catch {
            tallies = snapshot
            errorMessage = "Could not clear sightings."
        }
    }

    private var sortedTallies: [(state: String, count: Int)] {
        tallies.map { (state: $0.key, count: $0.value) }
            .sorted { $0.state < $1.state }
    }

    private func fetchTallies() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let results = try await PlateService.shared.fetchTallies()
            tallies = Dictionary(uniqueKeysWithValues: results.map { ($0.state, $0.count) })
        } catch {
            errorMessage = "Could not load tallies."
        }
    }

    private func recordSighting(state: String) async {
        errorMessage = nil
        tallies[state, default: 0] += 1

        do {
            let response = try await PlateService.shared.recordSighting(state: state)
            tallies[response.state] = response.count
        } catch {
            tallies[state, default: 1] -= 1
            if tallies[state] == 0 { tallies.removeValue(forKey: state) }
            errorMessage = "Could not save sighting."
        }
    }
}

#Preview {
    NavigationStack {
        SpotAPlateView()
    }
}
