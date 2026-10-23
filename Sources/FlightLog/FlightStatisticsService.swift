import Foundation

enum StatisticsFilter: Equatable, Sendable {
    case all
    case year(Int)
    case dateRange(ClosedRange<Date>)

    fileprivate func includes(_ date: Date) -> Bool {
        switch self {
        case .all:
            true
        case let .year(year):
            FlightStatisticsCalendar.year(for: date) == year
        case let .dateRange(range):
            range.contains(date)
        }
    }

    fileprivate var selectedYear: Int? {
        guard case let .year(year) = self else {
            return nil
        }
        return year
    }
}

struct StatisticsRankingItem: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let count: Int
}

struct LongestFlightStatistic: Identifiable, Equatable, Sendable {
    let id: UUID
    let flightNumber: String
    let route: String
    let airline: String
    let flightDate: Date
    let distanceKilometers: Double
    let durationMinutes: Int?
}

struct StatisticsMonth: Identifiable, Hashable, Comparable, Sendable {
    let year: Int
    let month: Int

    var id: String {
        String(format: "%04d-%02d", year, month)
    }

    var label: String {
        "\(year) 年 \(month) 月"
    }

    var shortLabel: String {
        "\(month) 月"
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

struct YearlyStatisticsTrend: Identifiable, Equatable, Sendable {
    let year: Int
    let flightCount: Int
    let totalDistanceKilometers: Double?
    let measuredDistanceFlightCount: Int
    let missingDistanceFlightCount: Int
    let totalDurationMinutes: Int?
    let measuredDurationFlightCount: Int
    let missingDurationFlightCount: Int

    var id: Int { year }
}

struct MonthlyStatisticsTrend: Identifiable, Equatable, Sendable {
    let month: StatisticsMonth
    let flightCount: Int
    let totalDistanceKilometers: Double?
    let measuredDistanceFlightCount: Int
    let missingDistanceFlightCount: Int
    let totalDurationMinutes: Int?
    let measuredDurationFlightCount: Int
    let missingDurationFlightCount: Int

    var id: String { month.id }
}

struct StatisticsSnapshot: Equatable, Sendable {
    let totalFlightCount: Int
    let totalDistanceKilometers: Double?
    let measuredDistanceFlightCount: Int
    let missingDistanceFlightCount: Int
    let totalDurationMinutes: Int?
    let measuredDurationFlightCount: Int
    let missingDurationFlightCount: Int
    let uniqueAirportCount: Int
    let uniqueCityCount: Int
    let uniqueCountryCount: Int
    let domesticFlightCount: Int
    let internationalFlightCount: Int
    let unknownClassificationFlightCount: Int
    let airportRankings: [StatisticsRankingItem]
    let airlineRankings: [StatisticsRankingItem]
    let routeRankings: [StatisticsRankingItem]
    let longestFlights: [LongestFlightStatistic]
    let yearlyTrend: [YearlyStatisticsTrend]
    let monthlyTrend: [MonthlyStatisticsTrend]

    var mostUsedAirport: StatisticsRankingItem? {
        airportRankings.first
    }

    var mostUsedAirline: StatisticsRankingItem? {
        airlineRankings.first
    }

    var mostUsedRoute: StatisticsRankingItem? {
        routeRankings.first
    }

    var longestFlight: LongestFlightStatistic? {
        longestFlights.first
    }
}

struct StatisticsViewData: Sendable {
    let availableYears: [Int]
    let snapshot: StatisticsSnapshot
}

struct FlightStatisticsService {
    let metrics: FlightMetricsService

    init(metrics: FlightMetricsService = .standard) {
        self.metrics = metrics
    }

    func viewData(
        _ records: [FlightRecord],
        selectedYear: Int?
    ) -> StatisticsViewData {
        let years = Array(
            Set(records.map {
                FlightStatisticsCalendar.year(for: $0.flightDate)
            })
        ).sorted(by: >)
        return StatisticsViewData(
            availableYears: years,
            snapshot: snapshot(
                records,
                filter: selectedYear.map(StatisticsFilter.year) ?? .all
            )
        )
    }

    func snapshot(
        _ records: [FlightRecord],
        filter: StatisticsFilter = .all
    ) -> StatisticsSnapshot {
        let filteredRecords = records.filter {
            filter.includes($0.flightDate)
        }
        let measurements = filteredRecords.map {
            Measurement(
                record: $0,
                distanceKilometers: metrics.distanceKilometers(for: $0),
                durationMinutes: metrics.durationMinutes(for: $0)
            )
        }
        let totals = MetricTotals(measurements)
        let airportRankings = makeAirportRankings(filteredRecords)
        let locations = FlightLocationResolver(records: filteredRecords)

        return StatisticsSnapshot(
            totalFlightCount: filteredRecords.count,
            totalDistanceKilometers: totals.totalDistanceKilometers,
            measuredDistanceFlightCount: totals.measuredDistanceFlightCount,
            missingDistanceFlightCount: totals.missingDistanceFlightCount,
            totalDurationMinutes: totals.totalDurationMinutes,
            measuredDurationFlightCount: totals.measuredDurationFlightCount,
            missingDurationFlightCount: totals.missingDurationFlightCount,
            uniqueAirportCount: Set(
                airportRankings
                    .map(\.id)
                    .filter { $0 != Self.unknownAirportID }
            ).count,
            uniqueCityCount: uniqueCities(
                in: filteredRecords,
                locations: locations
            ).count,
            uniqueCountryCount: uniqueCountries(
                in: filteredRecords,
                locations: locations
            ).count,
            domesticFlightCount: filteredRecords.count {
                classification(of: $0) == .domestic
            },
            internationalFlightCount: filteredRecords.count {
                classification(of: $0) == .international
            },
            unknownClassificationFlightCount: filteredRecords.count {
                classification(of: $0) == .unknown
            },
            airportRankings: airportRankings,
            airlineRankings: makeAirlineRankings(filteredRecords),
            routeRankings: makeRouteRankings(filteredRecords),
            longestFlights: makeLongestFlights(measurements),
            yearlyTrend: makeYearlyTrend(measurements),
            monthlyTrend: makeMonthlyTrend(
                measurements,
                selectedYear: filter.selectedYear
            )
        )
    }

    private func makeAirportRankings(
        _ records: [FlightRecord]
    ) -> [StatisticsRankingItem] {
        var accumulators: [String: RankingAccumulator] = [:]
        for record in records {
            addAirport(
                iata: record.departureAirportIATA,
                name: record.departureAirportName,
                to: &accumulators
            )
            addAirport(
                iata: record.arrivalAirportIATA,
                name: record.arrivalAirportName,
                to: &accumulators
            )
        }
        return sortedRankings(
            accumulators.map { id, accumulator in
                StatisticsRankingItem(
                    id: id,
                    label: accumulator.preferredLabel,
                    count: accumulator.count
                )
            },
            unknownID: Self.unknownAirportID
        )
    }

    private func addAirport(
        iata: String,
        name: String,
        to accumulators: inout [String: RankingAccumulator]
    ) {
        let code = FlightRecordNormalization.code(iata)
        let id = code.isEmpty ? Self.unknownAirportID : code
        let airportName = Self.trimmed(name)
        let label: String
        if code.isEmpty {
            label = "未知机场"
        } else if airportName.isEmpty {
            label = code
        } else {
            label = "\(code) · \(airportName)"
        }
        accumulators[id, default: RankingAccumulator()].add(label: label)
    }

    private func makeAirlineRankings(
        _ records: [FlightRecord]
    ) -> [StatisticsRankingItem] {
        var accumulators: [String: AirlineAccumulator] = [:]
        for record in records {
            let code = FlightRecordNormalization.code(record.airlineCode)
            let name = Self.trimmed(record.airlineName)
            let id: String
            if !code.isEmpty {
                id = code
            } else if !name.isEmpty {
                id = "name:\(Self.folded(name))"
            } else {
                id = Self.unknownAirlineID
            }
            accumulators[id, default: AirlineAccumulator()].add(
                code: code,
                name: name
            )
        }

        let rankings = accumulators.map { id, accumulator in
            StatisticsRankingItem(
                id: id,
                label: accumulator.label(id: id),
                count: accumulator.count
            )
        }
        return sortedRankings(
            rankings,
            unknownID: Self.unknownAirlineID
        )
    }

    private func makeRouteRankings(
        _ records: [FlightRecord]
    ) -> [StatisticsRankingItem] {
        let rankings = RouteAggregator(metrics: metrics)
            .aggregate(records)
            .map {
                StatisticsRankingItem(
                    id: $0.id,
                    label: $0.displayName,
                    count: $0.flightCount
                )
            }
        return rankings.sorted(by: Self.routeRankingComesFirst)
    }

    private func makeLongestFlights(
        _ measurements: [Measurement]
    ) -> [LongestFlightStatistic] {
        measurements
            .compactMap { measurement -> LongestFlightStatistic? in
                guard let distance = measurement.distanceKilometers else {
                    return nil
                }
                let record = measurement.record
                return LongestFlightStatistic(
                    id: record.id,
                    flightNumber: record.flightNumber,
                    route: "\(record.departureAirportIATA) → \(record.arrivalAirportIATA)",
                    airline: Self.airlineDescription(record),
                    flightDate: record.flightDate,
                    distanceKilometers: distance,
                    durationMinutes: measurement.durationMinutes
                )
            }
            .sorted(by: Self.longestFlightComesFirst)
    }

    private func makeYearlyTrend(
        _ measurements: [Measurement]
    ) -> [YearlyStatisticsTrend] {
        Dictionary(grouping: measurements) {
            FlightStatisticsCalendar.year(for: $0.record.flightDate)
        }
        .map { year, bucket in
            let totals = MetricTotals(bucket)
            return YearlyStatisticsTrend(
                year: year,
                flightCount: bucket.count,
                totalDistanceKilometers: totals.totalDistanceKilometers,
                measuredDistanceFlightCount: totals.measuredDistanceFlightCount,
                missingDistanceFlightCount: totals.missingDistanceFlightCount,
                totalDurationMinutes: totals.totalDurationMinutes,
                measuredDurationFlightCount: totals.measuredDurationFlightCount,
                missingDurationFlightCount: totals.missingDurationFlightCount
            )
        }
        .sorted { $0.year < $1.year }
    }

    private func makeMonthlyTrend(
        _ measurements: [Measurement],
        selectedYear: Int?
    ) -> [MonthlyStatisticsTrend] {
        let grouped = Dictionary(grouping: measurements) {
            FlightStatisticsCalendar.month(for: $0.record.flightDate)
        }
        let months: [StatisticsMonth]
        if let selectedYear {
            months = (1...12).map {
                StatisticsMonth(year: selectedYear, month: $0)
            }
        } else {
            months = grouped.keys.sorted()
        }

        return months.map { month in
            let bucket = grouped[month] ?? []
            let totals = MetricTotals(bucket)
            return MonthlyStatisticsTrend(
                month: month,
                flightCount: bucket.count,
                totalDistanceKilometers: totals.totalDistanceKilometers,
                measuredDistanceFlightCount: totals.measuredDistanceFlightCount,
                missingDistanceFlightCount: totals.missingDistanceFlightCount,
                totalDurationMinutes: totals.totalDurationMinutes,
                measuredDurationFlightCount: totals.measuredDurationFlightCount,
                missingDurationFlightCount: totals.missingDurationFlightCount
            )
        }
    }

    private func uniqueCities(
        in records: [FlightRecord],
        locations: FlightLocationResolver
    ) -> Set<String> {
        var values: Set<String> = []
        for record in records {
            addCity(
                record.departureCity,
                countryCode: record.departureCountryCode,
                country: record.departureCountry,
                locations: locations,
                to: &values
            )
            addCity(
                record.arrivalCity,
                countryCode: record.arrivalCountryCode,
                country: record.arrivalCountry,
                locations: locations,
                to: &values
            )
        }
        return values
    }

    private func addCity(
        _ city: String,
        countryCode: String,
        country: String,
        locations: FlightLocationResolver,
        to values: inout Set<String>
    ) {
        if let value = locations.city(
            city: city,
            countryCode: countryCode,
            countryName: country
        ) {
            values.insert(value.id)
        }
    }

    private func uniqueCountries(
        in records: [FlightRecord],
        locations: FlightLocationResolver
    ) -> Set<String> {
        var values: Set<String> = []
        for record in records {
            for (code, name) in [
                (record.departureCountryCode, record.departureCountry),
                (record.arrivalCountryCode, record.arrivalCountry),
            ] {
                if let value = locations.country(
                    countryCode: code,
                    countryName: name
                ) {
                    values.insert(value.id)
                }
            }
        }
        return values
    }

    private func classification(
        of record: FlightRecord
    ) -> FlightClassification {
        guard
            let departure = Self.isoCountryCode(
                record.departureCountryCode
            ),
            let arrival = Self.isoCountryCode(record.arrivalCountryCode)
        else {
            return .unknown
        }
        return departure == arrival ? .domestic : .international
    }

    private func sortedRankings(
        _ rankings: [StatisticsRankingItem],
        unknownID: String
    ) -> [StatisticsRankingItem] {
        rankings.sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            let lhsIsUnknown = lhs.id == unknownID
            let rhsIsUnknown = rhs.id == unknownID
            if lhsIsUnknown != rhsIsUnknown {
                return !lhsIsUnknown
            }
            return Self.rankingComesFirst(lhs, rhs)
        }
    }

    private static func rankingComesFirst(
        _ lhs: StatisticsRankingItem,
        _ rhs: StatisticsRankingItem
    ) -> Bool {
        if lhs.count != rhs.count {
            return lhs.count > rhs.count
        }
        let lhsLabel = folded(lhs.label)
        let rhsLabel = folded(rhs.label)
        if lhsLabel != rhsLabel {
            return lhsLabel < rhsLabel
        }
        return lhs.id < rhs.id
    }

    private static func routeRankingComesFirst(
        _ lhs: StatisticsRankingItem,
        _ rhs: StatisticsRankingItem
    ) -> Bool {
        if lhs.count != rhs.count {
            return lhs.count > rhs.count
        }
        let lhsIsUnknown = lhs.id.split(separator: "-").contains("未知")
        let rhsIsUnknown = rhs.id.split(separator: "-").contains("未知")
        if lhsIsUnknown != rhsIsUnknown {
            return !lhsIsUnknown
        }
        return rankingComesFirst(lhs, rhs)
    }

    private static func longestFlightComesFirst(
        _ lhs: LongestFlightStatistic,
        _ rhs: LongestFlightStatistic
    ) -> Bool {
        if lhs.distanceKilometers != rhs.distanceKilometers {
            return lhs.distanceKilometers > rhs.distanceKilometers
        }
        if lhs.flightDate != rhs.flightDate {
            return lhs.flightDate > rhs.flightDate
        }
        if lhs.flightNumber != rhs.flightNumber {
            return lhs.flightNumber < rhs.flightNumber
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func airlineDescription(
        _ record: FlightRecord
    ) -> String {
        let code = FlightRecordNormalization.code(record.airlineCode)
        let name = trimmed(record.airlineName)
        return switch (code.isEmpty, name.isEmpty) {
        case (false, false): "\(code) · \(name)"
        case (false, true): code
        case (true, false): name
        case (true, true): "未知航司"
        }
    }

    private static func isoCountryCode(_ value: String) -> String? {
        let code = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard
            code.unicodeScalars.count == 2,
            code.unicodeScalars.allSatisfy({
                CharacterSet.uppercaseLetters.contains($0)
                    && $0.isASCII
            })
        else {
            return nil
        }
        return code
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func folded(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

    private static let unknownAirportID = "unknown-airport"
    private static let unknownAirlineID = "unknown-airline"

}

private enum FlightClassification {
    case domestic
    case international
    case unknown
}

private struct Measurement {
    let record: FlightRecord
    let distanceKilometers: Double?
    let durationMinutes: Int?
}

private struct MetricTotals {
    let totalDistanceKilometers: Double?
    let measuredDistanceFlightCount: Int
    let missingDistanceFlightCount: Int
    let totalDurationMinutes: Int?
    let measuredDurationFlightCount: Int
    let missingDurationFlightCount: Int

    init(_ measurements: [Measurement]) {
        let distances = measurements.compactMap(\.distanceKilometers)
        totalDistanceKilometers = distances.isEmpty
            ? nil
            : distances.reduce(0, +)
        measuredDistanceFlightCount = distances.count
        missingDistanceFlightCount = measurements.count - distances.count

        let durations = measurements.compactMap(\.durationMinutes)
        totalDurationMinutes = durations.isEmpty
            ? nil
            : durations.reduce(0, +)
        measuredDurationFlightCount = durations.count
        missingDurationFlightCount = measurements.count - durations.count
    }
}

private struct RankingAccumulator {
    private(set) var count = 0
    private var labels: Set<String> = []

    mutating func add(label: String) {
        count += 1
        labels.insert(label)
    }

    var preferredLabel: String {
        labels.sorted {
            let lhs = $0.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            let rhs = $1.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            return (lhs, $0) < (rhs, $1)
        }.first ?? ""
    }
}

private struct AirlineAccumulator {
    private(set) var count = 0
    private var codes: Set<String> = []
    private var names: Set<String> = []

    mutating func add(code: String, name: String) {
        count += 1
        if !code.isEmpty {
            codes.insert(code)
        }
        if !name.isEmpty {
            names.insert(name)
        }
    }

    func label(id: String) -> String {
        if id == "unknown-airline" {
            return "未知航司"
        }
        let code = codes.sorted().first ?? ""
        let name = names.sorted {
            let lhs = $0.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            let rhs = $1.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            return (lhs, $0) < (rhs, $1)
        }.first ?? ""

        return switch (code.isEmpty, name.isEmpty) {
        case (false, false): "\(code) · \(name)"
        case (false, true): code
        case (true, false): name
        case (true, true): "未知航司"
        }
    }
}

private enum FlightStatisticsCalendar {
    static func year(for date: Date) -> Int {
        calendar.component(.year, from: date)
    }

    static func month(for date: Date) -> StatisticsMonth {
        StatisticsMonth(
            year: calendar.component(.year, from: date),
            month: calendar.component(.month, from: date)
        )
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
