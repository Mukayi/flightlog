import Foundation
import SwiftData

enum FlightRecordNormalization {
    static func code(_ value: String) -> String {
        value
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .uppercased()
    }
}

enum FlightLogSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [FlightRecord.self]
    }

    @Model
    final class FlightRecord {
        @Attribute(.unique) var id: UUID
        var flightNumber: String
        var airlineCode: String
        var airlineName: String
        var flightDate: Date

        var departureAirportIATA: String
        var departureDate: Date
        var departureTimeZoneID: String
        var departureLocalDateTime: String?
        var departureUTCOffsetSeconds: Int?
        var departureAirportName: String
        var departureCity: String
        var departureCountry: String
        var departureCountryCode: String = ""
        var departureLatitude: Double
        var departureLongitude: Double

        var arrivalAirportIATA: String
        var arrivalDate: Date
        var arrivalTimeZoneID: String
        var arrivalLocalDateTime: String?
        var arrivalUTCOffsetSeconds: Int?
        var arrivalAirportName: String
        var arrivalCity: String
        var arrivalCountry: String
        var arrivalCountryCode: String = ""
        var arrivalLatitude: Double
        var arrivalLongitude: Double

        var aircraftType: String?
        var cabinClass: String?
        var seat: String?
        var notes: String?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID,
            flightNumber: String,
            airlineCode: String,
            airlineName: String,
            flightDate: Date,
            departureAirportIATA: String,
            departureDate: Date,
            departureTimeZoneID: String,
            departureLocalDateTime: String?,
            departureUTCOffsetSeconds: Int?,
            departureAirportName: String,
            departureCity: String,
            departureCountry: String,
            departureCountryCode: String,
            departureLatitude: Double,
            departureLongitude: Double,
            arrivalAirportIATA: String,
            arrivalDate: Date,
            arrivalTimeZoneID: String,
            arrivalLocalDateTime: String?,
            arrivalUTCOffsetSeconds: Int?,
            arrivalAirportName: String,
            arrivalCity: String,
            arrivalCountry: String,
            arrivalCountryCode: String,
            arrivalLatitude: Double,
            arrivalLongitude: Double,
            aircraftType: String?,
            cabinClass: String?,
            seat: String?,
            notes: String?,
            createdAt: Date,
            updatedAt: Date
        ) {
            self.id = id
            self.flightNumber = flightNumber
            self.airlineCode = airlineCode
            self.airlineName = airlineName
            self.flightDate = flightDate
            self.departureAirportIATA = departureAirportIATA
            self.departureDate = departureDate
            self.departureTimeZoneID = departureTimeZoneID
            self.departureLocalDateTime = departureLocalDateTime
            self.departureUTCOffsetSeconds = departureUTCOffsetSeconds
            self.departureAirportName = departureAirportName
            self.departureCity = departureCity
            self.departureCountry = departureCountry
            self.departureCountryCode = departureCountryCode
            self.departureLatitude = departureLatitude
            self.departureLongitude = departureLongitude
            self.arrivalAirportIATA = arrivalAirportIATA
            self.arrivalDate = arrivalDate
            self.arrivalTimeZoneID = arrivalTimeZoneID
            self.arrivalLocalDateTime = arrivalLocalDateTime
            self.arrivalUTCOffsetSeconds = arrivalUTCOffsetSeconds
            self.arrivalAirportName = arrivalAirportName
            self.arrivalCity = arrivalCity
            self.arrivalCountry = arrivalCountry
            self.arrivalCountryCode = arrivalCountryCode
            self.arrivalLatitude = arrivalLatitude
            self.arrivalLongitude = arrivalLongitude
            self.aircraftType = aircraftType
            self.cabinClass = cabinClass
            self.seat = seat
            self.notes = notes
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }
}

enum FlightLogSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [FlightRecord.self, UserProfile.self]
    }

    @Model
    final class UserProfile {
        @Attribute(.unique) var id: UUID
        var displayName: String
        var createdAt: Date
        var sortOrder: Int
        var comparisonColorRawValue: String

        init(
            id: UUID = UUID(),
            displayName: String,
            createdAt: Date = .now,
            sortOrder: Int,
            comparisonColorRawValue: String
        ) {
            self.id = id
            self.displayName = displayName
            self.createdAt = createdAt
            self.sortOrder = sortOrder
            self.comparisonColorRawValue = comparisonColorRawValue
        }
    }

    @Model
    final class FlightRecord {
        @Attribute(.unique) var id: UUID
        var flightNumber: String
        var airlineCode: String
        var airlineName: String
        var flightDate: Date

        var departureAirportIATA: String
        var departureDate: Date
        var departureTimeZoneID: String
        var departureLocalDateTime: String?
        var departureUTCOffsetSeconds: Int?
        var departureAirportName: String
        var departureCity: String
        var departureCountry: String
        var departureCountryCode: String = ""
        var departureLatitude: Double
        var departureLongitude: Double

        var arrivalAirportIATA: String
        var arrivalDate: Date
        var arrivalTimeZoneID: String
        var arrivalLocalDateTime: String?
        var arrivalUTCOffsetSeconds: Int?
        var arrivalAirportName: String
        var arrivalCity: String
        var arrivalCountry: String
        var arrivalCountryCode: String = ""
        var arrivalLatitude: Double
        var arrivalLongitude: Double

        var aircraftType: String?
        var cabinClass: String?
        var seat: String?
        var notes: String?
        var ownerProfileID: UUID?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            flightNumber: String,
            airlineCode: String,
            airlineName: String,
            flightDate: Date,
            departureAirport: Airport,
            arrivalAirport: Airport,
            departureDate: Date,
            arrivalDate: Date,
            departureLocalDateTime: String? = nil,
            departureUTCOffsetSeconds: Int? = nil,
            arrivalLocalDateTime: String? = nil,
            arrivalUTCOffsetSeconds: Int? = nil,
            aircraftType: String? = nil,
            cabinClass: String? = nil,
            seat: String? = nil,
            notes: String? = nil,
            ownerProfileID: UUID,
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.flightNumber = FlightRecordNormalization.code(flightNumber)
            self.airlineCode = FlightRecordNormalization.code(airlineCode)
            self.airlineName = airlineName
            self.flightDate = flightDate

            departureAirportIATA = departureAirport.iata
            self.departureDate = departureDate
            departureTimeZoneID = departureAirport.timeZoneID
            self.departureLocalDateTime = departureLocalDateTime
                ?? HistoricalLocalTime.localDateTime(
                    snapshot: nil,
                    absoluteDate: departureDate,
                    timeZoneID: departureAirport.timeZoneID
                )
            self.departureUTCOffsetSeconds = departureUTCOffsetSeconds
                ?? TimeZone(identifier: departureAirport.timeZoneID)?
                .secondsFromGMT(for: departureDate)
            departureAirportName = departureAirport.name
            departureCity = departureAirport.city
            departureCountry = departureAirport.country
            departureCountryCode = departureAirport.countryCode
            departureLatitude = departureAirport.latitude
            departureLongitude = departureAirport.longitude

            arrivalAirportIATA = arrivalAirport.iata
            self.arrivalDate = arrivalDate
            arrivalTimeZoneID = arrivalAirport.timeZoneID
            self.arrivalLocalDateTime = arrivalLocalDateTime
                ?? HistoricalLocalTime.localDateTime(
                    snapshot: nil,
                    absoluteDate: arrivalDate,
                    timeZoneID: arrivalAirport.timeZoneID
                )
            self.arrivalUTCOffsetSeconds = arrivalUTCOffsetSeconds
                ?? TimeZone(identifier: arrivalAirport.timeZoneID)?
                .secondsFromGMT(for: arrivalDate)
            arrivalAirportName = arrivalAirport.name
            arrivalCity = arrivalAirport.city
            arrivalCountry = arrivalAirport.country
            arrivalCountryCode = arrivalAirport.countryCode
            arrivalLatitude = arrivalAirport.latitude
            arrivalLongitude = arrivalAirport.longitude

            self.aircraftType = aircraftType
            self.cabinClass = cabinClass
            self.seat = seat
            self.notes = notes
            self.ownerProfileID = ownerProfileID
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

        func markUpdated(at date: Date = .now) {
            updatedAt = date
        }
    }
}

typealias FlightRecord = FlightLogSchemaV2.FlightRecord
typealias UserProfile = FlightLogSchemaV2.UserProfile

enum UserProfileDefaults {
    static let id = UUID(
        uuidString: "6F2D55CF-4A3A-4F63-9A68-90D0D3FB17C4"
    )!
    static let displayName = "我的档案"
    static let comparisonColorRawValue = "blue"
}

enum UserProfileNameValidationError: Error, Equatable {
    case invalidLength
    case duplicate
}

struct UserProfileNameCandidate: Equatable, Sendable {
    let id: UUID
    let displayName: String
}

enum UserProfileNameValidator {
    static func normalize(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .precomposedStringWithCanonicalMapping
    }

    static func validatedName(
        _ value: String,
        existingNames: [String]
    ) throws -> String {
        try validate(
            value,
            against: existingNames
        )
    }

    static func validatedName(
        _ value: String,
        existingProfiles: [UserProfileNameCandidate],
        excludingProfileID: UUID? = nil
    ) throws -> String {
        try validate(
            value,
            against: existingProfiles.compactMap {
                $0.id == excludingProfileID ? nil : $0.displayName
            }
        )
    }

    private static func validate(
        _ value: String,
        against existingNames: [String]
    ) throws -> String {
        let normalized = normalize(value)
        guard (1...30).contains(normalized.count) else {
            throw UserProfileNameValidationError.invalidLength
        }
        let isDuplicate = existingNames.contains {
            comparisonKey($0) == comparisonKey(normalized)
        }
        guard !isDuplicate else {
            throw UserProfileNameValidationError.duplicate
        }
        return normalized
    }

    private static func comparisonKey(_ value: String) -> String {
        normalize(value)
            .folding(
                options: [
                    .caseInsensitive,
                    .widthInsensitive,
                ],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .precomposedStringWithCanonicalMapping
    }
}
