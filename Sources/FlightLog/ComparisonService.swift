import Foundation

struct ProfileDataset {
    let profileID: UUID
    let name: String
    let color: ProfileComparisonColor
    let records: [FlightRecord]
}

enum ComparisonServiceError: Error, Equatable {
    case tooFewProfiles(actual: Int)
    case tooManyProfiles(actual: Int)
    case duplicateProfileID(UUID)
    case ownerProfileMismatch(
        recordID: UUID,
        expected: UUID,
        actual: UUID?
    )
}

extension ComparisonServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .tooFewProfiles:
            "对比至少需要两位用户。"
        case .tooManyProfiles:
            "一次最多对比四位用户。"
        case .duplicateProfileID:
            "所选用户包含重复项。"
        case .ownerProfileMismatch:
            "航班所属用户与对比资料不一致。"
        }
    }
}

enum CombinedStatisticsScope: Equatable, Sendable {
    case selectedProfilesTotal
}

struct ProfileComparisonSnapshot: Equatable, Sendable {
    let profileID: UUID
    let name: String
    let color: ProfileComparisonColor
    let statistics: StatisticsSnapshot
}

struct CombinedStatisticsSnapshot: Equatable, Sendable {
    let scope: CombinedStatisticsScope
    let snapshot: StatisticsSnapshot
}

struct ProfileFlightRecords: Equatable, Sendable {
    let profileID: UUID
    let records: [ComparisonRecordSnapshot]
}

struct SharedFlightGroup: Equatable, Sendable {
    let key: FlightBusinessKey
    let recordsByProfile: [ProfileFlightRecords]
}

struct ProfileRouteComparison: Equatable, Sendable {
    let profileID: UUID
    let flightCount: Int
    let totalDistanceKilometers: Double?
    let measuredDistanceFlightCount: Int
    let missingDistanceFlightCount: Int
    let flights: [ComparisonRecordSnapshot]
}

struct SharedRouteComparison: Equatable, Sendable {
    let id: String
    let airportA: AirportSnapshot
    let airportB: AirportSnapshot
    let profiles: [ProfileRouteComparison]

    var flightCount: Int {
        profiles.reduce(0) { $0 + $1.flightCount }
    }

    var totalDistanceKilometers: Double? {
        let values = profiles.compactMap(\.totalDistanceKilometers)
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var measuredDistanceFlightCount: Int {
        profiles.reduce(0) { $0 + $1.measuredDistanceFlightCount }
    }

    var missingDistanceFlightCount: Int {
        profiles.reduce(0) { $0 + $1.missingDistanceFlightCount }
    }

    var hasValidGeometry: Bool {
        airportA.coordinate.isValid
            && airportB.coordinate.isValid
            && airportA.coordinate != airportB.coordinate
    }
}

struct ComparisonOverlayRoute: Equatable, Sendable {
    let id: String
    let airportA: AirportSnapshot
    let airportB: AirportSnapshot
    let participantIDs: [UUID]
    let participantCount: Int
    let selectedProfileCount: Int
    let profiles: [ProfileRouteComparison]

    var participation: ComparisonRouteParticipation {
        .classify(
            participantIDs: participantIDs,
            selectedProfileCount: selectedProfileCount
        )
    }

    var isSharedByAll: Bool {
        if case .sharedByAll = participation { return true }
        return false
    }

    var zOrder: Int { participation.zOrder }
}

struct ProfileVisitCount: Equatable, Sendable {
    let profileID: UUID
    let count: Int
}

struct SharedLocationComparison: Equatable, Sendable {
    let id: String
    let label: String
    let combinedVisitCount: Int
    let counts: [ProfileVisitCount]
}

struct ComparisonYearPoint: Equatable, Sendable {
    let year: Int
    let flightCount: Int
    let totalDistanceKilometers: Double?
    let measuredDistanceFlightCount: Int
    let missingDistanceFlightCount: Int
    let totalDurationMinutes: Int?
    let measuredDurationFlightCount: Int
    let missingDurationFlightCount: Int
}

struct ComparisonMonthPoint: Equatable, Sendable {
    let month: StatisticsMonth
    let flightCount: Int
    let totalDistanceKilometers: Double?
    let measuredDistanceFlightCount: Int
    let missingDistanceFlightCount: Int
    let totalDurationMinutes: Int?
    let measuredDurationFlightCount: Int
    let missingDurationFlightCount: Int
}

struct ProfileYearlySeries: Equatable, Sendable {
    let profileID: UUID
    let points: [ComparisonYearPoint]
}

struct ProfileMonthlySeries: Equatable, Sendable {
    let profileID: UUID
    let points: [ComparisonMonthPoint]
}

struct ComparisonSummaryMetric: Equatable, Sendable {
    let profileID: UUID
    let profileName: String
    let color: ProfileComparisonColor
    let flightCount: Int
    let totalDistanceKilometers: Double?
    let totalDurationMinutes: Int?
}

struct ComparisonSharedCounts: Equatable, Sendable {
    let flightCount: Int
    let routeCount: Int
    let airportCount: Int
    let cityCount: Int
    let countryCount: Int
}

struct ComparisonLegendItem: Equatable, Sendable {
    let profileID: UUID
    let profileName: String
    let color: ProfileComparisonColor
}

struct ComparisonPresentation: Equatable, Sendable {
    let profiles: [ProfileComparisonSnapshot]
    let combinedStatistics: CombinedStatisticsSnapshot
    let availableYears: [Int]
    let sharedFlights: [SharedFlightGroup]
    let sharedRoutes: [SharedRouteComparison]
    let overlayRoutes: [ComparisonOverlayRoute]
    let sharedAirports: [SharedLocationComparison]
    let sharedCities: [SharedLocationComparison]
    let sharedCountries: [SharedLocationComparison]
    let yearlySeries: [ProfileYearlySeries]
    let monthlySeries: [ProfileMonthlySeries]
    let summaryMetrics: [ComparisonSummaryMetric]
    let sharedCounts: ComparisonSharedCounts
    let legend: [ComparisonLegendItem]
}

struct ComparisonService {
    private let statistics: FlightStatisticsService
    private let routes: RouteAggregator

    init(metrics: FlightMetricsService = .standard) {
        statistics = FlightStatisticsService(metrics: metrics)
        routes = RouteAggregator(metrics: metrics)
    }

    func compare(
        _ datasets: [ProfileDataset],
        selectedYear: Int? = nil
    ) throws -> ComparisonPresentation {
        try validate(datasets)
        try Task.checkCancellation()

        var availableYearSet = Set<Int>()
        for dataset in datasets {
            for (index, record) in dataset.records.enumerated() {
                try Self.cancellationCheckpoint(index)
                availableYearSet.insert(Self.year(record.flightDate))
            }
        }
        let availableYears = availableYearSet.sorted(by: >)
        var filtered: [ProfileDataset] = []
        for dataset in datasets {
            try Task.checkCancellation()
            let filteredRecords: [FlightRecord]
            if let selectedYear {
                filteredRecords = try dataset.records.enumerated().compactMap {
                    index,
                    record in
                    try Self.cancellationCheckpoint(index)
                    return Self.year(record.flightDate) == selectedYear
                        ? record
                        : nil
                }
            } else {
                filteredRecords = dataset.records
            }
            filtered.append(ProfileDataset(
                profileID: dataset.profileID,
                name: dataset.name,
                color: dataset.color,
                records: filteredRecords
            ))
        }
        var snapshots: [ProfileComparisonSnapshot] = []
        for dataset in filtered {
            try Task.checkCancellation()
            snapshots.append(ProfileComparisonSnapshot(
                profileID: dataset.profileID,
                name: dataset.name,
                color: dataset.color,
                statistics: statistics.snapshot(dataset.records)
            ))
        }
        try Task.checkCancellation()
        let allRecords = filtered.flatMap(\.records)
        let sharedFlights = try makeSharedFlights(filtered)
        try Task.checkCancellation()
        let routeData = try makeRoutes(filtered)
        try Task.checkCancellation()
        let locations = try makeLocations(filtered)
        try Task.checkCancellation()
        let yearlySeries = try makeYearlySeries(
            datasets: datasets,
            years: selectedYear.map { [$0] } ?? availableYears
        )
        let monthlySeries = try makeMonthlySeries(
            datasets: filtered,
            selectedYear: selectedYear
        )
        let summary = snapshots.map {
            ComparisonSummaryMetric(
                profileID: $0.profileID,
                profileName: $0.name,
                color: $0.color,
                flightCount: $0.statistics.totalFlightCount,
                totalDistanceKilometers:
                    $0.statistics.totalDistanceKilometers,
                totalDurationMinutes: $0.statistics.totalDurationMinutes
            )
        }

        return ComparisonPresentation(
            profiles: snapshots,
            combinedStatistics: CombinedStatisticsSnapshot(
                scope: .selectedProfilesTotal,
                snapshot: statistics.snapshot(allRecords)
            ),
            availableYears: availableYears,
            sharedFlights: sharedFlights,
            sharedRoutes: routeData.shared,
            overlayRoutes: routeData.overlays,
            sharedAirports: locations.airports,
            sharedCities: locations.cities,
            sharedCountries: locations.countries,
            yearlySeries: yearlySeries,
            monthlySeries: monthlySeries,
            summaryMetrics: summary,
            sharedCounts: ComparisonSharedCounts(
                flightCount: sharedFlights.count,
                routeCount: routeData.shared.count,
                airportCount: locations.airports.count,
                cityCount: locations.cities.count,
                countryCount: locations.countries.count
            ),
            legend: filtered.map {
                ComparisonLegendItem(
                    profileID: $0.profileID,
                    profileName: $0.name,
                    color: $0.color
                )
            }
        )
    }

    func compareSnapshots(
        _ datasets: [ProfileSnapshotDataset],
        selectedYear: Int? = nil
    ) throws -> ComparisonPresentation {
        try Task.checkCancellation()
        var materialized: [ProfileDataset] = []
        for dataset in datasets {
            var records: [FlightRecord] = []
            records.reserveCapacity(dataset.records.count)
            for (index, snapshot) in dataset.records.enumerated() {
                try Self.cancellationCheckpoint(index)
                records.append(snapshot.materialized())
            }
            materialized.append(ProfileDataset(
                    profileID: dataset.profileID,
                    name: dataset.name,
                    color: dataset.color,
                    records: records
            ))
        }
        return try compare(
            materialized,
            selectedYear: selectedYear
        )
    }

    private func validate(_ datasets: [ProfileDataset]) throws {
        guard datasets.count >= 2 else {
            throw ComparisonServiceError.tooFewProfiles(actual: datasets.count)
        }
        guard datasets.count <= 4 else {
            throw ComparisonServiceError.tooManyProfiles(actual: datasets.count)
        }
        var seen = Set<UUID>()
        for dataset in datasets {
            try Task.checkCancellation()
            guard seen.insert(dataset.profileID).inserted else {
                throw ComparisonServiceError.duplicateProfileID(
                    dataset.profileID
                )
            }
            for (index, record) in dataset.records.enumerated() {
                try Self.cancellationCheckpoint(index)
                if record.ownerProfileID != dataset.profileID {
                    throw ComparisonServiceError.ownerProfileMismatch(
                        recordID: record.id,
                        expected: dataset.profileID,
                        actual: record.ownerProfileID
                    )
                }
            }
        }
    }

    private func makeSharedFlights(
        _ datasets: [ProfileDataset]
    ) throws -> [SharedFlightGroup] {
        var grouped: [[FlightBusinessKey: [FlightRecord]]] = []
        for dataset in datasets {
            var values: [FlightBusinessKey: [FlightRecord]] = [:]
            for (index, record) in dataset.records.enumerated() {
                try Self.cancellationCheckpoint(index)
                values[FlightBusinessKey(record), default: []].append(record)
            }
            for key in values.keys {
                try Task.checkCancellation()
                values[key]?.sort(by: Self.flightComesFirst)
            }
            grouped.append(values)
        }
        guard let first = grouped.first else { return [] }
        let sharedKeys = grouped.dropFirst().reduce(Set(first.keys)) {
            $0.intersection($1.keys)
        }
        var output: [SharedFlightGroup] = []
        for (index, key) in sharedKeys.sorted(
            by: Self.businessKeyComesFirst
        ).enumerated() {
            try Self.cancellationCheckpoint(index)
            output.append(
            SharedFlightGroup(
                key: key,
                recordsByProfile: zip(datasets, grouped).map {
                    ProfileFlightRecords(
                        profileID: $0.profileID,
                        records: ($1[key] ?? []).map(
                            ComparisonRecordSnapshot.init
                        )
                    )
                }
            )
            )
        }
        return output
    }

    private func makeRoutes(
        _ datasets: [ProfileDataset]
    ) throws -> (
        shared: [SharedRouteComparison],
        overlays: [ComparisonOverlayRoute]
    ) {
        var aggregates: [[String: RouteAggregate]] = []
        for dataset in datasets {
            try Task.checkCancellation()
            aggregates.append(Dictionary(
                uniqueKeysWithValues: try routes
                    .aggregateCheckingCancellation(dataset.records).map {
                    ($0.id, $0)
                }
            ))
        }
        guard let first = aggregates.first else { return ([], []) }
        let allIDs = aggregates.reduce(into: Set<String>()) {
            $0.formUnion($1.keys)
        }
        let sharedIDs = aggregates.dropFirst().reduce(Set(first.keys)) {
            $0.intersection($1.keys)
        }

        var shared: [SharedRouteComparison] = []
        for (index, id) in sharedIDs.sorted().enumerated() {
            try Self.cancellationCheckpoint(index)
            let values = aggregates.compactMap { $0[id] }
            guard values.count == datasets.count,
                  let representative = values.first(where: \.hasValidGeometry)
                    ?? values.first
            else {
                continue
            }
            shared.append(SharedRouteComparison(
                id: id,
                airportA: representative.airportA,
                airportB: representative.airportB,
                profiles: zip(datasets, values).map { dataset, route in
                    ProfileRouteComparison(
                        profileID: dataset.profileID,
                        flightCount: route.flightCount,
                        totalDistanceKilometers:
                            route.totalDistanceKilometers,
                        measuredDistanceFlightCount:
                            route.measuredDistanceFlightCount,
                        missingDistanceFlightCount:
                            route.missingDistanceFlightCount,
                        flights: route.flights.map(
                            ComparisonRecordSnapshot.init
                        )
                    )
                }
            ))
        }

        var overlays: [ComparisonOverlayRoute] = []
        for (index, id) in allIDs.sorted().enumerated() {
            try Self.cancellationCheckpoint(index)
            let participants = zip(datasets, aggregates).compactMap {
                $1[id] == nil ? nil : $0.profileID
            }
            let values = aggregates.compactMap { $0[id] }
            guard let representative = values.first(where: \.hasValidGeometry)
                    ?? values.first
            else {
                continue
            }
            let profileRoutes = zip(datasets, aggregates).compactMap {
                dataset,
                aggregate -> ProfileRouteComparison? in
                guard let route = aggregate[id] else { return nil }
                return ProfileRouteComparison(
                    profileID: dataset.profileID,
                    flightCount: route.flightCount,
                    totalDistanceKilometers: route.totalDistanceKilometers,
                    measuredDistanceFlightCount:
                        route.measuredDistanceFlightCount,
                    missingDistanceFlightCount:
                        route.missingDistanceFlightCount,
                    flights: route.flights.map(ComparisonRecordSnapshot.init)
                )
            }
            overlays.append(ComparisonOverlayRoute(
                id: id,
                airportA: representative.airportA,
                airportB: representative.airportB,
                participantIDs: participants,
                participantCount: participants.count,
                selectedProfileCount: datasets.count,
                profiles: profileRoutes
            ))
        }
        return (shared, overlays)
    }

    private func makeLocations(
        _ datasets: [ProfileDataset]
    ) throws -> (
        airports: [SharedLocationComparison],
        cities: [SharedLocationComparison],
        countries: [SharedLocationComparison]
    ) {
        let resolver = FlightLocationResolver(
            records: datasets.flatMap(\.records)
        )
        var airports: [[String: VisitAccumulator]] = []
        var cities: [[String: VisitAccumulator]] = []
        var countries: [[String: VisitAccumulator]] = []

        for dataset in datasets {
            try Task.checkCancellation()
            var profileAirports: [String: VisitAccumulator] = [:]
            var profileCities: [String: VisitAccumulator] = [:]
            var profileCountries: [String: VisitAccumulator] = [:]
            for (index, record) in dataset.records.enumerated() {
                try Self.cancellationCheckpoint(index)
                for endpoint in Self.endpoints(record) {
                    let iata = FlightRecordNormalization.code(endpoint.iata)
                    if Self.isValidIATA(iata) {
                        profileAirports[iata, default: VisitAccumulator()]
                            .add(label: iata)
                    }
                    if let city = resolver.city(
                        city: endpoint.city,
                        countryCode: endpoint.countryCode,
                        countryName: endpoint.country
                    ), !city.id.hasPrefix("unknown-country|") {
                        profileCities[city.id, default: VisitAccumulator()]
                            .add(label: city.label)
                    }
                    if let country = resolver.country(
                        countryCode: endpoint.countryCode,
                        countryName: endpoint.country
                    ) {
                        profileCountries[
                            country.id,
                            default: VisitAccumulator()
                        ].add(label: country.label)
                    }
                }
            }
            airports.append(profileAirports)
            cities.append(profileCities)
            countries.append(profileCountries)
        }
        return (
            try makeSharedLocations(airports, datasets: datasets),
            try makeSharedLocations(cities, datasets: datasets),
            try makeSharedLocations(countries, datasets: datasets)
        )
    }

    private func makeSharedLocations(
        _ values: [[String: VisitAccumulator]],
        datasets: [ProfileDataset]
    ) throws -> [SharedLocationComparison] {
        guard let first = values.first else { return [] }
        let sharedIDs = values.dropFirst().reduce(Set(first.keys)) {
            $0.intersection($1.keys)
        }
        var output: [SharedLocationComparison] = []
        for (index, id) in sharedIDs.enumerated() {
            try Self.cancellationCheckpoint(index)
            let accumulators = values.compactMap { $0[id] }
            output.append(SharedLocationComparison(
                id: id,
                label: accumulators.map(\.label).sorted(
                    by: Self.labelComesFirst
                ).first ?? id,
                combinedVisitCount: accumulators.reduce(0) {
                    $0 + $1.count
                },
                counts: zip(datasets, accumulators).map {
                    ProfileVisitCount(
                        profileID: $0.profileID,
                        count: $1.count
                    )
                }
            ))
        }
        return output.sorted(by: Self.locationComesFirst)
    }

    private func makeYearlySeries(
        datasets: [ProfileDataset],
        years: [Int]
    ) throws -> [ProfileYearlySeries] {
        var output: [ProfileYearlySeries] = []
        for dataset in datasets {
            var points: [ComparisonYearPoint] = []
            for year in years {
                try Task.checkCancellation()
                let snapshot = statistics.snapshot(
                    dataset.records,
                    filter: .year(year)
                )
                points.append(ComparisonYearPoint(
                    year: year,
                    flightCount: snapshot.totalFlightCount,
                    totalDistanceKilometers:
                        snapshot.totalDistanceKilometers,
                    measuredDistanceFlightCount:
                        snapshot.measuredDistanceFlightCount,
                    missingDistanceFlightCount:
                        snapshot.missingDistanceFlightCount,
                    totalDurationMinutes: snapshot.totalDurationMinutes,
                    measuredDurationFlightCount:
                        snapshot.measuredDurationFlightCount,
                    missingDurationFlightCount:
                        snapshot.missingDurationFlightCount
                ))
            }
            output.append(ProfileYearlySeries(
                profileID: dataset.profileID,
                points: points
            ))
        }
        return output
    }

    private func makeMonthlySeries(
        datasets: [ProfileDataset],
        selectedYear: Int?
    ) throws -> [ProfileMonthlySeries] {
        let months: [StatisticsMonth]
        if let selectedYear {
            months = (1...12).map {
                StatisticsMonth(year: selectedYear, month: $0)
            }
        } else {
            months = Array(Set(datasets.flatMap {
                $0.records.map {
                    Self.month($0.flightDate)
                }
            })).sorted()
        }
        var output: [ProfileMonthlySeries] = []
        for dataset in datasets {
            try Task.checkCancellation()
            let grouped = Dictionary(grouping: dataset.records) {
                Self.month($0.flightDate)
            }
            var points: [ComparisonMonthPoint] = []
            for month in months {
                try Task.checkCancellation()
                let snapshot = statistics.snapshot(grouped[month] ?? [])
                points.append(ComparisonMonthPoint(
                    month: month,
                    flightCount: snapshot.totalFlightCount,
                    totalDistanceKilometers:
                        snapshot.totalDistanceKilometers,
                    measuredDistanceFlightCount:
                        snapshot.measuredDistanceFlightCount,
                    missingDistanceFlightCount:
                        snapshot.missingDistanceFlightCount,
                    totalDurationMinutes: snapshot.totalDurationMinutes,
                    measuredDurationFlightCount:
                        snapshot.measuredDurationFlightCount,
                    missingDurationFlightCount:
                        snapshot.missingDurationFlightCount
                ))
            }
            output.append(ProfileMonthlySeries(
                profileID: dataset.profileID,
                points: points
            ))
        }
        return output
    }

    private static func businessKeyComesFirst(
        _ lhs: FlightBusinessKey,
        _ rhs: FlightBusinessKey
    ) -> Bool {
        if lhs.localDepartureDate != rhs.localDepartureDate {
            return lhs.localDepartureDate > rhs.localDepartureDate
        }
        if lhs.flightNumber != rhs.flightNumber {
            return lhs.flightNumber < rhs.flightNumber
        }
        if lhs.departureIATA != rhs.departureIATA {
            return lhs.departureIATA < rhs.departureIATA
        }
        return lhs.arrivalIATA < rhs.arrivalIATA
    }

    private static func flightComesFirst(
        _ lhs: FlightRecord,
        _ rhs: FlightRecord
    ) -> Bool {
        if lhs.flightDate != rhs.flightDate {
            return lhs.flightDate > rhs.flightDate
        }
        if lhs.departureDate != rhs.departureDate {
            return lhs.departureDate > rhs.departureDate
        }
        if lhs.flightNumber != rhs.flightNumber {
            return lhs.flightNumber < rhs.flightNumber
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func locationComesFirst(
        _ lhs: SharedLocationComparison,
        _ rhs: SharedLocationComparison
    ) -> Bool {
        if lhs.combinedVisitCount != rhs.combinedVisitCount {
            return lhs.combinedVisitCount > rhs.combinedVisitCount
        }
        let lhsLabel = folded(lhs.label)
        let rhsLabel = folded(rhs.label)
        if lhsLabel != rhsLabel {
            return lhsLabel < rhsLabel
        }
        return lhs.id < rhs.id
    }

    private static func labelComesFirst(_ lhs: String, _ rhs: String) -> Bool {
        let lhsFolded = folded(lhs)
        let rhsFolded = folded(rhs)
        return lhsFolded == rhsFolded ? lhs < rhs : lhsFolded < rhsFolded
    }

    private static func folded(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func isValidIATA(_ value: String) -> Bool {
        value.unicodeScalars.count == 3
            && value.unicodeScalars.allSatisfy {
                (65...90).contains($0.value)
            }
    }

    private static func endpoints(_ record: FlightRecord) -> [Endpoint] {
        [
            Endpoint(
                iata: record.departureAirportIATA,
                city: record.departureCity,
                country: record.departureCountry,
                countryCode: record.departureCountryCode
            ),
            Endpoint(
                iata: record.arrivalAirportIATA,
                city: record.arrivalCity,
                country: record.arrivalCountry,
                countryCode: record.arrivalCountryCode
            ),
        ]
    }

    private static func year(_ date: Date) -> Int {
        calendar.component(.year, from: date)
    }

    private static func month(_ date: Date) -> StatisticsMonth {
        StatisticsMonth(
            year: calendar.component(.year, from: date),
            month: calendar.component(.month, from: date)
        )
    }

    private static func cancellationCheckpoint(
        _ index: Int
    ) throws {
        if index.isMultiple(of: 64) {
            try Task.checkCancellation()
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private struct Endpoint {
        let iata: String
        let city: String
        let country: String
        let countryCode: String
    }

    private struct VisitAccumulator {
        private(set) var count = 0
        private var labels: Set<String> = []

        mutating func add(label: String) {
            count += 1
            labels.insert(label)
        }

        var label: String {
            labels.sorted(by: ComparisonService.labelComesFirst).first ?? ""
        }
    }
}
