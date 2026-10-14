import Foundation
import CoreLocation
import UIKit
import SwiftUI

struct FacilityType: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: String // "facility" | "natural_space"
    let icon: String?
    let description: String?

    /// The query item that narrows an API request to this type. Types that came
    /// from the app's bundled fallback list carry local `fb-` ids the server
    /// doesn't recognize, so those have to filter by name instead.
    var filterQueryItem: URLQueryItem {
        id.hasPrefix("fb-")
            ? URLQueryItem(name: "facilityTypeName", value: name)
            : URLQueryItem(name: "facilityTypeId", value: id)
    }
}

struct FeatureCategory: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let icon: String?
    let description: String?
}

struct FeatureRatingInput: Identifiable {
    let id: String
    let category: FeatureCategory
    var rating: Int // 1-5
}

enum PlaceType: String, CaseIterable, Identifiable {
    case hotel = "Hotel"
    case restArea = "Rest Area"
    case restaurant = "Restaurant"
    case convenienceStore = "Convenience Store"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hotel: return "building.2"
        case .restArea: return "figure.stand"
        case .restaurant: return "fork.knife"
        case .convenienceStore: return "cart"
        }
    }

    var attributes: [String] {
        switch self {
        case .hotel:
            return ["Clean Room", "Clean Bathroom", "Wear on Furniture and Carpet", "Breakfast", "Ease of Getting a Government Rate", "Price", "Feels Safe", "Pet Friendly", "LGBTQ+ Friendly"]
        case .restArea:
            return ["Clean Bathroom", "Feels Safe", "Food Options", "Can Fill a Water Bottle", "Place to Sit", "Pet Friendly", "LGBTQ+ Friendly"]
        case .restaurant:
            return ["Clean", "Good Food", "Price", "Friendly Staff", "Location", "Pet Friendly", "LGBTQ+ Friendly"]
        case .convenienceStore:
            return ["Clean", "Selection", "Clean Bathroom", "Friendly Staff", "Location", "Pet Friendly", "LGBTQ+ Friendly"]
        }
    }
}

enum AttributeRating: String, CaseIterable {
    case great = "Great"
    case good = "Good"
    case meh = "Meh"
    case nope = "Nope"
    case na = "N/A"
    case yes = "Yes"
    case no = "No"
    case bad = "Bad" // legacy — kept for backward compatibility with previously saved ratings
    case easy = "Easy"
    case okay = "Okay"
    case goodLuck = "Good Luck"
    case free = "Free"
    case paid = "Paid"

    /// Returns the API-friendly value (lowercase, ASCII).
    var apiValue: String {
        switch self {
        case .great: return "great"
        case .good: return "good"
        case .meh: return "meh"
        case .nope: return "nope"
        case .na: return "na"
        case .yes: return "yes"
        case .no: return "no"
        case .bad: return "bad"
        case .easy: return "easy"
        case .okay: return "okay"
        case .goodLuck: return "good_luck"
        case .free: return "free"
        case .paid: return "paid"
        }
    }

    static let standardOptions: [AttributeRating] = [.great, .good, .meh, .nope, .na]
    static let booleanOptions: [AttributeRating] = [.yes, .no]
    static let parkingOptions: [AttributeRating] = [.easy, .okay, .goodLuck]
    static let airWaterOptions: [AttributeRating] = [.free, .paid, .na]

    /// Some attributes use a Yes/No scale instead of the standard 5-level scale.
    static func options(for attributeName: String) -> [AttributeRating] {
        let normalized = attributeName.lowercased()
        if normalized.contains("pet friendly") || normalized.contains("lgbtq") {
            return booleanOptions
        }
        if normalized == "parking" {
            return parkingOptions
        }
        if normalized == "air/water" {
            return airWaterOptions
        }
        return standardOptions
    }
}

/// Helpers for rendering raw rating strings coming back from the API.
enum AttributeRatingDisplay {
    static func displayLabel(for raw: String) -> String {
        switch raw.lowercased() {
        case "great": return "Great"
        case "good": return "Good"
        case "meh": return "Meh"
        case "nope": return "Nope"
        case "yes": return "Yes"
        case "no": return "No"
        case "bad": return "Bad"
        case "easy": return "Easy"
        case "okay": return "Okay"
        case "good_luck": return "Good Luck"
        case "free": return "Free"
        case "paid": return "Paid"
        default: return ""
        }
    }

    static func colorIsPositive(for raw: String) -> Bool? {
        switch raw.lowercased() {
        case "great", "good", "yes", "easy", "free": return true
        case "meh", "okay", "paid": return nil
        case "nope", "no", "bad", "good_luck": return false
        default: return nil
        }
    }

    /// Brand color used to render the rating's text label.
    static func color(for raw: String) -> Color {
        switch raw.lowercased() {
        case "great":
            return Color(red: 0.00, green: 0.78, blue: 0.20)   // bright green
        case "good", "yes", "easy", "free":
            return Color(red: 0.20, green: 0.55, blue: 0.25)   // medium green
        case "meh", "okay", "paid":
            return Color(red: 0.95, green: 0.65, blue: 0.10)   // amber
        case "nope", "no", "bad", "good_luck":
            return .red
        default:
            return .secondary
        }
    }
}

/// Which attributes a user rates for a facility type. Shared by new entries and Edit Review.
enum EntryAttributeCatalog {
    /// Facility types that also rate "Air/Water"
    static let airWaterFacilityTypes: Set<String> = [
        "EV Charging Stations", "Gas Stations", "Highway Rest Areas", "RV Parks", "Truck Stops"
    ]

    static func attributeNames(forFacilityTypeName name: String) -> [String] {
        var names = name.localizedCaseInsensitiveContains("hotel") ? hotelAttributes : defaultAttributes
        // Air/Water goes right after Parking
        if airWaterFacilityTypes.contains(name), let parkingIndex = names.firstIndex(of: "Parking") {
            names.insert("Air/Water", at: parkingIndex + 1)
        }
        return names
    }

    /// Builds the rating rows for a facility type, keeping any ratings already chosen by name.
    /// Rated attributes from older versions of the app (names no longer in any list) are kept at the end
    /// so editing doesn't silently drop them; current attributes that don't apply to the type are dropped.
    static func entries(forFacilityTypeName name: String, keeping existing: [AttributeEntry]) -> [AttributeEntry] {
        let names = attributeNames(forFacilityTypeName: name)
        var rows = names.map { attrName -> AttributeEntry in
            var row = AttributeEntry(name: attrName)
            row.rating = existing.first { $0.name == attrName }?.rating ?? .na
            return row
        }
        let catalogNames = Set(hotelAttributes + defaultAttributes + ["Air/Water"])
        rows += existing.filter { !names.contains($0.name) && !catalogNames.contains($0.name) && $0.rating != .na }
        return rows
    }

    /// The legacy placeType sent alongside a bundled ("fb-") facility type.
    static func placeType(forFacilityTypeName name: String) -> String {
        switch name {
        case "Hotels":
            return "Hotel"
        case "Restaurants", "Coffee Shops", "Breweries/Wineries", "Bakeries":
            return "Restaurant"
        case "Gas Stations", "Truck Stops", "EV Charging Stations",
             "Grocery Stores", "Convenience Stores", "Pharmacies",
             "Outdoor/Camping Supply Stores", "Laundromats",
             "Hospitals/Urgent Care", "Pet Boarding/Vet Clinics", "Post Offices":
            return "Convenience Store"
        default:
            return "Rest Area"
        }
    }

    private static let hotelAttributes = [
        "Clean Room", "Clean Bathroom", "Feels Safe", "Friendly Staff",
        "Price", "Breakfast", "Gov Rate Available", "Parking",
        "Pet Friendly", "LGBTQ+ Friendly"
    ]

    private static let defaultAttributes = [
        "Clean", "Clean Bathroom", "Feels Safe", "Friendly Staff",
        "Price", "Food Options", "Parking", "Pet Friendly", "LGBTQ+ Friendly"
    ]
}

struct AttributeEntry: Identifiable {
    let id = UUID()
    let name: String
    var rating: AttributeRating = .na
}

struct InsightDraft {
    var latitude: Double?
    var longitude: Double?
    var locationName: String = ""
    var facilityTypeId: String = ""
    var placeType: PlaceType?
    var attributeEntries: [AttributeEntry] = []
    var comment: String = ""
    var starRating: Int = 3
    var isPublic: Bool = true
    var featureRatings: [FeatureRatingInput] = []
    var photos: [UIImageWrapper] = []

    var hasValidCoordinates: Bool {
        latitude != nil && longitude != nil
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lng = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

struct UIImageWrapper: Identifiable {
    let id = UUID()
    var image: UIImage
    var uploaded: Bool = false
    var uploadedURL: String?
}

struct Insight: Identifiable, Codable {
    let id: String
    let locationId: String
    let userId: String
    let comment: String?
    let isPublic: Bool
    let placeType: String?
    let starRating: Int?
    let createdAt: Date
    let updatedAt: Date
    let location: LocationDetail
    let ratings: [FeatureRatingResult]
    let attributeRatings: [AttributeRatingResult]?
    let photos: [Photo]
    let user: UserSummary
}

struct AttributeRatingResult: Codable, Identifiable {
    let id: String
    let attributeName: String
    let rating: String
}

struct LocationDetail: Codable {
    let id: String
    let name: String?
    let address: String?
    let latitude: Double
    let longitude: Double
    let facilityType: FacilityType
}

struct FeatureRatingResult: Codable, Identifiable {
    let id: String
    let rating: Int
    let featureCategory: FeatureCategory
}

struct Photo: Identifiable, Codable {
    let id: String
    let url: String
    let sizeBytes: Int?
    let createdAt: Date
}

struct UserSummary: Codable {
    let id: String
    let fullName: String
}

struct CategoriesResponse: Codable {
    let facilityTypes: [FacilityType]
    let featureCategories: [FeatureCategory]
}

// MARK: - Offline Queue

struct PendingInsight: Identifiable, Codable {
    let id: UUID
    let draft: CodableDraft
    let createdAt: Date

    struct CodableDraft: Codable {
        let latitude: Double
        let longitude: Double
        let locationName: String
        let facilityTypeId: String
        let placeType: String
        let starRating: Int
        let comment: String
        let isPublic: Bool
        let featureRatings: [CodableRating]
        let attributeRatings: [CodableAttributeRating]

        struct CodableRating: Codable {
            let featureCategoryId: String
            let rating: Int
        }

        struct CodableAttributeRating: Codable {
            let attributeName: String
            let rating: String
        }
    }
}
