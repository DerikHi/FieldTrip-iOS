import SwiftUI
import MapKit
import CoreLocation

/// Full-screen map of every location that has been reviewed, nationwide.
///
/// Because the map has to encompass the whole country, it opens zoomed out to
/// fit all pins and relies on MapKit's native pinch-to-zoom and drag gestures
/// so the user can zoom in on a single spot. Tapping a pin opens that
/// location's reviews (merged across any duplicate records that share the same
/// name and town).
struct LocationsMapView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var locations: [MapLocation] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: MapLocation?

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $position) {
                    ForEach(locations) { location in
                        Annotation(
                            location.locationName ?? "Location",
                            coordinate: location.coordinate
                        ) {
                            Button {
                                selected = location
                            } label: {
                                LocationPin(count: location.insightCount)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }

                if isLoading {
                    ProgressView()
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't load the map", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                        .background(.ultraThinMaterial)
                } else if locations.isEmpty {
                    ContentUnavailableView("No locations yet", systemImage: "mappin.slash")
                        .background(.ultraThinMaterial)
                }

                if !isLoading && errorMessage == nil && !locations.isEmpty {
                    VStack {
                        Spacer()
                        Text("Pinch to zoom · tap a location to see its reviews")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 16)
                    }
                }
            }
            .navigationTitle("All Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $selected) { location in
                LocationDetailView(
                    locationId: location.locationId,
                    locationName: location.locationName,
                    latitude: location.latitude,
                    longitude: location.longitude,
                    additionalLocationIds: location.locationIds
                )
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let decoded = try await APIClient.shared.get(
                "/api/locations/map",
                decode: APIResponse<MapLocationsResult>.self
            )
            locations = decoded.data.results
        } catch {
            errorMessage = "An error has occurred, please try again."
        }
    }
}

/// A single tappable dot on the map. Shows the number of reviews so busier
/// spots read as larger at a glance.
private struct LocationPin: View {
    let count: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 28, height: 28)
                .shadow(radius: 1)
            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "mappin")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .overlay(Circle().stroke(.white, lineWidth: 2).frame(width: 28, height: 28))
    }
}

// MARK: - Models

struct MapLocationsResult: Decodable {
    let results: [MapLocation]
}

struct MapLocation: Decodable, Identifiable, Hashable {
    let locationId: String
    let locationIds: [String]
    let locationName: String?
    let town: String?
    let latitude: Double
    let longitude: Double
    let facilityTypeName: String?
    let insightCount: Int
    let avgRating: Double?

    var id: String { locationId }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
