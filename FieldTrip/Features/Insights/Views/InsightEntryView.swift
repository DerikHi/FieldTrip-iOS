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
                if let error = vm.errorMessage, vm.currentStep == .location {
                    ErrorBanner(message: error)
                        .padding(.top)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Name (optional)")
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

                    TextField("Coordinates, map link, or town (e.g. Springfield, IL)", text: $vm.coordinatePasteInput)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        .submitLabel(.search)
                        .onSubmit { vm.parseCoordinatePaste() }

                    if let error = vm.coordinatePasteError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    Button(action: {
                        if let text = UIPasteboard.general.string {
                            vm.coordinatePasteInput = text
                            vm.parseCoordinatePaste()
                        }
                    }) {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)

                    DisclosureGroup("How to get coordinates") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Google Maps", systemImage: "map")
                                    .font(.subheadline.bold())
                                Text("Tap and hold on the map to drop a pin. Tap the coordinates at the top of the screen to copy them.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Label("Apple Maps", systemImage: "map.fill")
                                    .font(.subheadline.bold())
                                Text("Tap and hold on the map to drop a pin. Swipe up on the pin details, then tap the coordinates to copy them.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Label("Share a Link", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.bold())
                                Text("You can also copy a share link from either app and paste it here — the coordinates will be extracted automatically.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.subheadline)
                    .tint(.secondary)
                }

                // Map preview + Location name
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
                    }

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
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await vm.loadCategoriesIfNeeded() }
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
                Text("Rate each attribute as Good, Bad, or N/A.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach($vm.draft.attributeEntries) { $entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.name)
                            .font(.subheadline.bold())

                        HStack(spacing: 8) {
                            ForEach(AttributeRating.allCases, id: \.self) { option in
                                Button(action: { entry.rating = option }) {
                                    Text(option.rawValue)
                                        .font(.subheadline)
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
        case .good: return .green
        case .bad: return .red
        case .na: return .gray
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
    @State private var photoError: String?

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

                PhotosPicker(selection: $selectedItems, maxSelectionCount: 2 - vm.draft.photos.count, matching: .images) {
                    Label("Select Photos", systemImage: "photo.badge.plus")
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

                if let error = vm.errorMessage {
                    ErrorBanner(message: error)
                }

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
                ReviewRow(label: "Facility Type", value: vm.selectedFacilityTypeName)
                ReviewRow(label: "Overall Rating", value: String(repeating: "★", count: vm.draft.starRating) + String(repeating: "☆", count: 5 - vm.draft.starRating))

                let rated = vm.draft.attributeEntries.filter { $0.rating != .na }
                if !rated.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Attributes").font(.caption).foregroundStyle(.secondary)
                        ForEach(rated) { entry in
                            HStack {
                                Text(entry.name)
                                    .font(.subheadline)
                                Spacer()
                                Text(entry.rating.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(entry.rating == .good ? .green : .red)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                }

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
