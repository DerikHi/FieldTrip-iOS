import SwiftUI
import CoreLocation
import MapKit
import UIKit
import Combine

struct BrowseInsightsView: View {
    @State private var searchText = ""
    @State private var results: [BrowseLocation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasSearched = false

    // Location search
    @State private var searchLatitude: Double?
    @State private var searchLongitude: Double?
    @State private var radiusMiles: Double = 5
    @State private var coordinatePasteInput = ""
    @State private var coordinatePasteError: String?
    @State private var isGettingLocation = false
    @State private var showLocationOptions = false
    @StateObject private var locationHelper = BrowseLocationHelper()

    // Facility type filter
    @State private var facilityTypes: [FacilityType] = []
    @State private var selectedFacilityTypeId: String?

    private var hasCoordinates: Bool {
        searchLatitude != nil && searchLongitude != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(error)
                        .font(.subheadline)
                }
                .foregroundStyle(.red)
                .padding()
            }

            VStack(spacing: 12) {
                if !facilityTypes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(.subheadline.bold())
                        Picker("Select a type", selection: Binding(
                            get: { selectedFacilityTypeId ?? "" },
                            set: { selectedFacilityTypeId = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("All").tag("")
                            ForEach(facilityTypes) { type in
                                Text(type.name).tag(type.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }

                // Search by name or town
                VStack(alignment: .leading, spacing: 8) {
                    Text("Search by name or town")
                        .font(.subheadline.bold())
                    TextField("e.g. Flying J or Springfield", text: $searchText)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Text("or")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Location search toggle
                Button(action: { withAnimation { showLocationOptions.toggle() } }) {
                    HStack {
                        Image(systemName: showLocationOptions ? "location.fill" : "location")
                        Text(hasCoordinates ? "Location set" : "Search by location")
                            .font(.subheadline)
                        Spacer()
                        if hasCoordinates {
                            Button(action: { clearLocation() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Image(systemName: showLocationOptions ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(hasCoordinates ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(hasCoordinates ? Color.accentColor : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                if showLocationOptions {
                    VStack(spacing: 12) {
                        // GPS button
                        Button(action: { requestLocation() }) {
                            Label(
                                isGettingLocation ? "Getting location…" : "Use Current GPS Location",
                                systemImage: "location.fill"
                            )
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isGettingLocation)

                        // Paste coordinates or town
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Coordinates, map link, or town", text: $coordinatePasteInput)
                                .padding(10)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                                .submitLabel(.search)
                                .onSubmit { parseCoordinates() }

                            if let error = coordinatePasteError {
                                Text(error).font(.caption).foregroundStyle(.red)
                            }

                            Button(action: {
                                if let text = UIPasteboard.general.string {
                                    coordinatePasteInput = text
                                    parseCoordinates()
                                }
                            }) {
                                Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }

                        if hasCoordinates {
                            Text(String(format: "📍 %.4f, %.4f", searchLatitude!, searchLongitude!))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Search radius: \(Int(radiusMiles)) \(Int(radiusMiles) == 1 ? "mile" : "miles")")
                        .font(.subheadline.bold())
                    Slider(value: $radiusMiles, in: 1...100, step: 1)
                }
                .padding(.horizontal)

                Divider()
            }

            if isLoading {
                ProgressView()
                    .padding(.top, 40)
                Spacer()
            } else if results.isEmpty && hasSearched {
                ContentUnavailableView.search(text: searchText)
            } else if results.isEmpty {
                Spacer()
            } else {
                List {
                    ForEach(results) { location in
                        NavigationLink(destination: LocationDetailView(locationId: location.locationId, locationName: location.locationName, latitude: location.latitude, longitude: location.longitude)) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(location.locationName ?? "Unnamed Location")
                                            .font(.headline)
                                        if let town = location.town, !town.isEmpty {
                                            Text(town)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if let facilityType = location.facilityTypeName {
                                        Text(facilityType)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                }

                                HStack(spacing: 12) {
                                    if let avgRating = location.avgRating {
                                        HStack(spacing: 4) {
                                            Image(systemName: "star.fill")
                                                .font(.caption)
                                                .foregroundStyle(.yellow)
                                            Text(String(format: "%.1f", avgRating))
                                                .font(.subheadline.weight(.medium))
                                            Text("rating")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    if let distance = location.distanceMiles {
                                        HStack(spacing: 4) {
                                            Image(systemName: "location.fill")
                                                .font(.caption)
                                            Text(String(format: "%.1f mi", distance))
                                                .font(.caption)
                                        }
                                        .foregroundStyle(.secondary)
                                    }

                                    Text("\(location.insightCount) \(location.insightCount == 1 ? "entry" : "entries")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                if let comment = location.comment, !comment.isEmpty {
                                    Text(comment)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                if let reviewer = location.reviewerName {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 9))
                                        Text(reviewer)
                                            .font(.subheadline)
                                    }
                                    .foregroundStyle(.secondary)
                                }

                                let attrs = (location.attributeRatings ?? []).prefix(4)
                                if !attrs.isEmpty {
                                    HStack(spacing: 8) {
                                        ForEach(attrs) { attr in
                                            HStack(spacing: 2) {
                                                Image(systemName: attr.rating == "good" ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(attr.rating == "good" ? .green : .red)
                                                Text(attr.attributeName)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Browse All")
        .task { await loadFacilityTypes() }
        .onChange(of: radiusMiles) { _, _ in
            if hasSearched {
                Task { await search() }
            }
        }
        .onChange(of: selectedFacilityTypeId) { _, _ in
            if hasSearched {
                Task { await search() }
            }
        }
        .onChange(of: locationHelper.latitude) { _, lat in
            if let lat, let lng = locationHelper.longitude {
                searchLatitude = lat
                searchLongitude = lng
                isGettingLocation = false
                Task { await search() }
            }
        }
        .onChange(of: locationHelper.authStatus) { _, status in
            if status == .authorizedWhenInUse && isGettingLocation {
                locationHelper.requestLocation()
            }
        }
    }

    private func requestLocation() {
        isGettingLocation = true
        switch locationHelper.authStatus {
        case .notDetermined:
            locationHelper.requestAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationHelper.requestLocation()
        case .denied, .restricted:
            errorMessage = "Location access denied. Enable it in Settings or paste coordinates."
            isGettingLocation = false
        @unknown default:
            isGettingLocation = false
        }
    }

    private func parseCoordinates() {
        coordinatePasteError = nil
        let trimmed = coordinatePasteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let coords = ValidationService.parseCoordinates(from: trimmed) {
            searchLatitude = coords.lat
            searchLongitude = coords.lng
            coordinatePasteError = nil
            Task { await search() }
            return
        }

        Task {
            if PlusCodeService.looksLikePlusCode(trimmed),
               let coords = await PlusCodeService.decode(trimmed) {
                searchLatitude = coords.latitude
                searchLongitude = coords.longitude
                coordinatePasteError = nil
                await search()
                return
            }

            let geocoder = CLGeocoder()
            do {
                guard let placemark = try await geocoder.geocodeAddressString(trimmed).first,
                      let location = placemark.location else {
                    coordinatePasteError = "Could not find that location. Try 'lat, lng', a map link, a Plus Code, or a town name like 'Springfield, IL'."
                    return
                }
                searchLatitude = location.coordinate.latitude
                searchLongitude = location.coordinate.longitude
                coordinatePasteError = nil
                await search()
            } catch {
                coordinatePasteError = "Could not find that location. Try 'lat, lng', a map link, a Plus Code, or a town name like 'Springfield, IL'."
            }
        }
    }

    private func clearLocation() {
        searchLatitude = nil
        searchLongitude = nil
        coordinatePasteInput = ""
    }

    private func loadFacilityTypes() async {
        facilityTypes = InsightEntryViewModel.fallbackFacilityTypes
    }

    private func search() async {
        let hasText = !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        guard hasText || hasCoordinates else { return }

        isLoading = true
        hasSearched = true
        errorMessage = nil
        defer { isLoading = false }

        guard let token = KeychainService.retrieve(for: .authToken) else {
            errorMessage = "Please sign in again."
            return
        }

        let baseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"

        var components = URLComponents(string: "\(baseURL)/api/search")!
        var queryItems: [URLQueryItem] = []

        if hasText {
            queryItems.append(URLQueryItem(name: "locationName", value: searchText))
        }

        queryItems.append(URLQueryItem(name: "radiusMiles", value: String(Int(radiusMiles))))

        if let facilityTypeId = selectedFacilityTypeId {
            if facilityTypeId.hasPrefix("fb-") {
                let name = facilityTypes.first(where: { $0.id == facilityTypeId })?.name ?? ""
                if !name.isEmpty {
                    queryItems.append(URLQueryItem(name: "facilityTypeName", value: name))
                }
            } else {
                queryItems.append(URLQueryItem(name: "facilityTypeId", value: facilityTypeId))
            }
        }

        if let lat = searchLatitude, let lng = searchLongitude {
            queryItems.append(URLQueryItem(name: "lat", value: String(lat)))
            queryItems.append(URLQueryItem(name: "lng", value: String(lng)))
        }

        components.queryItems = queryItems
        guard let url = components.url else {
            errorMessage = "Invalid search."
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as! HTTPURLResponse

            guard http.statusCode == 200 else {
                errorMessage = "Server error (\(http.statusCode))."
                return
            }

            let decoded = try JSONDecoder.apiDecoder.decode(
                APIResponse<BrowseSearchResult>.self, from: data
            )
            results = decoded.data.results
        } catch {
            errorMessage = "Could not load results."
        }
    }
}

// MARK: - Location Helper

@MainActor
final class BrowseLocationHelper: NSObject, ObservableObject {
    @Published var latitude: Double?
    @Published var longitude: Double?
    @Published var authStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        authStatus = manager.authorizationStatus
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        manager.requestLocation()
    }
}

extension BrowseLocationHelper: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            latitude = location.coordinate.latitude
            longitude = location.coordinate.longitude
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authStatus = manager.authorizationStatus
        }
    }
}

struct BrowseSearchResult: Decodable {
    let results: [BrowseLocation]
}

struct BrowseLocation: Decodable, Identifiable {
    let locationId: String
    let locationName: String?
    let town: String?
    let latitude: Double
    let longitude: Double
    let insightCount: Int
    let avgRating: Double?
    let distanceMiles: Double?
    let reviewerName: String?
    let facilityTypeName: String?
    let comment: String?
    let attributeRatings: [BrowseAttributeRating]?

    var id: String { locationId }
}

struct BrowseAttributeRating: Decodable, Identifiable {
    let id: String
    let attributeName: String
    let rating: String
}

// MARK: - Location Detail View

struct LocationDetailView: View {
    let locationId: String
    let locationName: String?
    let latitude: Double
    let longitude: Double

    @State private var insights: [LocationInsight] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var checkInCount = 0
    @State private var isCheckingIn = false
    @State private var showMapChoice = false
    @State private var fullScreenPhotoURL: URL?

    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading…")
            } else if let error = errorMessage {
                ContentUnavailableView(error, systemImage: "exclamationmark.triangle")
            } else if insights.isEmpty {
                ContentUnavailableView("No entries yet", systemImage: "bubble.left")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Check-in
                        HStack {
                            Button(action: { Task { await addCheckIn() } }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                            }
                            .disabled(isCheckingIn)

                            Text("\(checkInCount)")
                                .font(.title3.weight(.semibold))

                            Text(checkInCount == 1 ? "check-in" : "check-ins")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                        // Rating
                        let starRatings = insights.compactMap(\.starRating)
                        if !starRatings.isEmpty {
                            let avg = Double(starRatings.reduce(0, +)) / Double(starRatings.count)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rating")
                                    .font(.subheadline.bold())
                                HStack(spacing: 4) {
                                    ForEach(1...5, id: \.self) { star in
                                        Image(systemName: Double(star) <= avg + 0.5 ? "star.fill" : "star")
                                            .foregroundStyle(.yellow)
                                    }
                                    Text(String(format: "%.1f", avg))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("(\(starRatings.count) \(starRatings.count == 1 ? "review" : "reviews"))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }

                        // Attributes
                        let allAttributes = insights.flatMap { $0.attributeRatings ?? [] }
                        if !allAttributes.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Attributes")
                                    .font(.subheadline.bold())

                                let grouped = Dictionary(grouping: allAttributes, by: \.attributeName)
                                ForEach(grouped.keys.sorted(), id: \.self) { name in
                                    let ratings = grouped[name]!
                                    let goodCount = ratings.filter { $0.rating == "good" }.count
                                    let badCount = ratings.filter { $0.rating == "bad" }.count
                                    let total = goodCount + badCount

                                    HStack {
                                        Text(name)
                                            .font(.subheadline)
                                        Spacer()
                                        if goodCount > 0 {
                                            Label("\(goodCount)", systemImage: "hand.thumbsup.fill")
                                                .font(.caption.bold())
                                                .foregroundStyle(.green)
                                        }
                                        if badCount > 0 {
                                            Label("\(badCount)", systemImage: "hand.thumbsdown.fill")
                                                .font(.caption.bold())
                                                .foregroundStyle(.red)
                                                .padding(.leading, 4)
                                        }
                                        if total > 0 {
                                            let pct = Int(Double(goodCount) / Double(total) * 100)
                                            Text("\(pct)%")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 36, alignment: .trailing)
                                        }
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }

                        // Comments
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Comments")
                                .font(.subheadline.bold())

                            ForEach(insights) { insight in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(insight.user?.fullName ?? "Anonymous")
                                            .font(.subheadline.bold())
                                        Spacer()
                                        if let star = insight.starRating {
                                            HStack(spacing: 2) {
                                                Image(systemName: "star.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.yellow)
                                                Text("\(star)")
                                                    .font(.caption.bold())
                                            }
                                        }
                                    }

                                    if let comment = insight.comment, !comment.isEmpty {
                                        Text(comment)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(insight.createdAt, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                        }

                        // Photos
                        let allPhotos = insights.flatMap { $0.photos ?? [] }
                        if !allPhotos.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Photos")
                                    .font(.subheadline.bold())
                                ForEach(allPhotos, id: \.id) { photo in
                                    AsyncImage(url: URL(string: photo.url)) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 220)
                                            .clipped()
                                            .cornerRadius(10)
                                            .onTapGesture {
                                                if let url = URL(string: photo.url) {
                                                    fullScreenPhotoURL = url
                                                }
                                            }
                                    } placeholder: {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(.secondarySystemBackground))
                                            .frame(height: 220)
                                            .overlay(ProgressView())
                                    }
                                }
                            }
                        }

                        // Location
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Location")
                                .font(.subheadline.bold())
                            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                            Map(initialPosition: .region(MKCoordinateRegion(
                                center: coordinate,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            )), interactionModes: []) {
                                Marker(locationName ?? "Location", coordinate: coordinate)
                            }
                            .frame(height: 200)
                            .cornerRadius(10)
                            .onTapGesture { showMapChoice = true }
                            .confirmationDialog("Open in Maps", isPresented: $showMapChoice) {
                                Button("Apple Maps") {
                                    let placemark = MKPlacemark(coordinate: coordinate)
                                    let mapItem = MKMapItem(placemark: placemark)
                                    mapItem.name = locationName
                                    mapItem.openInMaps()
                                }
                                Button("Google Maps") {
                                    let urlString = "comgooglemaps://?q=\(latitude),\(longitude)"
                                    if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
                                        UIApplication.shared.open(url)
                                    } else if let webURL = URL(string: "https://maps.google.com/?q=\(latitude),\(longitude)") {
                                        UIApplication.shared.open(webURL)
                                    }
                                }
                                Button("Cancel", role: .cancel) {}
                            }

                            Text(String(format: "%.6f, %.6f", latitude, longitude))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle(locationName ?? "Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareSummary, preview: SharePreview(locationName ?? "Location", image: Image(systemName: "mappin.circle"))) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .task {
            await loadInsights()
            await loadCheckInCount()
        }
        .fullScreenCover(item: Binding(
            get: { fullScreenPhotoURL.map { IdentifiedURL(url: $0) } },
            set: { fullScreenPhotoURL = $0?.url }
        )) { wrapper in
            FullScreenImageView(url: wrapper.url)
        }
    }

    private func loadCheckInCount() async {
        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(apiBaseURL)/api/checkins?locationId=\(locationId)") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder.apiDecoder.decode(APIResponse<CheckInCountResponse>.self, from: data) else { return }
        checkInCount = decoded.data.count
    }

    private func addCheckIn() async {
        isCheckingIn = true
        defer { isCheckingIn = false }

        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(apiBaseURL)/api/checkins") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(["locationId": locationId])

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder.apiDecoder.decode(APIResponse<CheckInResponse>.self, from: data) else { return }
        checkInCount = decoded.data.count
    }

    private var shareSummary: String {
        var lines: [String] = []
        let name = locationName ?? "Unnamed Location"
        lines.append(name)

        let starRatings = insights.compactMap(\.starRating)
        if !starRatings.isEmpty {
            let avg = Double(starRatings.reduce(0, +)) / Double(starRatings.count)
            let stars = String(repeating: "\u{2605}", count: Int(avg.rounded())) + String(repeating: "\u{2606}", count: 5 - Int(avg.rounded()))
            lines.append("\(stars) \(String(format: "%.1f", avg)) (\(starRatings.count) \(starRatings.count == 1 ? "review" : "reviews"))")
        }

        let allAttributes = insights.flatMap { $0.attributeRatings ?? [] }
        if !allAttributes.isEmpty {
            let grouped = Dictionary(grouping: allAttributes, by: \.attributeName)
            for key in grouped.keys.sorted() {
                let ratings = grouped[key]!
                let good = ratings.filter { $0.rating == "good" }.count
                let bad = ratings.filter { $0.rating == "bad" }.count
                let total = good + bad
                guard total > 0 else { continue }
                let pct = Int(Double(good) / Double(total) * 100)
                lines.append("\(key): \(pct)% positive (\(good) good, \(bad) bad)")
            }
        }

        let comments = insights.compactMap(\.comment).filter { !$0.isEmpty }
        if !comments.isEmpty {
            lines.append("")
            lines.append("Comments:")
            for comment in comments.prefix(5) {
                lines.append("- \(comment)")
            }
        }

        lines.append("")
        lines.append("Shared from FieldTrip")
        if let url = NotificationCoordinator.deepLinkURL(
            id: locationId,
            name: locationName,
            lat: latitude,
            lng: longitude
        ) {
            lines.append("Open in app: \(url.absoluteString)")
        }
        return lines.joined(separator: "\n")
    }

    private func loadInsights() async {
        isLoading = true
        defer { isLoading = false }

        guard let token = KeychainService.retrieve(for: .authToken) else {
            errorMessage = "Please sign in again."
            return
        }

        guard let url = URL(string: "\(apiBaseURL)/api/insights?locationId=\(locationId)") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as! HTTPURLResponse
            guard http.statusCode == 200 else {
                errorMessage = "Server error (\(http.statusCode))."
                return
            }
            let decoded = try JSONDecoder.apiDecoder.decode(
                APIResponse<LocationInsightsPage>.self, from: data
            )
            insights = decoded.data.insights
        } catch {
            errorMessage = "Could not load entries."
        }
    }
}

// MARK: - Detail Models

private struct LocationInsightsPage: Decodable {
    let insights: [LocationInsight]
}

private struct LocationInsight: Decodable, Identifiable {
    let id: String
    let comment: String?
    let placeType: String?
    let starRating: Int?
    let createdAt: Date
    let attributeRatings: [LocationAttributeRating]?
    let photos: [LocationPhoto]?
    let user: LocationUser?
}

private struct LocationAttributeRating: Decodable {
    let id: String
    let attributeName: String
    let rating: String
}

private struct LocationPhoto: Decodable, Identifiable {
    let id: String
    let url: String
}

private struct LocationUser: Decodable {
    let id: String
    let fullName: String
}

#Preview {
    NavigationStack {
        BrowseInsightsView()
    }
}
