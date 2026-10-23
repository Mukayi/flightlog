import Foundation

enum AirportSearchPresentation {
    static let prompt = "支持中文、IATA/ICAO、机场或城市"

    static func chineseAliasText(for airport: Airport) -> String? {
        let aliases = airport.aliases
            .filter { $0.unicodeScalars.contains(where: isHanCharacter) }
            .prefix(3)

        guard !aliases.isEmpty else { return nil }
        return aliases.joined(separator: "、")
    }

    private static func isHanCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x3134F:
            true
        default:
            false
        }
    }
}
