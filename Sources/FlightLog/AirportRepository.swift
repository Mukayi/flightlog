import Foundation

enum AirportRepositoryError: LocalizedError {
    case resourceNotFound

    var errorDescription: String? {
        switch self {
        case .resourceNotFound:
            "找不到内置机场资料文件。"
        }
    }
}

struct AirportRepository: Sendable {
    let airports: [Airport]
    private let airportsByIATA: [String: Airport]

    init(airports: [Airport]) {
        let airports = airports.sorted {
            ($0.iata, $0.name) < ($1.iata, $1.name)
        }
        self.airports = airports
        airportsByIATA = airports.reduce(into: [:]) { index, airport in
            if index[airport.iata] == nil {
                index[airport.iata] = airport
            }
        }
    }

    init() throws {
        let url = try Self.resolveResourceURL(
            mainResourceURL: Bundle.main.url(
                forResource: "airports",
                withExtension: "json"
            ),
            swiftPMFallback: {
                Bundle.module.url(
                    forResource: "airports",
                    withExtension: "json"
                )
            }
        )

        let data = try Data(contentsOf: url)
        let airports = try JSONDecoder().decode([Airport].self, from: data)
        self.init(airports: airports)
    }

    static func resolveResourceURL(
        mainResourceURL: URL?,
        swiftPMFallback: () -> URL?
    ) throws -> URL {
        if let mainResourceURL {
            return mainResourceURL
        }
        guard let fallback = swiftPMFallback() else {
            throw AirportRepositoryError.resourceNotFound
        }
        return fallback
    }

    func airport(iata: String) -> Airport? {
        let code = FlightRecordNormalization.code(iata)
        return airportsByIATA[code]
    }

    func search(_ query: String, limit: Int = 20) -> [Airport] {
        guard limit > 0 else { return [] }

        let needle = Self.searchKey(query)
        guard !needle.isEmpty else { return [] }

        let ranked = airports
            .compactMap { airport -> (Airport, Int)? in
                guard let rank = Self.rank(airport, matching: needle) else {
                    return nil
                }
                return (airport, rank)
            }
            .sorted {
                if $0.1 != $1.1 {
                    return $0.1 < $1.1
                }
                return ($0.0.iata, $0.0.name) < ($1.0.iata, $1.0.name)
            }

        var seenIATA = Set<String>()
        return ranked
            .filter { seenIATA.insert($0.0.iata).inserted }
            .prefix(limit)
            .map(\.0)
    }

    private static func rank(_ airport: Airport, matching query: String) -> Int? {
        let iata = searchKey(airport.iata)
        let icao = searchKey(airport.icao)
        let name = searchKey(airport.name)
        let city = searchKey(airport.city)
        let country = searchKey(airport.country)
        let aliases = airport.aliases.map(searchKey)

        if iata == query { return 0 }
        if icao == query { return 1 }
        if iata.hasPrefix(query) { return 2 }
        if icao.hasPrefix(query) { return 3 }
        if aliases.contains(query) { return 4 }
        if aliases.contains(where: { $0.hasPrefix(query) }) { return 5 }
        if city.hasPrefix(query) { return 6 }
        if name.hasPrefix(query) { return 7 }
        if country.hasPrefix(query) { return 8 }
        if aliases.contains(where: { $0.contains(query) }) { return 9 }
        if city.contains(query) { return 10 }
        if name.contains(query) { return 11 }
        if country.contains(query) { return 12 }
        return nil
    }

    private static func searchKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

}
