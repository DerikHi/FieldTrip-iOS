import SwiftUI
import MapKit
import PhotosUI

struct InsightEntryView: View {
    @StateObject private var vm = InsightEntryViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
                    FacilityTypeStepView(vm: vm).tag(InsightEntryViewModel.Step.facilityType)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Success!", isPresented: $vm.isSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text(vm.isOffline ? "Saved offline. Will sync when you're back online." : "Your insight has been shared.")
            }
        }
    }
}

// MARK: - Step Views

struct LocationStepView: View {
    @ObservedObject var vm: InsightEntryViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Where is this location?")
                    .font(.title2.bold())
                    .padding(.top)

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

                // Paste coordinates
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paste coordinates or map link")
                        .font(.subheadline.bold())

                    TextField("e.g. 46.9319, -118.3878 or Google Maps URL", text: $vm.coordinatePasteInput)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)

                    if let error = vm.coordinatePasteError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    Button("Parse") { vm.parseCoordinatePaste() }
                        .frame(minHeight: 44)
                        .buttonStyle(.bordered)
                }

                // Map preview
                if let coord = vm.draft.coordinate {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirmed Location")
                            .font(.subheadline.bold())

                        Map(coordinateRegion: .constant(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                        )), annotationItems: [coord.asAnnotation]) { pin in
                            MapMarker(coordinate: pin.coordinate, tint: .red)
                        }
                        .frame(height: 180)
                        .cornerRadius(12)

                        Text(String(format: "%.6f, %.6f", coord.latitude, coord.longitude))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                // Location name (optional)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location name (optional)")
                        .font(.subheadline.bold())

                    TextField("e.g. Flying J Travel Center - Exit 221", text: $vm.draft.locationName)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

struct FacilityTypeStepView: View {
    @ObservedObject var vm: InsightEntryViewModel

    private var facilities: [FacilityType] { vm.facilityTypes.filter { $0.category == "facility" } }
    private var naturalSpaces: [FacilityType] { vm.facilityTypes.filter { $0.category == "natural_space" } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("What type of location is this?")
                    .font(.title2.bold())
                    .padding(.top)

                if !facilities.isEmpty {
                    TypeSection(title: "Facilities", types: facilities, selectedId: $vm.draft.facilityTypeId)
                }

                if !naturalSpaces.isEmpty {
                    TypeSection(title: "Natural Spaces", types: naturalSpaces, selectedId: $vm.draft.facilityTypeId)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            if vm.draft.facilityTypeId.isEmpty && !vm.facilityTypes.isEmpty {
                vm.draft.facilityTypeId = vm.facilityTypes.first?.id ?? ""
            }
        }
    }
}

private struct TypeSection: View {
    let title: String
    let types: [FacilityType]
    @Binding var selectedId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)

            ForEach(types) { type in
                Button(action: { selectedId = type.id }) {
                    HStack(spacing: 16) {
                        if let icon = type.icon {
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 28)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(type.name).font(.subheadline.bold())
                            if let desc = type.description {
                                Text(desc).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selectedId == type.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding()
                    .background(selectedId == type.id ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selectedId == type.id ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(type.name)
                .frame(minHeight: 44)
            }
        }
    }
}

struct RatingsStepView: View {
    @ObservedObject var vm: InsightEntryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Rate the features")
                    .font(.title2.bold())
                    .padding(.top)
                Text("Slide to rate 1–5. Skip any that don't apply.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach($vm.draft.featureRatings) { $rating in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if let icon = rating.category.icon {
                                Image(systemName: icon)
                            }
                            Text(rating.category.name).font(.subheadline.bold())
                            Spacer()
                            Text("\(rating.rating)/5")
                                .font(.caption.bold())
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(rating.rating) },
                            set: { rating.rating = Int($0) }
                        ), in: 1...5, step: 1)
                        .accessibilityLabel("\(rating.category.name) rating")
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear { if vm.draft.featureRatings.isEmpty { vm.initializeRatings() } }
    }
}

struct CommentStepView: View {
    @ObservedObject var vm: InsightEntryViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Add a comment")
                    .font(.title2.bold())
                    .padding(.top)

                VStack(alignment: .leading, spacing: 8) {
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

                    if vm.draft.comment.count > 125 {
                        Text("Comment must be 125 characters or fewer.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Toggle("Share publicly with other users", isOn: $vm.draft.isPublic)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Add photos")
                    .font(.title2.bold())
                    .padding(.top)
                Text("Optional. Up to 5 photos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                PhotosPicker(selection: $selectedItems, maxSelectionCount: 5 - vm.draft.photos.count, matching: .images) {
                    Label("Select Photos", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .disabled(vm.draft.photos.count >= 5)
                .onChange(of: selectedItems) { _, items in
                    Task {
                        for item in items {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let image = UIImage(data: data),
                               vm.draft.photos.count < 5 {
                                vm.draft.photos.append(UIImageWrapper(image: image))
                            }
                        }
                        selectedItems = []
                    }
                }

                if !vm.draft.photos.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                        ForEach(vm.draft.photos.indices, id: \.self) { i in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: vm.draft.photos[i].image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
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

                if let error = vm.errorMessage {
                    ErrorBanner(message: error)
                }

                ReviewRow(label: "Location", value: vm.draft.locationName.isEmpty ? "Unnamed" : vm.draft.locationName)
                if let lat = vm.draft.latitude, let lng = vm.draft.longitude {
                    ReviewRow(label: "Coordinates", value: String(format: "%.6f, %.6f", lat, lng))
                }
                ReviewRow(label: "Facility Type", value: vm.facilityTypes.first { $0.id == vm.draft.facilityTypeId }?.name ?? "—")
                ReviewRow(label: "Ratings", value: "\(vm.draft.featureRatings.count) categories rated")
                if !vm.draft.comment.isEmpty {
                    ReviewRow(label: "Comment", value: vm.draft.comment)
                }
                ReviewRow(label: "Photos", value: "\(vm.draft.photos.count) photo(s)")
                ReviewRow(label: "Visibility", value: vm.draft.isPublic ? "Public" : "Private")
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
