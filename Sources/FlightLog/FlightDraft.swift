import Foundation

enum FlightDraftField: Hashable {
    case flightDate
    case flightNumber
    case airlineCode
    case airlineName
    case departureAirport
    case arrivalAirport
    case departureLocalDate
    case arrivalLocalDate
    case aircraftType
    case cabinClass
    case seat
    case notes
}

struct FlightDraft {
    var flightDate: Date
    var flightNumber: String
    var airlineCode: String
    var airlineName: String
    var departureAirport: Airport? {
        didSet {
            departureAirportWasReselected = true
        }
    }
    var arrivalAirport: Airport? {
        didSet {
            arrivalAirportWasReselected = true
        }
    }
    var departureLocalDate: Date
    var arrivalLocalDate: Date
    var departureLocalTimeOccurrence: LocalWallClockOccurrence
    var arrivalLocalTimeOccurrence: LocalWallClockOccurrence
    var aircraftType: String
    var cabinClass: String
    var seat: String
    var notes: String
    private(set) var departureAirportWasReselected: Bool
    private(set) var arrivalAirportWasReselected: Bool
    private let originalDepartureLocalDate: Date?
    private let originalArrivalLocalDate: Date?
    private let originalDepartureDate: Date?
    private let originalArrivalDate: Date?
    private let originalDepartureLocalDateTime: String?
    private let originalArrivalLocalDateTime: String?
    private let originalDepartureUTCOffsetSeconds: Int?
    private let originalArrivalUTCOffsetSeconds: Int?
    private let originalDepartureOccurrence: LocalWallClockOccurrence?
    private let originalArrivalOccurrence: LocalWallClockOccurrence?

    init(
        flightDate: Date = .now,
        flightNumber: String = "",
        airlineCode: String = "",
        airlineName: String = "",
        departureAirport: Airport? = nil,
        arrivalAirport: Airport? = nil,
        departureLocalDate: Date = .now,
        arrivalLocalDate: Date = .now.addingTimeInterval(7_200),
        departureLocalTimeOccurrence: LocalWallClockOccurrence = .first,
        arrivalLocalTimeOccurrence: LocalWallClockOccurrence = .first,
        aircraftType: String = "",
        cabinClass: String = "",
        seat: String = "",
        notes: String = ""
    ) {
        self.flightDate = flightDate
        self.flightNumber = flightNumber
        self.airlineCode = airlineCode
        self.airlineName = airlineName
        self.departureAirport = departureAirport
        self.arrivalAirport = arrivalAirport
        self.departureLocalDate = departureLocalDate
        self.arrivalLocalDate = arrivalLocalDate
        self.departureLocalTimeOccurrence = departureLocalTimeOccurrence
        self.arrivalLocalTimeOccurrence = arrivalLocalTimeOccurrence
        self.aircraftType = aircraftType
        self.cabinClass = cabinClass
        self.seat = seat
        self.notes = notes
        departureAirportWasReselected = departureAirport != nil
        arrivalAirportWasReselected = arrivalAirport != nil
        originalDepartureLocalDate = nil
        originalArrivalLocalDate = nil
        originalDepartureDate = nil
        originalArrivalDate = nil
        originalDepartureLocalDateTime = nil
        originalArrivalLocalDateTime = nil
        originalDepartureUTCOffsetSeconds = nil
        originalArrivalUTCOffsetSeconds = nil
        originalDepartureOccurrence = nil
        originalArrivalOccurrence = nil
    }

    init(record: FlightRecord, repository: AirportRepository) {
        flightDate = record.flightDate
        flightNumber = record.flightNumber
        airlineCode = record.airlineCode
        airlineName = record.airlineName
        departureAirport = Self.departureSnapshot(from: record)
        arrivalAirport = Self.arrivalSnapshot(from: record)
        let departureLocalDate = HistoricalLocalTime.wallClockDate(
            snapshot: record.departureLocalDateTime,
            absoluteDate: record.departureDate,
            timeZoneID: record.departureTimeZoneID
        )
        let arrivalLocalDate = HistoricalLocalTime.wallClockDate(
            snapshot: record.arrivalLocalDateTime,
            absoluteDate: record.arrivalDate,
            timeZoneID: record.arrivalTimeZoneID
        )
        self.departureLocalDate = departureLocalDate
        self.arrivalLocalDate = arrivalLocalDate
        departureLocalTimeOccurrence = Self.savedOccurrence(
            wallClockDate: departureLocalDate,
            timeZoneID: record.departureTimeZoneID,
            absoluteDate: record.departureDate,
            utcOffsetSeconds: record.departureUTCOffsetSeconds
        )
        arrivalLocalTimeOccurrence = Self.savedOccurrence(
            wallClockDate: arrivalLocalDate,
            timeZoneID: record.arrivalTimeZoneID,
            absoluteDate: record.arrivalDate,
            utcOffsetSeconds: record.arrivalUTCOffsetSeconds
        )
        aircraftType = record.aircraftType ?? ""
        cabinClass = record.cabinClass ?? ""
        seat = record.seat ?? ""
        notes = record.notes ?? ""
        departureAirportWasReselected = false
        arrivalAirportWasReselected = false
        originalDepartureLocalDate = departureLocalDate
        originalArrivalLocalDate = arrivalLocalDate
        originalDepartureDate = record.departureDate
        originalArrivalDate = record.arrivalDate
        originalDepartureLocalDateTime = record.departureLocalDateTime
        originalArrivalLocalDateTime = record.arrivalLocalDateTime
        originalDepartureUTCOffsetSeconds =
            record.departureUTCOffsetSeconds
        originalArrivalUTCOffsetSeconds = record.arrivalUTCOffsetSeconds
        originalDepartureOccurrence = departureLocalTimeOccurrence
        originalArrivalOccurrence = arrivalLocalTimeOccurrence
    }

    var normalizedFlightNumber: String {
        FlightRecordNormalization.code(flightNumber)
    }

    mutating func setFlightDate(_ newDate: Date) {
        let currentDate = FlightDateNormalization.canonicalDate(
            departureLocalDate
        )
        let targetDate = FlightDateNormalization.canonicalDate(newDate)
        let dayShift = targetDate.timeIntervalSince(currentDate)

        departureLocalDate = departureLocalDate.addingTimeInterval(dayShift)
        arrivalLocalDate = arrivalLocalDate.addingTimeInterval(dayShift)
        flightDate = targetDate
    }

    var departureAmbiguityChoices: [LocalWallClockOccurrence] {
        ambiguityChoices(
            wallClockDate: departureLocalDate,
            timeZoneID: departureAirport?.timeZoneID
        )
    }

    var arrivalAmbiguityChoices: [LocalWallClockOccurrence] {
        ambiguityChoices(
            wallClockDate: arrivalLocalDate,
            timeZoneID: arrivalAirport?.timeZoneID
        )
    }

    var usesSavedDepartureAirport: Bool {
        originalDepartureDate != nil && !departureAirportWasReselected
    }

    var usesSavedArrivalAirport: Bool {
        originalArrivalDate != nil && !arrivalAirportWasReselected
    }

    var unchangedDepartureDate: Date? {
        guard
            usesSavedDepartureAirport,
            departureLocalDate == originalDepartureLocalDate,
            departureLocalTimeOccurrence == originalDepartureOccurrence,
            savedOffsetMatches(
                wallClockDate: departureLocalDate,
                airport: departureAirport,
                occurrence: departureLocalTimeOccurrence,
                originalOffset: originalDepartureUTCOffsetSeconds
            )
        else {
            return nil
        }
        return originalDepartureDate
    }

    var unchangedArrivalDate: Date? {
        guard
            usesSavedArrivalAirport,
            arrivalLocalDate == originalArrivalLocalDate,
            arrivalLocalTimeOccurrence == originalArrivalOccurrence,
            savedOffsetMatches(
                wallClockDate: arrivalLocalDate,
                airport: arrivalAirport,
                occurrence: arrivalLocalTimeOccurrence,
                originalOffset: originalArrivalUTCOffsetSeconds
            )
        else {
            return nil
        }
        return originalArrivalDate
    }

    var unchangedDepartureLocalDateTime: String? {
        unchangedDepartureDate == nil
            ? nil
            : originalDepartureLocalDateTime
    }

    var unchangedArrivalLocalDateTime: String? {
        unchangedArrivalDate == nil
            ? nil
            : originalArrivalLocalDateTime
    }

    var unchangedDepartureUTCOffsetSeconds: Int? {
        unchangedDepartureDate == nil
            ? nil
            : originalDepartureUTCOffsetSeconds
    }

    var unchangedArrivalUTCOffsetSeconds: Int? {
        unchangedArrivalDate == nil
            ? nil
            : originalArrivalUTCOffsetSeconds
    }

    private func ambiguityChoices(
        wallClockDate: Date,
        timeZoneID: String?
    ) -> [LocalWallClockOccurrence] {
        guard
            let timeZoneID,
            let resolution = try? LocalWallClockResolver.resolve(
                wallClockDate,
                timeZoneID: timeZoneID
            ),
            resolution.isAmbiguous
        else {
            return []
        }
        return [.first, .second]
    }

    private func savedOffsetMatches(
        wallClockDate: Date,
        airport: Airport?,
        occurrence: LocalWallClockOccurrence,
        originalOffset: Int?
    ) -> Bool {
        guard let originalOffset else { return true }
        guard
            let airport,
            let resolution = try? LocalWallClockResolver.resolve(
                wallClockDate,
                timeZoneID: airport.timeZoneID
            )
        else {
            return false
        }
        return resolution.candidate(for: occurrence).utcOffsetSeconds
            == originalOffset
    }

    private static func savedOccurrence(
        wallClockDate: Date,
        timeZoneID: String,
        absoluteDate: Date,
        utcOffsetSeconds: Int?
    ) -> LocalWallClockOccurrence {
        guard
            let resolution = try? LocalWallClockResolver.resolve(
                wallClockDate,
                timeZoneID: timeZoneID
            ),
            resolution.isAmbiguous
        else {
            return .first
        }
        if
            let match = resolution.candidates.first(where: {
                $0.absoluteDate == absoluteDate
                    || $0.utcOffsetSeconds == utcOffsetSeconds
            })
        {
            return match.occurrence
        }
        return .first
    }

    private static func departureSnapshot(from record: FlightRecord) -> Airport {
        Airport(
            iata: record.departureAirportIATA,
            icao: "",
            name: record.departureAirportName,
            city: record.departureCity,
            country: record.departureCountry,
            countryCode: record.departureCountryCode,
            latitude: record.departureLatitude,
            longitude: record.departureLongitude,
            timeZoneID: record.departureTimeZoneID
        )
    }

    private static func arrivalSnapshot(from record: FlightRecord) -> Airport {
        Airport(
            iata: record.arrivalAirportIATA,
            icao: "",
            name: record.arrivalAirportName,
            city: record.arrivalCity,
            country: record.arrivalCountry,
            countryCode: record.arrivalCountryCode,
            latitude: record.arrivalLatitude,
            longitude: record.arrivalLongitude,
            timeZoneID: record.arrivalTimeZoneID
        )
    }
}

enum FlightDateNormalization {
    static func canonicalDate(_ date: Date) -> Date {
        let components = wallClockCalendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return wallClockCalendar.date(from: components) ?? date
    }

    static func isSameDate(_ lhs: Date, _ rhs: Date) -> Bool {
        canonicalDate(lhs) == canonicalDate(rhs)
    }

    private static var wallClockCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
