import Foundation

struct Airport: Codable, Identifiable, Sendable {
    let iata: String
    let icao: String
    let name: String
    let city: String
    let country: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let timeZoneID: String
    let aliases: [String]

    var id: String { iata }

    init(
        iata: String,
        icao: String,
        name: String,
        city: String,
        country: String,
        countryCode: String,
        latitude: Double,
        longitude: Double,
        timeZoneID: String,
        aliases: [String] = []
    ) {
        self.iata = iata.uppercased()
        self.icao = icao.uppercased()
        self.name = name
        self.city = city
        self.country = country
        self.countryCode = countryCode.uppercased()
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneID = timeZoneID
        self.aliases = aliases
    }

    private enum CodingKeys: String, CodingKey {
        case iata
        case icao
        case name
        case city
        case country
        case countryCode
        case latitude
        case longitude
        case timeZoneID
        case aliases
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            iata: try container.decode(String.self, forKey: .iata),
            icao: try container.decode(String.self, forKey: .icao),
            name: try container.decode(String.self, forKey: .name),
            city: try container.decode(String.self, forKey: .city),
            country: try container.decode(String.self, forKey: .country),
            countryCode: try container.decode(String.self, forKey: .countryCode),
            latitude: try container.decode(Double.self, forKey: .latitude),
            longitude: try container.decode(Double.self, forKey: .longitude),
            timeZoneID: try container.decode(String.self, forKey: .timeZoneID),
            aliases: try container.decodeIfPresent(
                [String].self,
                forKey: .aliases
            ) ?? []
        )
    }
}
