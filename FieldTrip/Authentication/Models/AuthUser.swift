import Foundation

struct AuthUser: Equatable, Codable {
    let id: String
    let email: String
    let fullName: String
    let role: UserRole
    let organization: String?
    let createdAt: Date

    enum UserRole: String, Codable {
        case user
        case admin
    }

    var isAdmin: Bool { role == .admin }
}

enum PasswordStrength: Int, Comparable {
    case weak = 0
    case fair = 1
    case strong = 2

    static func < (lhs: PasswordStrength, rhs: PasswordStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .weak: return "Weak"
        case .fair: return "Fair"
        case .strong: return "Strong"
        }
    }

    var color: String {
        switch self {
        case .weak: return "red"
        case .fair: return "orange"
        case .strong: return "green"
        }
    }

    var progress: Double {
        switch self {
        case .weak: return 0.33
        case .fair: return 0.66
        case .strong: return 1.0
        }
    }
}
