import SwiftUI
import MapKit
import PhotosUI

struct InsightEntryView: View {
    @StateObject private var vm = InsightEntryViewModel()
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            StepIndicatorView(currentStep: vm.currentStep.rawValue, totalSteps: InsightEntryViewModel.Step.allCases.count)
                .padding(.horizontal)
                .padding(.vertical, 12)

            Divider()

            // Offline banner
            if vm.isOffline {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                    Text("Offline — insight will sync when connected")
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.orange)
            }

            // Step content
            TabView(selection: $vm.currentStep) {
                LocationStepView(vm: vm).tag(InsightEntryViewModel.Step.location)
                RatingsStepView(vm: vm).tag(InsightEntryViewModel.Step.ratings)
                CommentStepView(vm: vm).tag(InsightEntryViewModel.Step.comment)
                PhotoStepView(vm: vm).tag(InsightEntryViewModel.Step.photos)
                ReviewStepView(vm: vm).tag(InsightEntryViewModel.Step.review)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: vm.currentStep)

            Divider()

            // Navigation buttons
            HStack(spacing: 16) {
                if vm.currentStep != .location {
                    Button("Back") { vm.goBack() }
                        .frame(minHeight: 44)
                        .buttonStyle(.bordered)
                }

                Spacer()

                if vm.currentStep == .review {
                    Button(action: { Task { await vm.submit() } }) {
                        Group {
                            if vm.isLoading {
                                ProgressView().progressViewStyle(.circular).tint(.white)
                            } else {
                                Text(vm.isOffline ? "Save Offline" : "Submit")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(minWidth: 120, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isLoading)
                } else {
                    Button("Next") { vm.advance() }
                        .frame(minHeight: 44)
                        .buttonStyle(.borderedProminent)
                        .disabled(!vm.canAdvance)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .navigationTitle(vm.currentStep.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Success!", isPresented: $vm.isSuccess) {
            Button("Done") {
                router.selectedTab = .my
                router.myPath.removeAll()
            }
        } message: {
            Text(vm.isOffline ? "Saved offline. Will sync when you're back online." : "Your insight has been shared.")
        }
    }
}

// MARK: - Step Views

struct LocationStepView: View {
    @ObservedObject var vm: InsightEntryViewModel
    @State private var placeSearchName = ""
    @State private var placeSearchTown = ""
    @State private var placeSearchResults: [PlaceSearchResult] = []
    @State private var isSearchingPlace = false
    @State private var placeSearchPerformed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let error = vm.errorMessage, vm.currentStep == .location {
                    ErrorBanner(message: error)
                        .padding(.top)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.subheadline.bold())

                    TextField("e.g. Flying J Travel Center - Exit 221", text: $vm.draft.locationName)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }
                .padding(.top)

                if !vm.facilityTypes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type")
                            .font(.subheadline.bold())
                        Picker("Select a type", selection: $vm.draft.facilityTypeId) {
                            Text("Select…").tag("")
                            ForEach(vm.facilityTypes) { type in
                                Text(type.name).tag(type.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                }

                // Map preview (appears as soon as a location has been resolved)
                if let coord = vm.draft.coordinate {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirmed Location")
                            .font(.subheadline.bold())

                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                        )), interactionModes: []) {
                            Marker("Location", coordinate: coord)
                        }
                        .frame(height: 180)
                        .cornerRadius(12)

                        Text(String(format: "%.6f, %.6f", coord.latitude, coord.longitude))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        if let town = vm.nearestTown {
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text(town)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // GPS Button
                Button(action: { vm.requestLocation() }) {
                    Label(
                        vm.isGettingLocation ? "Getting location…" : "Use Current GPS Location",
                        systemImage: "location.fill"
                    )
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.isGettingLocation)

                Divider().overlay(Text("or").padding(.horizontal, 8).background(Color(.systemBackground)), alignment: .center)

                // Find a Place
                VStack(alignment: .leading, spacing: 8) {
                    Text("Find a Place")
                        .font(.subheadline.bold())

                    TextField("Place name (e.g. Joe's Diner)", text: $placeSearchName)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .submitLabel(.next)

                    TextField("Town (e.g. Springfield, IL)", text: $placeSearchTown)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .submitLabel(.search)
                        .onSubmit { Task { await runPlaceSearch() } }

                    Button(action: { Task { await runPlaceSearch() } }) {
                        Label(
                            isSearchingPlace ? "Searching…" : "Search",
                            systemImage: "magnifyingglass"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSearchingPlace || placeSearchName.trimmingCharacters(in: .whitespaces).isEmpty)

                    if placeSearchPerformed && placeSearchResults.isEmpty && !isSearchingPlace {
                        Text("No places found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(placeSearchResults) { result in
                        Button(action: { selectPlace(result) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                if !result.address.isEmpty {
                                    Text(result.address)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }

            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await vm.loadCategoriesIfNeeded() }
    }

    private func runPlaceSearch() async {
        let name = placeSearchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let town = placeSearchTown.trimmingCharacters(in: .whitespacesAndNewlines)
        placeSearchName = name
        placeSearchTown = town
        guard !name.isEmpty else { return }
        isSearchingPlace = true
        placeSearchPerformed = true
        defer { isSearchingPlace = false }
        placeSearchResults = await PlaceSearchService.search(name: name, town: town)
    }

    private func selectPlace(_ result: PlaceSearchResult) {
        vm.draft.latitude = result.latitude
        vm.draft.longitude = result.longitude
        if vm.draft.locationName.trimmingCharacters(in: .whitespaces).isEmpty {
            vm.draft.locationName = result.name
        }
        vm.reverseGeocode(latitude: result.latitude, longitude: result.longitude)
        placeSearchResults = []
        placeSearchPerformed = false
    }
}


struct RatingsStepView: View {
    @ObservedObject var vm: InsightEntryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What's good to know?")
                    .font(.title2.bold())
                    .padding(.top)
                Text("Rate each attribute.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach($vm.draft.attributeEntries) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.name)
                            .font(.subheadline.bold())

                        let options = AttributeRating.options(for: entry.name)
                        HStack(spacing: 6) {
                            ForEach(options, id: \.self) { option in
                                Button(action: { entry.rating = option }) {
                                    Text(option.rawValue)
                                        .font(.caption.weight(.medium))
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background(entry.rating == option ? colorFor(option).opacity(0.2) : Color(.secondarySystemBackground))
                                        .foregroundStyle(entry.rating == option ? colorFor(option) : .primary)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(entry.rating == option ? colorFor(option) : Color.clear, lineWidth: 1.5)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground).opacity(0.5))
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private func colorFor(_ rating: AttributeRating) -> Color {
        switch rating {
        case .great: return .green
        case .good: return .mint
        case .meh: return .yellow
        case .nope, .bad: return .red
        case .na: return .gray
        case .yes: return .green
        case .no: return .red
        }
    }
}

struct CommentStepView: View {
    @ObservedObject var vm: InsightEntryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Overall Rating & Comment")
                    .font(.title2.bold())
                    .padding(.top)

                if let error = vm.errorMessage, vm.currentStep == .comment {
                    ErrorBanner(message: error)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Overall star rating")
                        .font(.subheadline.bold())

                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { star in
                            Button(action: { vm.draft.starRating = star }) {
                                Image(systemName: star <= vm.draft.starRating ? "star.fill" : "star")
                                    .font(.title)
                                    .foregroundStyle(star <= vm.draft.starRating ? .yellow : .gray.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Comment (optional)")
                        .font(.subheadline.bold())

                    TextEditor(text: $vm.draft.comment)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(vm.draft.comment.count > 125 ? Color.red : Color.clear, lineWidth: 1.5)
                        )

                    HStack {
                        Spacer()
                        Text("\(vm.draft.comment.count)/125")
                            .font(.caption)
                            .foregroundStyle(vm.draft.comment.count > 125 ? .red : .secondary)
                    }
                }

            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct PhotoStepView: View {
    @ObservedObject var vm: InsightEntryViewModel
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var photoError: String?
    @State private var showCamera = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Add photos")
                    .font(.title2.bold())
                    .padding(.top)
                Text("Optional. Up to 2 photos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let error = photoError {
                    ErrorBanner(message: error)
                }

                HStack(spacing: 12) {
                    PhotosPicker(selection: $selectedItems, maxSelectionCount: 2 - vm.draft.photos.count, matching: .images) {
                        Label("Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.draft.photos.count >= 2)
                    .onChange(of: selectedItems) { _, items in
                        Task {
                            photoError = nil
                            for item in items {
                                if let data = try? await item.loadTransferable(type: Data.self),
                                   let image = UIImage(data: data),
                                   vm.draft.photos.count < 2 {
                                    if let rejection = await vm.addPhotoIfAppropriate(image) {
                                        photoError = rejection
                                    }
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
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(vm.draft.photos.count >= 2)
                    }
                }
                .sheet(isPresented: $showCamera) {
                    CameraPicker { image in
                        Task {
                            if let rejection = await vm.addPhotoIfAppropriate(image) {
                                photoError = rejection
                            }
                        }
                    }
                    .ignoresSafeArea()
                }

                if !vm.draft.photos.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(vm.draft.photos.indices, id: \.self) { i in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: vm.draft.photos[i].image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 140, height: 140)
                                    .clipped()
                                    .cornerRadius(8)

                                Button(action: { vm.draft.photos.remove(at: i) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black)
                                        .font(.title3)
                                }
                                .padding(4)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

struct ReviewStepView: View {
    @ObservedObject var vm: InsightEntryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Review & Submit")
                    .font(.title2.bold())
                    .padding(.top)

                Toggle("Share publicly with other users", isOn: $vm.draft.isPublic)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)

                if let error = vm.errorMessage {
                    ErrorBanner(message: error)
                }

                // Location name (editable)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Location").font(.caption).foregroundStyle(.secondary)
                    TextField("Location name", text: $vm.draft.locationName)
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)

                if let lat = vm.draft.latitude, let lng = vm.draft.longitude {
                    ReviewRow(label: "Coordinates", value: String(format: "%.6f, %.6f", lat, lng))
                }

                // Facility Type (editable picker)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Facility Type").font(.caption).foregroundStyle(.secondary)
                    if !vm.facilityTypes.isEmpty {
                        Picker("Type", selection: $vm.draft.facilityTypeId) {
                            Text("Select…").tag("")
                            ForEach(vm.facilityTypes) { type in
                                Text(type.name).tag(type.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    } else {
                        Text(vm.selectedFacilityTypeName).font(.subheadline)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)

                // Overall star rating (editable)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Overall Rating").font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(1...5, id: \.self) { star in
                            Button(action: { vm.draft.starRating = star }) {
                                Image(systemName: star <= vm.draft.starRating ? "star.fill" : "star")
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

                // Attribute ratings (editable)
                if !vm.draft.attributeEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Attributes").font(.caption).foregroundStyle(.secondary)
                        ForEach($vm.draft.attributeEntries) { $entry in
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

                // Comment (editable)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Comment").font(.caption).foregroundStyle(.secondary)
                    TextField("Add a comment (optional)", text: $vm.draft.comment, axis: .vertical)
                        .lineLimit(2...6)
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)

                ReviewRow(label: "Photos", value: "\(vm.draft.photos.count) photo(s)")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

private struct ReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }
}

// MARK: - Step Indicator

struct StepIndicatorView: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= currentStep ? Color.accentColor : Color(.systemGray4))
                    .frame(height: 4)
                    .animation(.easeInOut, value: currentStep)
            }
        }
    }
}

// MARK: - Coordinate annotation helper

extension CLLocationCoordinate2D {
    struct Annotation: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
    }

    var asAnnotation: Annotation { Annotation(coordinate: self) }
}
