import Foundation

struct NormalizedLocation: Hashable, Sendable {
    let id: String
    let label: String
}

struct FlightLocationResolver: Sendable {
    private let isoCodeByCountryName: [String: String]
    private let countryLabelByID: [String: String]
    private let cityLabelByID: [String: String]

    init(records: [FlightRecord]) {
        var codesByName: [String: Set<String>] = [:]
        for endpoint in records.flatMap(Self.endpoints) {
            guard
                let code = Self.isoCountryCode(endpoint.countryCode),
                let name = Self.knownTextKey(endpoint.country)
            else {
                continue
            }
            codesByName[name, default: []].insert(code)
        }
        isoCodeByCountryName = codesByName.reduce(into: [:]) {
            if $1.value.count == 1, let code = $1.value.first {
                $0[$1.key] = code
            }
        }

        var countryLabels: [String: Set<String>] = [:]
        var cityLabels: [String: Set<String>] = [:]
        for endpoint in records.flatMap(Self.endpoints) {
            guard let countryID = Self.countryKey(
                countryCode: endpoint.countryCode,
                countryName: endpoint.country,
                aliases: isoCodeByCountryName
            ) else {
                continue
            }
            if let countryLabel = Self.knownLabel(endpoint.country) {
                countryLabels[countryID, default: []].insert(countryLabel)
            }
            guard let cityKey = Self.knownTextKey(endpoint.city) else {
                continue
            }
            let cityID = "\(countryID)|\(cityKey)"
            if let cityLabel = Self.knownLabel(endpoint.city) {
                cityLabels[cityID, default: []].insert(cityLabel)
            }
        }
        countryLabelByID = countryLabels.mapValues(Self.preferredLabel)
        cityLabelByID = cityLabels.mapValues(Self.preferredLabel)
    }

    func country(countryCode: String, countryName: String) -> NormalizedLocation? {
        guard let id = Self.countryKey(
            countryCode: countryCode,
            countryName: countryName,
            aliases: isoCodeByCountryName
        ) else {
            return nil
        }
        let fallback = Self.knownLabel(countryName)
            ?? id.replacingOccurrences(of: "iso:", with: "")
        return NormalizedLocation(
            id: id,
            label: countryLabelByID[id] ?? fallback
        )
    }

    func city(
        city: String,
        countryCode: String,
        countryName: String
    ) -> NormalizedLocation? {
        guard let cityKey = Self.knownTextKey(city) else {
            return nil
        }
        let countryID = country(
            countryCode: countryCode,
            countryName: countryName
        )?.id ?? "unknown-country"
        let id = "\(countryID)|\(cityKey)"
        return NormalizedLocation(
            id: id,
            label: cityLabelByID[id] ?? Self.knownLabel(city) ?? cityKey
        )
    }

    private static func countryKey(
        countryCode: String,
        countryName: String,
        aliases: [String: String]
    ) -> String? {
        if let code = isoCountryCode(countryCode) {
            return "iso:\(code)"
        }
        guard let name = knownTextKey(countryName) else {
            return nil
        }
        return aliases[name].map { "iso:\($0)" } ?? "name:\(name)"
    }

    private static func endpoints(_ record: FlightRecord) -> [Endpoint] {
        [
            Endpoint(
                city: record.departureCity,
                country: record.departureCountry,
                countryCode: record.departureCountryCode
            ),
            Endpoint(
                city: record.arrivalCity,
                country: record.arrivalCountry,
                countryCode: record.arrivalCountryCode
            ),
        ]
    }

    private static func isoCountryCode(_ value: String) -> String? {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard code.unicodeScalars.count == 2,
              code.unicodeScalars.allSatisfy({
                  $0.isASCII && CharacterSet.uppercaseLetters.contains($0)
              })
        else {
            return nil
        }
        return code
    }

    private static func knownTextKey(_ value: String) -> String? {
        let key = folded(value)
        return key.isEmpty || key == "unknown" || key == "未知" ? nil : key
    }

    private static func knownLabel(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return knownTextKey(value) == nil ? nil : value
    }

    private static func folded(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

    private static func preferredLabel(_ labels: Set<String>) -> String {
        labels.sorted {
            let lhs = (folded($0), $0)
            let rhs = (folded($1), $1)
            return lhs < rhs
        }.first ?? ""
    }

    private struct Endpoint {
        let city: String
        let country: String
        let countryCode: String
    }
}
