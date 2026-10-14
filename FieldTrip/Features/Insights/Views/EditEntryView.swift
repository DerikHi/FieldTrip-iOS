import SwiftUI
import PhotosUI
import CoreLocation

/// Lets a user edit every part of one of their existing entries: location, type,
/// ratings, comment, visibility, and photos. Nothing is sent until Save.
struct EditEntryView: View {
    let entry: MyEntry
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    // Location
    @State private var locationName: String
    @State private var town: String
    @State private var latitude: Double
    @State private var longitude: Double
    @State private var facilityTypeName: String
    @State private var coordinatePasteInput = ""
    @State private var coordinateError: String?
    @State private var isGettingLocation = false
    @StateObject private var locationHelper = BrowseLocationHelper()

    // Ratings, comment, visibility
    @State private var starRating: Int
    @State private var attributeEntries: [AttributeEntry]
    @State private var comment: String
    @State private var isPublic: Bool

    // Photos: removals and additions are applied on Save
    @State private var keptPhotos: [MyEntryPhoto]
    @State private var removedPhotoIds: [String] = []
    @State private var newPhotos: [UIImage] = []
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var photoError: String?

    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let maxPhotos = 2
    private static let commentLimit = 250

    init(entry: MyEntry, onSaved: @escaping () -> Void) {
        self.entry = entry
        self.onSaved = onSaved
        _locationName = State(initialValue: entry.location.name ?? "")
        _town = State(initialValue: entry.location.town ?? "")
        _latitude = State(initialValue: entry.location.latitude)
        _longitude = State(initialValue: entry.location.longitude)
        _facilityTypeName = State(initialValue: entry.location.facilityType.name)
        _starRating = State(initialValue: entry.starRating ?? 3)
        _comment = State(initialValue: entry.comment ?? "")
        _isPublic = State(initialValue: entry.isPublic ?? true)
        _keptPhotos = State(initialValue: entry.photos ?? [])

        // Show every attribute for this type, pre-filled with what was saved
        let saved = (entry.attributeRatings ?? []).map { attr -> AttributeEntry in
            var e = AttributeEntry(name: attr.attributeName)
            e.rating = AttributeRating.allCases.first { $0.apiValue == attr.rating.lowercased() } ?? .na
            return e
        }
        _attributeEntries = State(initialValue: EntryAttributeCatalog.entries(
            forFacilityTypeName: entry.location.facilityType.name,
            keeping: saved
        ))
    }

    private var photoCount: Int { keptPhotos.count + newPhotos.count }
    private var isCommentTooLong: Bool { comment.count > Self.commentLimit }

    /// Bundled types, plus the entry's current type if it isn't one of them
    private var facilityTypeNames: [String] {
        let names = InsightEntryViewModel.fallbackFacilityTypes.map(\.name)
        return names.contains(entry.location.facilityType.name) ? names : [entry.location.facilityType.name] + names
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = errorMessage {
                        ErrorBanner(message: error)
                    }

                    locationSection

                    Toggle("Share publicly with other users", isOn: $isPublic)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                    starRatingSection

                    if !attributeEntries.isEmpty {
                        attributesSection
                    }

                    commentSection

                    photosSection
                }
                .padding()
            }
            .navigationTitle("Edit Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || isCommentTooLong)
                }
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Saving…").padding().background(.thickMaterial).cornerRadius(12)
                }
            }
            .onChange(of: facilityTypeName) { _, newName in
                // A new type can add or remove attributes (e.g. Air/Water); keep chosen ratings
                attributeEntries = EntryAttributeCatalog.entries(forFacilityTypeName: newName, keeping: attributeEntries)
            }
            .onChange(of: locationHelper.latitude) { _, lat in
                if let lat, let lng = locationHelper.longitude, isGettingLocation {
                    isGettingLocation = false
                    updateCoordinates(latitude: lat, longitude: lng)
                }
            }
            .onChange(of: locationHelper.authStatus) { _, status in
                if status == .authorizedWhenInUse && isGettingLocation {
                    locationHelper.requestLocation()
                }
            }
        }
    }

    // MARK: - Sections

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location").font(.caption).foregroundStyle(.secondary)

            TextField("Location name", text: $locationName)
                .font(.subheadline)
                .padding(10)
                .background(Color(.systemBackground))
                .cornerRadius(8)

            TextField("Town, e.g. Springfield, IL", text: $town)
                .font(.subheadline)
                .padding(10)
                .background(Color(.systemBackground))
                .cornerRadius(8)

            HStack {
                Text("Type").font(.subheadline)
                Spacer()
                Picker("Type", selection: $facilityTypeName) {
                    ForEach(facilityTypeNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
            }

            Text(String(format: "📍 %.5f, %.5f", latitude, longitude))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button(action: { requestLocation() }) {
                Label(
                    isGettingLocation ? "Getting location…" : "Use Current GPS Location",
                    systemImage: "location.fill"
                )
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .disabled(isGettingLocation)

            HStack(spacing: 8) {
                TextField("Or paste coordinates / a maps link", text: $coordinatePasteInput)
                    .font(.subheadline)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { applyPastedCoordinates() }
                    .padding(10)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                Button("Use") { applyPastedCoordinates() }
                    .buttonStyle(.bordered)
                    .disabled(coordinatePasteInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let coordinateError {
                Text(coordinateError).font(.caption).foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private var starRatingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Rating").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { star in
                    Button(action: { starRating = star }) {
                        Image(systemName: star <= starRating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private var attributesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attributes").font(.caption).foregroundStyle(.secondary)
            ForEach($attributeEntries) { $entry in
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name).font(.subheadline.weight(.medium))
                    let options = AttributeRating.options(for: entry.name)
                    HStack(spacing: 6) {
                        ForEach(options, id: \.self) { option in
                            Button(action: { entry.rating = option }) {
                                Text(option.rawValue)
                                    .font(.caption.weight(.medium))
                                    .frame(maxWidth: .infinity, minHeight: 30)
                                    .background(entry.rating == option ? AttributeRatingDisplay.color(for: option.apiValue).opacity(0.2) : Color(.systemBackground))
                                    .foregroundStyle(entry.rating == option ? AttributeRatingDisplay.color(for: option.apiValue) : .primary)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(entry.rating == option ? AttributeRatingDisplay.color(for: option.apiValue) : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Comment").font(.caption).foregroundStyle(.secondary)
            TextField("Comment (optional)", text: $comment, axis: .vertical)
                .lineLimit(2...6)
                .font(.subheadline)
            HStack {
                Spacer()
                Text("\(comment.count)/\(Self.commentLimit)")
                    .font(.caption)
                    .foregroundStyle(isCommentTooLong ? .red : .secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos (up to \(Self.maxPhotos))").font(.caption).foregroundStyle(.secondary)

            if let photoError {
                Text(photoError).font(.caption).foregroundStyle(.red)
            }

            if photoCount > 0 {
                HStack(spacing: 12) {
                    ForEach(keptPhotos) { photo in
                        photoThumbnail {
                            AsyncImage(url: URL(string: photo.url)) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color(.systemBackground).overlay(ProgressView())
                            }
                        } onRemove: {
                            keptPhotos.removeAll { $0.id == photo.id }
                            removedPhotoIds.append(photo.id)
                        }
                    }
                    ForEach(newPhotos.indices, id: \.self) { i in
                        photoThumbnail {
                            Image(uiImage: newPhotos[i]).resizable().scaledToFill()
                        } onRemove: {
                            newPhotos.remove(at: i)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: max(Self.maxPhotos - photoCount, 1),
                    matching: .images
                ) {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .disabled(photoCount >= Self.maxPhotos)
                .onChange(of: selectedItems) { _, items in
                    Task {
                        photoError = nil
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                await addPhotoIfAppropriate(image)
                            }
                        }
                        selectedItems = []
                    }
                }

                if CameraPicker.isAvailable {
                    Button {
                        photoError = nil
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.bordered)
                    .disabled(photoCount >= Self.maxPhotos)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    Task { await addPhotoIfAppropriate(image) }
                }
                .ignoresSafeArea()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    private func photoThumbnail<Content: View>(
        @ViewBuilder content: () -> Content,
        onRemove: @escaping () -> Void
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            content()
                .frame(width: 120, height: 120)
                .clipped()
                .cornerRadius(8)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .black)
                    .font(.title3)
            }
            .padding(4)
            .accessibilityLabel("Remove photo")
        }
    }

    // MARK: - Location helpers

    private func requestLocation() {
        coordinateError = nil
        isGettingLocation = true
        switch locationHelper.authStatus {
        case .notDetermined:
            locationHelper.requestAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationHelper.requestLocation()
        case .denied, .restricted:
            coordinateError = "Location access denied. Enable it in Settings or paste coordinates."
            isGettingLocation = false
        @unknown default:
            isGettingLocation = false
        }
    }

    private func applyPastedCoordinates() {
        coordinateError = nil
        guard let coords = ValidationService.parseCoordinates(from: coordinatePasteInput) else {
            coordinateError = "Couldn't read those coordinates. Try \"41.8781, -87.6298\" or a maps link."
            return
        }
        coordinatePasteInput = ""
        updateCoordinates(latitude: coords.lat, longitude: coords.lng)
    }

    /// Moves the entry and refreshes the town to match the new spot
    private func updateCoordinates(latitude lat: Double, longitude lng: Double) {
        latitude = lat
        longitude = lng
        Task {
            let geocoder = CLGeocoder()
            guard let placemark = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lng)).first else { return }
            let locality = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
            if let locality, let state = placemark.administrativeArea, state != locality {
                town = "\(locality), \(state)"
            } else if let locality {
                town = locality
            }
        }
    }

    // MARK: - Photos

    private func addPhotoIfAppropriate(_ image: UIImage) async {
        let result = await ContentModerationService.checkImage(image)
        guard result.isClean else {
            photoError = result.message
            return
        }
        if photoCount < Self.maxPhotos {
            newPhotos.append(image)
        }
    }

    // MARK: - Save

    private func save() async {
        guard !isCommentTooLong else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let attrPayload = attributeEntries
            .filter { $0.rating != .na }
            .map { ["attributeName": $0.name, "rating": $0.rating.apiValue] }

        var body: [String: Any] = [
            "comment": comment,
            "isPublic": isPublic,
            "starRating": starRating,
            "attributeRatings": attrPayload,
        ]

        // Only send location fields that changed
        let trimmedName = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName != (entry.location.name ?? "") {
            body["locationName"] = trimmedName
        }
        let trimmedTown = town.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTown != (entry.location.town ?? "") {
            body["town"] = trimmedTown
        }
        if latitude != entry.location.latitude || longitude != entry.location.longitude {
            body["latitude"] = latitude
            body["longitude"] = longitude
        }
        if facilityTypeName != entry.location.facilityType.name {
            body["facilityTypeName"] = facilityTypeName
            body["placeType"] = EntryAttributeCatalog.placeType(forFacilityTypeName: facilityTypeName)
        }

        do {
            // Save the entry first so a rejected edit doesn't leave photos half-changed
            try await APIClient.shared.send("PATCH", "/api/insights/\(entry.id)", json: body)

            // Removals before additions so the 2-photo limit has room. Each finished
            // step is cleared, so tapping Save again after a failure only retries what's left.
            while let photoId = removedPhotoIds.first {
                try await APIClient.shared.send("DELETE", "/api/insights/\(entry.id)/photos/\(photoId)")
                removedPhotoIds.removeFirst()
            }
            while let image = newPhotos.first {
                try await InsightPhotoUploader.upload(image, index: keptPhotos.count, insightId: entry.id)
                newPhotos.removeFirst()
            }

            dismiss()
            onSaved()
        } catch APIError.http(status: 409, _) {
            errorMessage = "This location is shared with other reviews, so its name, town, type, and position can't be changed."
        } catch {
            errorMessage = "Could not save all of your changes. Please try again."
        }
    }
}
