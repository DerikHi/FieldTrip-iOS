import Foundation
import UIKit
import SensitiveContentAnalysis

enum ContentModerationService {

    struct ModerationResult {
        let isClean: Bool
        let message: String?
    }

    // MARK: - Text Moderation

    static func checkText(_ text: String) -> ModerationResult {
        let normalized = normalize(text)
        let words = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for word in words {
            if profanitySet.contains(word) {
                return ModerationResult(isClean: false, message: "Please remove inappropriate language before continuing.")
            }
        }

        for phrase in profanityPhrases {
            if normalized.contains(phrase) {
                return ModerationResult(isClean: false, message: "Please remove inappropriate language before continuing.")
            }
        }

        return ModerationResult(isClean: true, message: nil)
    }

    private static func normalize(_ text: String) -> String {
        var result = text.lowercased()
        let substitutions: [Character: Character] = [
            "@": "a", "0": "o", "1": "i", "3": "e",
            "$": "s", "5": "s", "!": "i", "+": "t",
        ]
        result = String(result.map { substitutions[$0] ?? $0 })
        return result
    }

    private static let profanitySet: Set<String> = Set(profanityWords)

    private static let profanityWords: [String] = [
        "fuck", "fucker", "fucking", "fucked", "fucks", "fuk", "fuq",
        "shit", "shits", "shitty", "shitting",
        "bitch", "bitches", "bitching",
        "asshole", "assholes",
        "cunt", "cunts",
        "bastard", "bastards",
        "whore", "whores",
        "slut", "sluts",
        "motherfucker", "motherfuckers", "motherfucking",
        "bullshit", "horseshit", "dipshit",
        "douchebag", "douchebags",
        "wanker", "wankers",
        "twat", "twats",
        "nigger", "niggers", "nigga", "niggas",
        "faggot", "faggots", "fag",
        "retard", "retards", "retarded",
        "spic", "spics",
        "chink", "chinks",
        "kike", "kikes",
        "wetback", "wetbacks",
        "blowjob", "blowjobs",
        "handjob", "handjobs",
        "jerkoff", "jackoff",
        "cumshot", "cumshots",
        "porn", "porno", "pornography",
        "stfu", "gtfo",
    ]

    private static let profanityPhrases: [String] = [
        "fuck you", "fuck off", "suck my", "eat shit", "kiss my ass",
    ]

    // MARK: - Image Moderation

    static func checkImage(_ image: UIImage) async -> ModerationResult {
        let analyzer = SCSensitivityAnalyzer()
        guard analyzer.analysisPolicy != .disabled else {
            return ModerationResult(isClean: true, message: nil)
        }

        guard let cgImage = image.cgImage else {
            return ModerationResult(isClean: true, message: nil)
        }

        do {
            let response = try await analyzer.analyzeImage(cgImage)
            if response.isSensitive {
                return ModerationResult(
                    isClean: false,
                    message: "This image could not be added. Please choose a different photo."
                )
            }
        } catch {
            // Analysis failed — allow image through
        }

        return ModerationResult(isClean: true, message: nil)
    }
}
