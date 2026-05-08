import Foundation
import CoreLocation

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

struct InsightDraft {
    var latitude: Double?
    var longitude: Double?
    var locationName: String = ""
    var facilityTypeId: String = ""
    var comment: String = ""
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
    let createdAt: Date
    let updatedAt: Date
    let location: LocationDetail
    let ratings: [FeatureRatingResult]
    let photos: [Photo]
    let user: UserSummary
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
        let comment: String
        let isPublic: Bool
        let featureRatings: [CodableRating]

        struct CodableRating: Codable {
            let featureCategoryId: String
            let rating: Int
        }
    }
}
