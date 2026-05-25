import Foundation
import CoreLocation
import UIKit

struct FacilityType: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: String // "facility" | "natural_space"
    let icon: String?
    let description: String?
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
        }
    }

    static let standardOptions: [AttributeRating] = [.great, .good, .meh, .nope, .na]
    static let booleanOptions: [AttributeRating] = [.yes, .no]

    /// Some attributes use a Yes/No scale instead of the standard 5-level scale.
    static func options(for attributeName: String) -> [AttributeRating] {
        let normalized = attributeName.lowercased()
        if normalized.contains("pet friendly") || normalized.contains("lgbtq") {
            return booleanOptions
        }
        return standardOptions
    }
}

/// Helpers for rendering raw rating strings coming back from the API.
enum AttributeRatingDisplay {
    static func iconName(for raw: String) -> String {
        switch raw.lowercased() {
        case "great", "good", "yes": return "hand.thumbsup.fill"
        case "meh": return "minus.circle.fill"
        case "nope", "no", "bad": return "hand.thumbsdown.fill"
        default: return "circle"
        }
    }

    static func displayLabel(for raw: String) -> String {
        switch raw.lowercased() {
        case "great": return "Great"
        case "good": return "Good"
        case "meh": return "Meh"
        case "nope": return "Nope"
        case "yes": return "Yes"
        case "no": return "No"
        case "bad": return "Bad"
        default: return ""
        }
    }

    static func colorIsPositive(for raw: String) -> Bool? {
        switch raw.lowercased() {
        case "great", "good", "yes": return true
        case "meh": return nil
        case "nope", "no", "bad": return false
        default: return nil
        }
    }
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
