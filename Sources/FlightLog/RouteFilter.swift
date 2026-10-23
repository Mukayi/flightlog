import Foundation

struct RouteFilter: Equatable {
    var dateRange: ClosedRange<Date>?
    var airline: String?
    var airportIATA: String?

    init(
        dateRange: ClosedRange<Date>? = nil,
        airline: String? = nil,
        airportIATA: String? = nil
    ) {
        self.dateRange = dateRange
        self.airline = airline
        self.airportIATA = airportIATA
    }

    var isActive: Bool {
        dateRange != nil || airline != nil || airportIATA != nil
    }

    func apply(to records: [FlightRecord]) -> [FlightRecord] {
        records.filter(matches)
    }

    static func dateRange(forYear year: Int) -> ClosedRange<Date>? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard
            let start = calendar.date(
                from: DateComponents(year: year, month: 1, day: 1)
            ),
            let nextYear = calendar.date(
                from: DateComponents(year: year + 1, month: 1, day: 1)
            )
        else {
            return nil
        }
        return start...nextYear.addingTimeInterval(-0.001)
    }

    private func matches(_ record: FlightRecord) -> Bool {
        if
            let dateRange,
            !dateRange.contains(record.flightDate)
        {
            return false
        }

        if let airline {
            let airlineKey = Self.folded(airline)
            if
                Self.folded(record.airlineCode) != airlineKey,
                Self.folded(record.airlineName) != airlineKey
            {
                return false
            }
        }

        if let airportIATA {
            let airportCode = FlightRecordNormalization.code(airportIATA)
            if
                record.departureAirportIATA != airportCode,
                record.arrivalAirportIATA != airportCode
            {
                return false
            }
        }

        return true
    }

    private static func folded(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }
}

enum RouteSelection {
    static func reconciled(
        selectedRouteID: String?,
        visibleRouteIDs: [String]
    ) -> String? {
        guard let selectedRouteID else {
            return nil
        }
        return visibleRouteIDs.contains(selectedRouteID)
            ? selectedRouteID
            : nil
    }
}
