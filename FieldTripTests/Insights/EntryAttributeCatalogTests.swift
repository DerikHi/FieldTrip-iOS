import Testing
@testable import FieldTrip

struct EntryAttributeCatalogTests {

    @Test func parkingIsOfferedForEveryType() {
        for type in ["Hotels", "Restaurants", "Gas Stations", "Museums"] {
            #expect(EntryAttributeCatalog.attributeNames(forFacilityTypeName: type).contains("Parking"))
        }
    }

    @Test(arguments: ["EV Charging Stations", "Gas Stations", "Highway Rest Areas", "RV Parks", "Truck Stops"])
    func airWaterIsOfferedForTravelStops(type: String) {
        let names = EntryAttributeCatalog.attributeNames(forFacilityTypeName: type)
        let parking = try! #require(names.firstIndex(of: "Parking"))
        #expect(names[parking + 1] == "Air/Water")
    }

    @Test(arguments: ["Hotels", "Restaurants", "Campgrounds", "Public Restrooms"])
    func airWaterIsNotOfferedElsewhere(type: String) {
        #expect(!EntryAttributeCatalog.attributeNames(forFacilityTypeName: type).contains("Air/Water"))
    }

    @Test func ratingOptions() {
        #expect(AttributeRating.options(for: "Parking") == [.easy, .okay, .goodLuck])
        #expect(AttributeRating.options(for: "Air/Water") == [.free, .paid, .na])
        #expect(AttributeRating.goodLuck.apiValue == "good_luck")
        #expect(AttributeRatingDisplay.displayLabel(for: "good_luck") == "Good Luck")
    }

    @Test func changingTypeKeepsChosenRatings() {
        var parking = AttributeEntry(name: "Parking")
        parking.rating = .easy
        var airWater = AttributeEntry(name: "Air/Water")
        airWater.rating = .free
        var legacy = AttributeEntry(name: "Good Food")
        legacy.rating = .great

        // Gas Station -> Restaurant: Parking keeps its rating, Air/Water no longer applies,
        // and an attribute from an older app version is kept at the end
        let rows = EntryAttributeCatalog.entries(forFacilityTypeName: "Restaurants", keeping: [parking, airWater, legacy])
        #expect(rows.first { $0.name == "Parking" }?.rating == .easy)
        #expect(!rows.contains { $0.name == "Air/Water" })
        #expect(rows.last?.name == "Good Food")
    }
}
