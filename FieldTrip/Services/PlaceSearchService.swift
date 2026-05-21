import Foundation
import MapKit

struct PlaceSearchResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
}

enum PlaceSearchService {

    /// Search for a place (POI) by name within a town or region.
    /// Uses Apple Maps' POI database via MKLocalSearch.
    static func search(name: String, town: String) async -> [PlaceSearchResult] {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTown = town.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return [] }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmedTown.isEmpty ? trimmedName : "\(trimmedName) \(trimmedTown)"
        request.resultTypes = [.pointOfInterest, .address]

        // If a town was provided, bias the search region near it so results are local.
        if !trimmedTown.isEmpty,
           let placemark = try? await CLGeocoder().geocodeAddressString(trimmedTown).first,
           let location = placemark.location {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }

        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            return response.mapItems.prefix(5).map { item in
                PlaceSearchResult(
                    name: item.name ?? trimmedName,
                    address: formatAddress(for: item.placemark),
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
            }
        } catch {
            return []
        }
    }

    private static func formatAddress(for placemark: MKPlacemark) -> String {
        var parts: [String] = []
        if let number = placemark.subThoroughfare, let street = placemark.thoroughfare {
            parts.append("\(number) \(street)")
        } else if let street = placemark.thoroughfare {
            parts.append(street)
        }
        if let city = placemark.locality {
            parts.append(city)
        }
        if let state = placemark.administrativeArea {
            parts.append(state)
        }
        return parts.joined(separator: ", ")
    }
}
