import SwiftUI
import MapKit

struct MyInsightsView: View {
    let user: AuthUser
    @State private var entries: [MyEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFacilityType: String?
    @State private var showFilterSheet = false

    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"

    private var facilityTypeNames: [String] {
        Array(Set(entries.map { $0.location.facilityType.name })).sorted()
    }

    private var filteredEntries: [MyEntry] {
        guard let selected = selectedFacilityType else { return entries }
        return entries.filter { $0.location.facilityType.name == selected }
    }

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
                    "No Entries Yet",
                    systemImage: "tray",
                    description: Text("Your reviews will appear here after you add your first entry.")
                )
            } else {
                VStack(spacing: 0) {
                    if facilityTypeNames.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Type")
                                .font(.subheadline.bold())
                            Button {
                                showFilterSheet = true
                            } label: {
                                HStack {
                                    Text(selectedFacilityType ?? "All")
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                        Divider()
                    }

                    List {
                        ForEach(filteredEntries) { entry in
                            NavigationLink(destination: MyEntryDetailView(entry: entry)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(entry.locationName ?? "Unnamed Location")
                                            .font(.headline)
                                        Spacer()
                                        Text(entry.location.facilityType.name)
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.1))
                                            .cornerRadius(4)
                                    }

                                    HStack(spacing: 12) {
                                        if let star = entry.starRating {
                                            HStack(spacing: 4) {
                                                Image(systemName: "star.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.yellow)
                                                Text("\(star)")
                                                    .font(.subheadline.weight(.medium))
                                                Text("rating")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        Text(entry.createdAt, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if let comment = entry.comment, !comment.isEmpty {
                                        Text(comment)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    let rated = (entry.attributeRatings ?? []).prefix(4)
                                    if !rated.isEmpty {
                                        VStack(alignment: .leading, spacing: 2) {
                                            ForEach(rated, id: \.id) { attr in
                                                HStack(spacing: 6) {
                                                    Text(attr.attributeName)
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(.secondary)
                                                    Text(AttributeRatingDisplay.displayLabel(for: attr.rating))
                                                        .font(.system(size: 11, weight: .semibold))
                                                        .foregroundStyle(AttributeRatingDisplay.color(for: attr.rating))
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
        }
        .navigationTitle("My Entries")
        .withHomeToolbar()
        .task { await loadEntries() }
        .sheet(isPresented: $showFilterSheet) {
            NavigationStack {
                List {
                    Button {
                        selectedFacilityType = nil
                        showFilterSheet = false
                    } label: {
                        HStack {
                            Text("All").foregroundStyle(.primary)
                            Spacer()
                            if selectedFacilityType == nil {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    ForEach(facilityTypeNames, id: \.self) { name in
                        Button {
                            selectedFacilityType = name
                            showFilterSheet = false
                        } label: {
                            HStack {
                                Text(name).foregroundStyle(.primary)
                                Spacer()
                                if selectedFacilityType == name {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Filter by Type")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showFilterSheet = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func loadEntries() async {
        isLoading = true
        defer { isLoading = false }

        guard let token = KeychainService.retrieve(for: .authToken) else {
            errorMessage = "Please sign in again."
            return
        }

        guard let url = URL(string: "\(apiBaseURL)/api/insights") else {
            errorMessage = "Invalid server URL."
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
                APIResponse<MyEntriesPage>.self, from: data
            )
            entries = decoded.data.insights
        } catch {
            errorMessage = "Could not load your entries."
        }
    }
}

// MARK: - Entry Detail View

struct MyEntryDetailView: View {
    let entry: MyEntry
    @Environment(\.dismiss) private var dismiss
    @State private var checkInCount = 0
    @State private var isCheckingIn = false
    @State private var showMapChoice = false
    @State private var fullScreenPhotoURL: URL?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var showEditReview = false

    private let apiBaseURL = ProcessInfo.processInfo.environment["API_URL"] ?? "https://backend-nine-kappa-58.vercel.app"

    var body: some View {
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

                // Edit Review button
                Button {
                    showEditReview = true
                } label: {
                    Label("Edit Review", systemImage: "pencil")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                // Star rating
                if let star = entry.starRating {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rating")
                            .font(.subheadline.bold())
                        HStack(spacing: 4) {
                            ForEach(1...5, id: \.self) { s in
                                Image(systemName: s <= star ? "star.fill" : "star")
                                    .foregroundStyle(s <= star ? .yellow : .gray.opacity(0.4))
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }

                // Attributes
                let rated = (entry.attributeRatings ?? []).filter { $0.rating != "na" }
                if !rated.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Attributes")
                            .font(.subheadline.bold())
                        ForEach(rated, id: \.id) { attr in
                            HStack {
                                Text(attr.attributeName)
                                    .font(.subheadline)
                                Spacer()
                                Text(AttributeRatingDisplay.displayLabel(for: attr.rating))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AttributeRatingDisplay.color(for: attr.rating))
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }

                // Comment
                if let comment = entry.comment, !comment.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Comment")
                            .font(.subheadline.bold())
                        Text(comment)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }

                // Photos
                let photos = entry.photos ?? []
                if !photos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Photos")
                            .font(.subheadline.bold())
                        ForEach(photos, id: \.id) { photo in
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

                // Map
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location")
                        .font(.subheadline.bold())
                    let coordinate = CLLocationCoordinate2D(
                        latitude: entry.location.latitude,
                        longitude: entry.location.longitude
                    )
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )), interactionModes: []) {
                        Marker(entry.locationName ?? "Location", coordinate: coordinate)
                    }
                    .frame(height: 200)
                    .cornerRadius(10)
                    .onTapGesture { showMapChoice = true }
                    .confirmationDialog("Open in Maps", isPresented: $showMapChoice) {
                        Button("Apple Maps") {
                            let placemark = MKPlacemark(coordinate: coordinate)
                            let mapItem = MKMapItem(placemark: placemark)
                            mapItem.name = entry.locationName
                            mapItem.openInMaps()
                        }
                        Button("Google Maps") {
                            let urlString = "comgooglemaps://?q=\(entry.location.latitude),\(entry.location.longitude)"
                            if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
                                UIApplication.shared.open(url)
                            } else if let webURL = URL(string: "https://maps.google.com/?q=\(entry.location.latitude),\(entry.location.longitude)") {
                                UIApplication.shared.open(webURL)
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    }

                    Text(String(format: "%.6f, %.6f", entry.location.latitude, entry.location.longitude))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .navigationTitle(entry.locationName ?? "Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .disabled(isDeleting)
                .accessibilityLabel("Delete Entry")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareSummary, preview: SharePreview(entry.locationName ?? "Entry", image: Image(systemName: "mappin.circle"))) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await deleteEntry() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your rating for this location. This cannot be undone.")
        }
        .alert("Delete Failed", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .task { await loadCheckInCount() }
        .fullScreenCover(item: Binding(
            get: { fullScreenPhotoURL.map { IdentifiedURL(url: $0) } },
            set: { fullScreenPhotoURL = $0?.url }
        )) { wrapper in
            FullScreenImageView(url: wrapper.url)
        }
        .sheet(isPresented: $showEditReview) {
            EditEntryView(entry: entry) {
                dismiss()
            }
        }
    }

    private func deleteEntry() async {
        isDeleting = true
        defer { isDeleting = false }

        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(apiBaseURL)/api/insights/\(entry.id)") else {
            deleteError = "Please sign in again."
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                dismiss()
            } else {
                deleteError = "Could not delete this entry. Please try again later."
            }
        } catch {
            deleteError = "Could not delete this entry. Please try again later."
        }
    }

    private func loadCheckInCount() async {
        guard let token = KeychainService.retrieve(for: .authToken),
              let url = URL(string: "\(apiBaseURL)/api/checkins?locationId=\(entry.locationId)") else { return }
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
        request.httpBody = try? JSONEncoder().encode(["locationId": entry.locationId])

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = try? JSONDecoder.apiDecoder.decode(APIResponse<CheckInResponse>.self, from: data) else { return }
        checkInCount = decoded.data.count
    }

    private var shareSummary: String {
        var lines: [String] = []
        lines.append(entry.locationName ?? "Unnamed Location")
        lines.append(entry.location.facilityType.name)
        if let star = entry.starRating {
            let stars = String(repeating: "\u{2605}", count: star) + String(repeating: "\u{2606}", count: 5 - star)
            lines.append(stars)
        }
        if let comment = entry.comment, !comment.isEmpty {
            lines.append(comment)
        }
        lines.append("")
        lines.append("Shared from FieldTrip")
        if let url = NotificationCoordinator.deepLinkURL(
            id: entry.locationId,
            name: entry.locationName,
            lat: entry.location.latitude,
            lng: entry.location.longitude
        ) {
            lines.append("Open in app: \(url.absoluteString)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Models

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct MyEntriesPage: Decodable {
    let insights: [MyEntry]
}

struct MyEntry: Decodable, Identifiable {
    let id: String
    let comment: String?
    let placeType: String?
    let starRating: Int?
    let createdAt: Date
    let location: MyEntryLocation
    let attributeRatings: [MyEntryAttribute]?
    let photos: [MyEntryPhoto]?

    var locationId: String { location.id }
    var locationName: String? { location.name }
}

struct MyEntryLocation: Decodable {
    let id: String
    let name: String?
    let latitude: Double
    let longitude: Double
    let facilityType: MyEntryFacilityType
}

struct MyEntryFacilityType: Decodable {
    let name: String
}

struct MyEntryAttribute: Decodable, Identifiable {
    let id: String
    let attributeName: String
    let rating: String
}

struct MyEntryPhoto: Decodable, Identifiable {
    let id: String
    let url: String
}

struct CheckInCountResponse: Decodable {
    let locationId: String
    let count: Int
}

struct CheckInResponse: Decodable {
    let checkIn: CheckInRecord
    let count: Int
}

struct CheckInRecord: Decodable {
    let id: String
}

#Preview {
    NavigationStack {
        MyInsightsView(user: AuthUser(
            id: "preview",
            email: "jane@example.com",
            fullName: "Jane Smith",
            role: .user,
            organization: nil,
            createdAt: Date()
        ))
    }
}
