import XCTest
@testable import FieldTrip

final class ValidationServiceTests: XCTestCase {
    // MARK: - Email Tests

    func testValidEmails() {
        let validEmails = [
            "user@university.edu",
            "jane.smith@state.gov",
            "field.worker+tag@agency.org",
            "u@x.co",
        ]
        for email in validEmails {
            XCTAssertTrue(ValidationService.isValidEmail(email), "Expected valid: \(email)")
        }
    }

    func testInvalidEmails() {
        let invalidEmails = [
            "",
            "notanemail",
            "@nodomain.com",
            "missing@",
            "two@@at.com",
            "spaces in@email.com",
            "a" + String(repeating: "b", count: 255) + "@long.com",
        ]
        for email in invalidEmails {
            XCTAssertFalse(ValidationService.isValidEmail(email), "Expected invalid: \(email)")
        }
    }

    // MARK: - Password Strength

    func testWeakPasswords() {
        XCTAssertEqual(ValidationService.passwordStrength("abc"), .weak)
        XCTAssertEqual(ValidationService.passwordStrength("12345678"), .weak)
        XCTAssertEqual(ValidationService.passwordStrength("password"), .weak)
    }

    func testFairPasswords() {
        XCTAssertGreaterThanOrEqual(ValidationService.passwordStrength("Password1"), .fair)
    }

    func testStrongPasswords() {
        XCTAssertEqual(ValidationService.passwordStrength("Tr@vel!ng2025#"), .strong)
        XCTAssertEqual(ValidationService.passwordStrength("FieldTrip!99Secure"), .strong)
    }

    func testIsValidPasswordRequiresFairOrBetter() {
        XCTAssertFalse(ValidationService.isValidPassword("weak"))
        XCTAssertTrue(ValidationService.isValidPassword("Password1!"))
    }

    // MARK: - Password Match

    func testPasswordsMatch() {
        XCTAssertTrue(ValidationService.passwordsMatch("Secret!1", "Secret!1"))
        XCTAssertFalse(ValidationService.passwordsMatch("Secret!1", "Secret!2"))
        XCTAssertFalse(ValidationService.passwordsMatch("", ""))
    }

    // MARK: - Name Validation

    func testValidNames() {
        XCTAssertTrue(ValidationService.isValidName("Jo"))
        XCTAssertTrue(ValidationService.isValidName("Jane Smith"))
        XCTAssertTrue(ValidationService.isValidName("María García"))
    }

    func testInvalidNames() {
        XCTAssertFalse(ValidationService.isValidName(""))
        XCTAssertFalse(ValidationService.isValidName("J"))
        XCTAssertFalse(ValidationService.isValidName(String(repeating: "a", count: 101)))
    }

    // MARK: - Coordinate Parsing

    func testDecimalDegreesWithComma() {
        let result = ValidationService.parseCoordinates(from: "46.9319, -118.3878")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lat ?? 0, 46.9319, accuracy: 0.0001)
        XCTAssertEqual(result?.lng ?? 0, -118.3878, accuracy: 0.0001)
    }

    func testDecimalDegreesWithSpace() {
        let result = ValidationService.parseCoordinates(from: "46.9319 -118.3878")
        XCTAssertNotNil(result)
    }

    func testGoogleMapsURL() {
        let url = "https://www.google.com/maps/@46.9319,-118.3878,15z"
        let result = ValidationService.parseCoordinates(from: url)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lat ?? 0, 46.9319, accuracy: 0.0001)
    }

    func testAppleMapsURL() {
        let url = "https://maps.apple.com/?ll=46.9319,-118.3878&z=15"
        let result = ValidationService.parseCoordinates(from: url)
        XCTAssertNotNil(result)
    }

    func testInvalidCoordinates() {
        XCTAssertNil(ValidationService.parseCoordinates(from: ""))
        XCTAssertNil(ValidationService.parseCoordinates(from: "not coordinates"))
        XCTAssertNil(ValidationService.parseCoordinates(from: "999, 999"))
        XCTAssertNil(ValidationService.parseCoordinates(from: "91, 0"))
    }

    func testSQLInjectionAttempt() {
        XCTAssertNil(ValidationService.parseCoordinates(from: "46.9319'; DROP TABLE locations; --"))
    }

    func testNegativeLatitude() {
        let result = ValidationService.parseCoordinates(from: "-33.8688, 151.2093")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lat ?? 0, -33.8688, accuracy: 0.0001)
    }

    // MARK: - Comment

    func testCommentValidation() {
        XCTAssertTrue(ValidationService.isValidComment(""))
        XCTAssertTrue(ValidationService.isValidComment(String(repeating: "a", count: 125)))
        XCTAssertFalse(ValidationService.isValidComment(String(repeating: "a", count: 126)))
    }
}
