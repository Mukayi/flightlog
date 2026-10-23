import Foundation

enum FlightSortOrder: String, CaseIterable, Identifiable {
    case dateDescending
    case flightNumber
    case route

    var id: Self { self }

    var title: String {
        switch self {
        case .dateDescending: "日期（最新优先）"
        case .flightNumber: "航班号"
        case .route: "航线"
        }
    }
}

struct FlightListFilter: Equatable {
    var year: Int?
    var airline: String?
    var airportIATA: String?

    init(
        year: Int? = nil,
        airline: String? = nil,
        airportIATA: String? = nil
    ) {
        self.year = year
        self.airline = airline
        self.airportIATA = airportIATA
    }

    var isActive: Bool {
        year != nil || airline != nil || airportIATA != nil
    }
}

enum FlightListEmptyRecovery: Equatable {
    case addFlight
    case clearSearch
    case clearFilters
    case clearSearchAndFilters

    static func resolve(
        hasRecords: Bool,
        searchText: String,
        filterIsActive: Bool
    ) -> Self {
        guard hasRecords else {
            return .addFlight
        }

        let hasSearch = !searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        switch (hasSearch, filterIsActive) {
        case (true, true):
            return .clearSearchAndFilters
        case (true, false):
            return .clearSearch
        case (false, true):
            return .clearFilters
        case (false, false):
            return .clearSearch
        }
    }
}

enum FlightListSelection {
    static func reconciled(
        selectedID: UUID?,
        visibleIDs: [UUID]
    ) -> UUID? {
        guard let selectedID else { return nil }
        return visibleIDs.contains(selectedID) ? selectedID : nil
    }
}

struct FlightOpenRequestResolution: Equatable {
    let selectedID: UUID
    let searchText: String
    let filter: FlightListFilter

    static func resolve(
        requestedID: UUID,
        records: [FlightRecord],
        searchText: String,
        sortOrder: FlightSortOrder,
        filter: FlightListFilter
    ) -> Self? {
        guard let target = records.first(where: { $0.id == requestedID }) else {
            return nil
        }

        let currentQueryShowsTarget = FlightListQuery.apply(
            to: [target],
            searchText: searchText,
            sortOrder: sortOrder,
            filter: filter
        ).contains { $0.id == requestedID }
        guard !currentQueryShowsTarget else {
            return Self(
                selectedID: requestedID,
                searchText: searchText,
                filter: filter
            )
        }

        let searchShowsTarget = FlightListQuery.apply(
            to: [target],
            searchText: searchText,
            sortOrder: sortOrder,
            filter: FlightListFilter()
        ).contains { $0.id == requestedID }
        let filterShowsTarget = FlightListQuery.apply(
            to: [target],
            searchText: "",
            sortOrder: sortOrder,
            filter: filter
        ).contains { $0.id == requestedID }

        return Self(
            selectedID: requestedID,
            searchText: searchShowsTarget ? searchText : "",
            filter: filterShowsTarget ? filter : FlightListFilter()
        )
    }
}

enum FlightListQuery {
    static func apply(
        to records: [FlightRecord],
        searchText: String = "",
        sortOrder: FlightSortOrder = .dateDescending,
        filter: FlightListFilter = FlightListFilter()
    ) -> [FlightRecord] {
        records
            .filter { matchesSearch($0, searchText: searchText) }
            .filter { matchesFilter($0, filter: filter) }
            .sorted { lhs, rhs in
                ordered(lhs, before: rhs, by: sortOrder)
            }
    }

    private static func matchesSearch(
        _ record: FlightRecord,
        searchText: String
    ) -> Bool {
        let searchKey = folded(searchText)
        guard !searchKey.isEmpty else { return true }

        let codeKey = FlightRecordNormalization.code(searchText)
        if !codeKey.isEmpty {
            if record.flightNumber.contains(codeKey)
                || record.airlineCode.contains(codeKey)
                || record.departureAirportIATA.contains(codeKey)
                || record.arrivalAirportIATA.contains(codeKey)
            {
                return true
            }
        }

        return [
            record.flightNumber,
            record.airlineCode,
            record.airlineName,
            record.departureAirportIATA,
            record.departureAirportName,
            record.departureCity,
            record.arrivalAirportIATA,
            record.arrivalAirportName,
            record.arrivalCity,
        ].contains { folded($0).contains(searchKey) }
    }

    private static func matchesFilter(
        _ record: FlightRecord,
        filter: FlightListFilter
    ) -> Bool {
        if
            let year = filter.year,
            calendar.component(.year, from: record.flightDate) != year
        {
            return false
        }

        if let airline = filter.airline {
            let airlineKey = folded(airline)
            let codeMatches = folded(record.airlineCode) == airlineKey
            let nameMatches = folded(record.airlineName) == airlineKey
            if !codeMatches && !nameMatches {
                return false
            }
        }

        if let airportIATA = filter.airportIATA {
            let airportCode = FlightRecordNormalization.code(airportIATA)
            if
                record.departureAirportIATA != airportCode
                    && record.arrivalAirportIATA != airportCode
            {
                return false
            }
        }

        return true
    }

    private static func ordered(
        _ lhs: FlightRecord,
        before rhs: FlightRecord,
        by sortOrder: FlightSortOrder
    ) -> Bool {
        let result: Bool
        switch sortOrder {
        case .dateDescending:
            if lhs.flightDate != rhs.flightDate {
                result = lhs.flightDate > rhs.flightDate
            } else {
                result = lhs.flightNumber < rhs.flightNumber
            }
        case .flightNumber:
            if lhs.flightNumber != rhs.flightNumber {
                result = lhs.flightNumber < rhs.flightNumber
            } else {
                result = lhs.flightDate > rhs.flightDate
            }
        case .route:
            let lhsRoute = (
                lhs.departureAirportIATA,
                lhs.arrivalAirportIATA,
                lhs.flightNumber
            )
            let rhsRoute = (
                rhs.departureAirportIATA,
                rhs.arrivalAirportIATA,
                rhs.flightNumber
            )
            result = lhsRoute < rhsRoute
        }

        if primaryKeysAreEqual(lhs, rhs, sortOrder: sortOrder) {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return result
    }

    private static func primaryKeysAreEqual(
        _ lhs: FlightRecord,
        _ rhs: FlightRecord,
        sortOrder: FlightSortOrder
    ) -> Bool {
        switch sortOrder {
        case .dateDescending:
            lhs.flightDate == rhs.flightDate
                && lhs.flightNumber == rhs.flightNumber
        case .flightNumber:
            lhs.flightNumber == rhs.flightNumber
                && lhs.flightDate == rhs.flightDate
        case .route:
            lhs.departureAirportIATA == rhs.departureAirportIATA
                && lhs.arrivalAirportIATA == rhs.arrivalAirportIATA
                && lhs.flightNumber == rhs.flightNumber
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
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

enum FlightDuplicateDetector {
    static func matches(
        _ draft: FlightDraft,
        in records: [FlightRecord],
        ownerProfileID: UUID,
        excluding excludedID: UUID? = nil
    ) -> [FlightRecord] {
        guard
            let departureIATA = draft.departureAirport?.iata,
            let arrivalIATA = draft.arrivalAirport?.iata
        else {
            return []
        }

        let flightNumber = draft.normalizedFlightNumber
        let flightDate = FlightDateNormalization.canonicalDate(
            draft.departureLocalDate
        )
        return records.filter { record in
            record.id != excludedID
                && record.ownerProfileID == ownerProfileID
                && record.flightNumber == flightNumber
                && FlightDateNormalization.isSameDate(
                    record.flightDate,
                    flightDate
                )
                && record.departureAirportIATA == departureIATA
                && record.arrivalAirportIATA == arrivalIATA
        }
    }
}
