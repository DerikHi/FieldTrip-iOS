import SwiftUI
import MapKit

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()
    @State private var viewMode: ViewMode = .list
    @State private var showFilters = false

    enum ViewMode { case list, map }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("City, location name, or coordinates", text: $vm.searchText)
                            .onSubmit { Task { await vm.performSearch() } }
                            .onChange(of: vm.searchText) { _, _ in vm.triggerSearch() }
                        if !vm.searchText.isEmpty {
                            Button(action: { vm.searchText = "" }) {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                    Button(action: { showFilters.toggle() }) {
                        Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .font(.title2)
                    }
                    .accessibilityLabel("Filters")
                    .frame(minWidth: 44, minHeight: 44)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Filters panel
                if showFilters {
                    FilterPanelView(vm: vm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Near Me button
                Button(action: { Task { await vm.nearMe() } }) {
                    Label(vm.isLoadingNearMe ? "Finding nearby…" : "What's Near Me?", systemImage: "location.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                .padding(.bottom, 4)
                .disabled(vm.isLoadingNearMe)

                // View mode toggle
                Picker("View", selection: $viewMode) {
                    Label("List", systemImage: "list.bullet").tag(ViewMode.list)
                    Label("Map", systemImage: "map").tag(ViewMode.map)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                Divider()

                // Results
                if vm.isLoading {
                    Spacer()
                    ProgressView("Searching…")
                    Spacer()
                } else if let error = vm.errorMessage {
                    Spacer()
                    ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
                    Spacer()
                } else if viewMode == .list {
                    ResultsListView(vm: vm)
                } else {
                    ResultsMapView(vm: vm)
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .animation(.easeInOut(duration: 0.2), value: showFilters)
        }
    }
}

// MARK: - Filter Panel

struct FilterPanelView: View {
    @ObservedObject var vm: SearchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            // Radius
            HStack {
                Text("Search radius: \(Int(vm.radiusMiles)) miles")
                    .font(.subheadline.bold())
                Spacer()
            }
            Slider(value: $vm.radiusMiles, in: 5...200, step: 5)
                .onChange(of: vm.radiusMiles) { _, _ in vm.triggerSearch() }

            // Min rating
            HStack {
                Text("Min rating: \(Int(vm.minRating))★")
                    .font(.subheadline.bold())
                Spacer()
            }
            Slider(value: $vm.minRating, in: 1...5, step: 1)
                .onChange(of: vm.minRating) { _, _ in vm.triggerSearch() }

            // Facility type filter
            Text("Facility type").font(.subheadline.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ChipButton(title: "All", isSelected: vm.selectedFacilityTypeId == nil) {
                        vm.selectedFacilityTypeId = nil
                        vm.triggerSearch()
                    }
                    ForEach(vm.facilityTypes) { type in
                        ChipButton(title: type.name, isSelected: vm.selectedFacilityTypeId == type.id) {
                            vm.selectedFacilityTypeId = vm.selectedFacilityTypeId == type.id ? nil : type.id
                            vm.triggerSearch()
                        }
                    }
                }
                .padding(.horizontal, 1)
            }

            Divider()
        }
        .padding(.horizontal)
        .background(Color(.systemBackground))
    }
}

private struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
        .frame(minHeight: 44)
    }
}

// MARK: - Results List

struct ResultsListView: View {
    @ObservedObject var vm: SearchViewModel

    var displayResults: [SearchViewModel.SearchResult] {
        vm.searchText.isEmpty && vm.nearMeResults.isEmpty ? [] :
        vm.nearMeResults.isEmpty ? vm.results : vm.nearMeResults
    }

    var body: some View {
        Group {
            if displayResults.isEmpty {
                ContentUnavailableView(
                    "Search for a location",
                    systemImage: "magnifyingglass",
                    description: Text("Enter a city name, paste coordinates, or tap \"What's Near Me?\"")
                )
            } else {
                List(displayResults) { result in
                    NavigationLink(destination: InsightDetailView(locationId: result.locationId)) {
                        ResultRowView(result: result)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

struct ResultRowView: View {
    let result: SearchViewModel.SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(result.displayName)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                Spacer()
                if let rating = result.ratingText {
                    Text(rating)
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 12) {
                Label(result.facilityTypeName, systemImage: "mappin.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let dist = result.distanceText {
                    Label(dist, systemImage: "arrow.triangle.swap")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if result.insightCount > 0 {
                Text("\(result.insightCount) insight\(result.insightCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Results Map

struct ResultsMapView: View {
    @ObservedObject var vm: SearchViewModel

    var body: some View {
        Map(coordinateRegion: $vm.mapRegion, annotationItems: vm.results) { result in
            MapAnnotation(coordinate: result.coordinate) {
                Button(action: { vm.selectedResult = result }) {
                    VStack(spacing: 2) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                        if let rating = result.ratingText {
                            Text(rating)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(.red)
                                .cornerRadius(4)
                        }
                    }
                }
                .accessibilityLabel(result.displayName)
            }
        }
        .sheet(item: $vm.selectedResult) { result in
            NavigationStack {
                InsightDetailView(locationId: result.locationId)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { vm.selectedResult = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Insight Detail

struct InsightDetailView: View {
    let locationId: String
    @State private var insights: [Insight] = []
    @State private var isLoading = true

    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading insights…")
            } else if insights.isEmpty {
                ContentUnavailableView("No insights yet", systemImage: "bubble.left")
            } else {
                List(insights) { insight in
                    InsightCardView(insight: insight)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Location Insights")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadInsights() }
    }

    private func loadInsights() async {
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "\(apiBaseURL)/api/insights?locationId=\(locationId)") else { return }
        let token = KeychainService.retrieve(for: .authToken) ?? ""
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            // TODO: parse insights response
        } catch {}
    }
}

struct InsightCardView: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(insight.user.fullName)
                    .font(.subheadline.bold())
                Spacer()
                Text(insight.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !insight.ratings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(insight.ratings) { rating in
                            VStack(spacing: 2) {
                                if let icon = rating.featureCategory.icon {
                                    Image(systemName: icon).font(.caption)
                                }
                                Text("\(rating.rating)").font(.caption.bold())
                                Text(rating.featureCategory.name).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                    }
                }
            }

            if let comment = insight.comment, !comment.isEmpty {
                Text(comment)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !insight.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(insight.photos) { photo in
                            AsyncImage(url: URL(string: photo.url)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color(.secondarySystemBackground)
                            }
                            .frame(width: 80, height: 80)
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}
