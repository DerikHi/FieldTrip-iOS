import Foundation

enum ValidationService {
    // MARK: - Email

    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 254 else { return false }
        // RFC 5322 simplified regex
        let pattern = #"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$"#
        return NSPredicate(format: "SELF MATCHES %@", pattern).evaluate(with: trimmed)
    }

    // MARK: - Password

    static func isValidPassword(_ password: String) -> Bool {
        passwordStrength(password) >= .fair
    }

    static func passwordStrength(_ password: String) -> PasswordStrength {
        var score = 0

        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.contains(where: \.isUppercase) { score += 1 }
        if password.contains(where: \.isNumber) { score += 1 }
        if password.range(of: #"[!@#$%^&*()_+\-=\[\]{}|;':",.<>?/\\`~]"#, options: .regularExpression) != nil {
            score += 1
        }

        switch score {
        case 0...2: return .weak
        case 3: return .fair
        default: return .strong
        }
    }

    static func passwordsMatch(_ p1: String, _ p2: String) -> Bool {
        !p1.isEmpty && p1 == p2
    }

    // MARK: - Name

    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 100
    }

    // MARK: - Coordinates

    static func parseCoordinates(from input: String) -> (lat: Double, lng: Double)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Decimal degrees: "46.9319, -118.3878"
        let decimalPattern = #"^(-?\d+\.?\d*)[,\s]+(-?\d+\.?\d*)$"#
        if let match = trimmed.range(of: decimalPattern, options: .regularExpression) {
            let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: ", ")).filter { !$0.isEmpty }
            if parts.count == 2,
               let lat = Double(parts[0]),
               let lng = Double(parts[1]),
               isValidLatLng(lat: lat, lng: lng) {
                return (lat, lng)
            }
        }

        // Google Maps URL "@lat,lng"
        if let range = trimmed.range(of: #"@(-?\d+\.?\d+),(-?\d+\.?\d+)"#, options: .regularExpression) {
            let matched = String(trimmed[range]).dropFirst() // remove @
            let parts = matched.split(separator: ",")
            if parts.count >= 2,
               let lat = Double(parts[0]),
               let lng = Double(parts[1]),
               isValidLatLng(lat: lat, lng: lng) {
                return (lat, lng)
            }
        }

        // Apple Maps URL "ll=lat,lng"
        if let range = trimmed.range(of: #"ll=(-?\d+\.?\d+),(-?\d+\.?\d+)"#, options: .regularExpression) {
            let matched = String(trimmed[range]).replacingOccurrences(of: "ll=", with: "")
            let parts = matched.split(separator: ",")
            if parts.count >= 2,
               let lat = Double(parts[0]),
               let lng = Double(parts[1]),
               isValidLatLng(lat: lat, lng: lng) {
                return (lat, lng)
            }
        }

        return nil
    }

    private static func isValidLatLng(lat: Double, lng: Double) -> Bool {
        lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
    }

    // MARK: - Comment

    static func isValidComment(_ comment: String) -> Bool {
        comment.count <= 125
    }
}
