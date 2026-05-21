import Foundation
import CoreLocation

/// Decoder for Open Location Code (Plus Code) — Google's geocoding format.
/// Supports full codes like "849VCWC8+R9" and short codes like "CWC8+R9 Springfield, IL".
enum PlusCodeService {

    private static let alphabet = Array("23456789CFGHJMPQRVWX")
    private static let separator: Character = "+"
    private static let paddingChar: Character = "0"
    private static let base = 20
    private static let pairCount = 5            // 10 characters before the +
    private static let gridRows = 5
    private static let gridColumns = 4
    private static let pairResolutions: [Double] = [20, 1, 1.0 / 20, 1.0 / 400, 1.0 / 8000]

    /// Detect whether a string looks like a Plus Code (with optional locality after a space).
    static func looksLikePlusCode(_ input: String) -> Bool {
        let codePart = input.split(separator: " ", maxSplits: 1).first.map(String.init) ?? input
        let trimmed = codePart.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.contains(separator) else { return false }
        let body = trimmed.replacingOccurrences(of: String(separator), with: "")
        guard body.count >= 4, body.count <= 15 else { return false }
        let allowed = Set(alphabet + [paddingChar])
        return body.allSatisfy { allowed.contains($0) }
    }

    /// Decode a Plus Code into coordinates. If the code is short, resolve via the optional
    /// locality (e.g. "CWC8+R9 Springfield, IL").
    static func decode(_ input: String) async -> CLLocationCoordinate2D? {
        let parts = input.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return nil }
        let codeRaw = String(first).trimmingCharacters(in: .whitespaces).uppercased()
        let locality = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : nil

        if isFullCode(codeRaw) {
            return decodeFullCode(codeRaw)
        }

        guard let locality, !locality.isEmpty,
              let reference = try? await CLGeocoder().geocodeAddressString(locality).first?.location else {
            return nil
        }
        guard let full = recoverShortCode(codeRaw, refLat: reference.coordinate.latitude, refLng: reference.coordinate.longitude) else {
            return nil
        }
        return decodeFullCode(full)
    }

    // MARK: - Internal

    private static func isFullCode(_ code: String) -> Bool {
        guard let plusIndex = code.firstIndex(of: separator) else { return false }
        return code.distance(from: code.startIndex, to: plusIndex) == 8
    }

    private static func indexOf(_ ch: Character) -> Int? {
        alphabet.firstIndex(of: ch)
    }

    private static func decodeFullCode(_ code: String) -> CLLocationCoordinate2D? {
        let stripped = code.replacingOccurrences(of: String(separator), with: "")
            .replacingOccurrences(of: String(paddingChar), with: "")
        let chars = Array(stripped)
        guard chars.count >= 4, chars.count % 2 == 0 || chars.count > 10 else { return nil }

        var lat: Double = -90
        var lng: Double = -180
        var latRes: Double = 400 / Double(base) // = 20
        var lngRes: Double = 400 / Double(base) // = 20
        latRes = 20
        lngRes = 20

        var idx = 0
        let pairChars = min(chars.count, 10)
        var step = 0
        while idx < pairChars {
            guard let latDigit = indexOf(chars[idx]) else { return nil }
            guard idx + 1 < pairChars, let lngDigit = indexOf(chars[idx + 1]) else { return nil }
            lat += Double(latDigit) * latRes
            lng += Double(lngDigit) * lngRes
            idx += 2
            step += 1
            if step < pairResolutions.count {
                latRes /= Double(base)
                lngRes /= Double(base)
            }
        }

        // After pair section, current latRes/lngRes is already divided one more time
        // — back it up to be the resolution of the last consumed pair.
        if pairChars > 0 {
            latRes *= Double(base)
            lngRes *= Double(base)
        }

        // Grid refinement
        if chars.count > 10 {
            var rowRes = latRes
            var colRes = lngRes
            for i in 10..<chars.count {
                rowRes /= Double(gridRows)
                colRes /= Double(gridColumns)
                guard let v = indexOf(chars[i]) else { return nil }
                let row = v / gridColumns
                let col = v % gridColumns
                lat += Double(row) * rowRes
                lng += Double(col) * colRes
            }
            latRes = rowRes
            lngRes = colRes
        }

        // Center the result inside the resolved cell
        lat += latRes / 2
        lng += lngRes / 2

        guard lat >= -90, lat <= 90, lng >= -180, lng <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// Combine a short code with a reference location to recover the full code.
    private static func recoverShortCode(_ short: String, refLat: Double, refLng: Double) -> String? {
        guard let plusIndex = short.firstIndex(of: separator) else { return nil }
        let prefixLength = short.distance(from: short.startIndex, to: plusIndex)
        let paddingLength = 8 - prefixLength
        guard paddingLength > 0, paddingLength % 2 == 0 else { return nil }

        let refFull = encodeFullCode(latitude: refLat, longitude: refLng)
        // refFull will be 11 chars including '+' at index 8
        let refStripped = refFull.replacingOccurrences(of: String(separator), with: "")
        let neededPrefix = String(refStripped.prefix(paddingLength))
        let combined = neededPrefix + short.replacingOccurrences(of: String(separator), with: "")
        // Re-insert separator at position 8
        guard combined.count >= 8 else { return nil }
        var result = combined
        result.insert(separator, at: result.index(result.startIndex, offsetBy: 8))
        return result
    }

    /// Encode a coordinate as a full 10-digit Plus Code (no grid refinement).
    private static func encodeFullCode(latitude: Double, longitude: Double) -> String {
        var lat = max(-90, min(90, latitude))
        var lng = longitude
        while lng < -180 { lng += 360 }
        while lng >= 180 { lng -= 360 }
        if lat == 90 { lat -= 1e-12 }

        var latVal = lat + 90
        var lngVal = lng + 180

        var digits: [Character] = []
        for resolution in pairResolutions {
            let latIdx = min(Int((latVal / resolution).rounded(.down)), base - 1)
            let lngIdx = min(Int((lngVal / resolution).rounded(.down)), base - 1)
            latVal -= Double(latIdx) * resolution
            lngVal -= Double(lngIdx) * resolution
            digits.append(alphabet[latIdx])
            digits.append(alphabet[lngIdx])
        }
        var code = String(digits)
        code.insert(separator, at: code.index(code.startIndex, offsetBy: 8))
        return code
    }
}
