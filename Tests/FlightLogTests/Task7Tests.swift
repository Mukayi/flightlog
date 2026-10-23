import Foundation
import XCTest
@testable import FlightLog

@MainActor
final class AppCommandStateTests: XCTestCase {
    func testSixNavigationSectionsExposeCommandNumberShortcuts() {
        XCTAssertEqual(
            AppSection.allCases.map(\.keyboardShortcutCharacter),
            ["1", "2", "3", "4", "5", "6"]
        )
    }

    func testNewFlightAndSearchCommandsSelectFlightsAndAdvanceRequests() {
        let state = AppCommandState()

        state.requestNewFlight()

        XCTAssertEqual(state.selection, .flights)
        XCTAssertEqual(state.newFlightRequest, 1)
        XCTAssertEqual(state.focusSearchRequest, 0)

        state.navigate(to: .settings)
        state.requestFlightSearch()

        XCTAssertEqual(state.selection, .flights)
        XCTAssertEqual(state.newFlightRequest, 1)
        XCTAssertEqual(state.focusSearchRequest, 1)
    }

    func testCommandRequestsAreConsumedOnlyOnceAcrossViewRecreation() {
        let state = AppCommandState()

        state.requestNewFlight()
        XCTAssertTrue(state.takeNewFlightRequest())
        XCTAssertFalse(state.takeNewFlightRequest())

        state.requestFlightSearch()
        XCTAssertTrue(state.takeFocusSearchRequest())
        XCTAssertFalse(state.takeFocusSearchRequest())

        state.requestNewFlight()
        XCTAssertTrue(state.takeNewFlightRequest())
    }
}

final class Task7UsabilityLogicTests: XCTestCase {
    func testFlightListEmptyRecoveryCoversAddSearchFilterAndCombinedStates() {
        XCTAssertEqual(
            FlightListEmptyRecovery.resolve(
                hasRecords: false,
                searchText: "PEK",
                filterIsActive: true
            ),
            .addFlight
        )
        XCTAssertEqual(
            FlightListEmptyRecovery.resolve(
                hasRecords: true,
                searchText: "PEK",
                filterIsActive: false
            ),
            .clearSearch
        )
        XCTAssertEqual(
            FlightListEmptyRecovery.resolve(
                hasRecords: true,
                searchText: " ",
                filterIsActive: true
            ),
            .clearFilters
        )
        XCTAssertEqual(
            FlightListEmptyRecovery.resolve(
                hasRecords: true,
                searchText: "PEK",
                filterIsActive: true
            ),
            .clearSearchAndFilters
        )
    }

    func testRouteMapUsesStackedLayoutForNarrowWidth() {
        XCTAssertEqual(RouteMapLayout.mode(forWidth: 719), .stacked)
        XCTAssertEqual(RouteMapLayout.mode(forWidth: 899), .stacked)
        XCTAssertEqual(RouteMapLayout.mode(forWidth: 900), .sideBySide)
        XCTAssertEqual(RouteMapLayout.mode(forWidth: 1_400), .sideBySide)
    }

    func testMissingAirportResourceHasChineseError() {
        XCTAssertEqual(
            AirportRepositoryError.resourceNotFound.localizedDescription,
            "找不到内置机场资料文件。"
        )
    }

    func testMainAppResourceWinsWithoutEvaluatingSwiftPMFallback() throws {
        let appResource = URL(fileURLWithPath: "/tmp/app-airports.json")
        var evaluatedFallback = false

        let resolved = try AirportRepository.resolveResourceURL(
            mainResourceURL: appResource,
            swiftPMFallback: {
                evaluatedFallback = true
                return URL(fileURLWithPath: "/tmp/module-airports.json")
            }
        )

        XCTAssertEqual(resolved, appResource)
        XCTAssertFalse(evaluatedFallback)
    }

    func testSwiftPMResourceIsResolvedLazilyOutsidePackagedApp() throws {
        let moduleResource = URL(fileURLWithPath: "/tmp/module-airports.json")
        var evaluatedFallback = false

        let resolved = try AirportRepository.resolveResourceURL(
            mainResourceURL: nil,
            swiftPMFallback: {
                evaluatedFallback = true
                return moduleResource
            }
        )

        XCTAssertEqual(resolved, moduleResource)
        XCTAssertTrue(evaluatedFallback)
    }
}

final class SampleDataGeneratorTests: XCTestCase {
    func testDefaultSampleIsDeterministicAndCoversRequiredVariety() throws {
        let repository = try AirportRepository()

        let first = try SampleDataGenerator.generate(
            repository: repository,
            existingRecords: [],
            ownerProfileID: UserProfileDefaults.id,
            occupiedRecordIDs: []
        )
        let second = try SampleDataGenerator.generate(
            repository: repository,
            existingRecords: [],
            ownerProfileID: UserProfileDefaults.id,
            occupiedRecordIDs: []
        )

        XCTAssertEqual(first.records.count, SampleDataGenerator.defaultCount)
        XCTAssertEqual(first.skippedDuplicateCount, 0)
        XCTAssertEqual(
            first.records.map(recordSignature),
            second.records.map(recordSignature)
        )

        let years = Set(first.records.map {
            utcCalendar.component(.year, from: $0.flightDate)
        })
        let airlines = Set(first.records.map(\.airlineCode))
        let airports = Set(first.records.flatMap {
            [$0.departureAirportIATA, $0.arrivalAirportIATA]
        })
        let statistics = FlightStatisticsService().snapshot(first.records)

        XCTAssertGreaterThanOrEqual(years.count, 4)
        XCTAssertGreaterThanOrEqual(airlines.count, 4)
        XCTAssertGreaterThanOrEqual(airports.count, 8)
        XCTAssertGreaterThan(statistics.domesticFlightCount, 0)
        XCTAssertGreaterThan(statistics.internationalFlightCount, 0)
        XCTAssertEqual(statistics.unknownClassificationFlightCount, 0)
    }

    func testRepeatedGenerationSkipsEveryExistingBusinessKey() throws {
        let repository = try AirportRepository()
        let first = try SampleDataGenerator.generate(
            repository: repository,
            existingRecords: [],
            ownerProfileID: UserProfileDefaults.id,
            occupiedRecordIDs: []
        )

        let repeated = try SampleDataGenerator.generate(
            repository: repository,
            existingRecords: first.records,
            ownerProfileID: UserProfileDefaults.id,
            occupiedRecordIDs: Set(first.records.map(\.id))
        )

        XCTAssertTrue(repeated.records.isEmpty)
        XCTAssertEqual(
            repeated.skippedDuplicateCount,
            SampleDataGenerator.defaultCount
        )
    }

    func testGenerationSkipsOnlyConflictingExistingBusinessKey() throws {
        let repository = try AirportRepository()
        let baseline = try SampleDataGenerator.generate(
            repository: repository,
            existingRecords: [],
            ownerProfileID: UserProfileDefaults.id,
            occupiedRecordIDs: []
        )
        let existing = try XCTUnwrap(baseline.records.first)

        let result = try SampleDataGenerator.generate(
            repository: repository,
            existingRecords: [existing],
            ownerProfileID: UserProfileDefaults.id,
            occupiedRecordIDs: [existing.id]
        )

        XCTAssertEqual(
            result.records.count,
            SampleDataGenerator.defaultCount - 1
        )
        XCTAssertEqual(result.skippedDuplicateCount, 1)
        XCTAssertFalse(
            result.records.map(businessKey).contains(businessKey(existing))
        )
    }

    func testMissingTemplateAirportsProduceChineseError() {
        XCTAssertThrowsError(
            try SampleDataGenerator.generate(
                repository: AirportRepository(airports: []),
                existingRecords: [],
                ownerProfileID: UserProfileDefaults.id,
                occupiedRecordIDs: []
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("机场"))
            XCTAssertTrue(error.localizedDescription.contains("PEK"))
        }
    }

    private func recordSignature(_ record: FlightRecord) -> String {
        [
            record.id.uuidString,
            record.flightNumber,
            String(record.flightDate.timeIntervalSince1970),
            record.departureAirportIATA,
            record.arrivalAirportIATA,
            String(record.departureDate.timeIntervalSince1970),
            String(record.arrivalDate.timeIntervalSince1970),
        ].joined(separator: "|")
    }

    private func businessKey(_ record: FlightRecord) -> String {
        [
            FlightRecordNormalization.code(record.flightNumber),
            String(
                FlightDateNormalization.canonicalDate(record.flightDate)
                    .timeIntervalSince1970
            ),
            FlightRecordNormalization.code(record.departureAirportIATA),
            FlightRecordNormalization.code(record.arrivalAirportIATA),
        ].joined(separator: "|")
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

final class Task7PerformanceTests: XCTestCase {
    func testOneThousandGeneratedRecordsCoreQueriesAreCorrectAndTimed() throws {
        let repository = try AirportRepository()
        let generation = try SampleDataGenerator.generate(
            count: 1_000,
            repository: repository,
            existingRecords: [],
            ownerProfileID: UserProfileDefaults.id,
            occupiedRecordIDs: []
        )
        let records = generation.records
        for (index, record) in records.enumerated() {
            let routeIndex = index
            record.departureAirportIATA = String(
                format: "D%03d",
                routeIndex
            )
            record.arrivalAirportIATA = String(
                format: "A%03d",
                routeIndex
            )
            record.departureAirportName = "Departure \(routeIndex)"
            record.arrivalAirportName = "Arrival \(routeIndex)"
            record.departureCity = "Departure City \(routeIndex)"
            record.arrivalCity = "Arrival City \(routeIndex)"
            record.departureCountry = "中国"
            record.departureCountryCode = "CN"
            record.arrivalCountry = routeIndex.isMultiple(of: 2)
                ? "中国"
                : "日本"
            record.arrivalCountryCode = routeIndex.isMultiple(of: 2)
                ? "CN"
                : "JP"
            record.departureLatitude = -50 + Double(routeIndex % 100)
            record.departureLongitude = -120 + Double(routeIndex % 200)
            record.arrivalLatitude = record.departureLatitude + 0.2
            record.arrivalLongitude = record.departureLongitude + 0.2
        }

        XCTAssertEqual(records.count, 1_000)
        XCTAssertEqual(generation.skippedDuplicateCount, 0)

        let (listResults, listSeconds) = timed {
            FlightListQuery.apply(
                to: records,
                searchText: "中国国际航空",
                sortOrder: .dateDescending
            )
        }
        XCTAssertFalse(listResults.isEmpty)
        XCTAssertTrue(listResults.allSatisfy { $0.airlineCode == "CA" })
        XCTAssertTrue(
            zip(listResults, listResults.dropFirst()).allSatisfy {
                lhs,
                rhs in
                lhs.flightDate > rhs.flightDate
                    || (
                        lhs.flightDate == rhs.flightDate
                            && lhs.flightNumber <= rhs.flightNumber
                    )
            }
        )

        let (routes, routeSeconds) = timed {
            RouteAggregator().aggregate(records)
        }
        XCTAssertEqual(routes.reduce(0) { $0 + $1.flightCount }, 1_000)
        XCTAssertEqual(routes.count, 1_000)
        XCTAssertTrue(routes.allSatisfy { $0.flightCount == 1 })

        let (sampledPointCount, samplingSeconds) = timed {
            routes.reduce(into: 0) { count, route in
                count += GreatCircleRouteSampler.sampleSegments(
                    from: route.airportA.coordinate,
                    to: route.airportB.coordinate,
                    segmentCount: 96
                ).reduce(0) { $0 + $1.count }
            }
        }
        XCTAssertEqual(sampledPointCount, 97_000)

        let (snapshot, statisticsSeconds) = timed {
            FlightStatisticsService().snapshot(records)
        }
        XCTAssertEqual(snapshot.totalFlightCount, 1_000)
        XCTAssertEqual(
            snapshot.domesticFlightCount + snapshot.internationalFlightCount,
            1_000
        )
        XCTAssertEqual(snapshot.unknownClassificationFlightCount, 0)
        XCTAssertEqual(snapshot.measuredDistanceFlightCount, 1_000)
        XCTAssertEqual(snapshot.measuredDurationFlightCount, 1_000)
        XCTAssertEqual(snapshot.uniqueAirportCount, 2_000)
        XCTAssertEqual(snapshot.uniqueCityCount, 2_000)
        XCTAssertEqual(
            snapshot.routeRankings.reduce(0) { $0 + $1.count },
            1_000
        )
        XCTAssertLessThan(
            routeSeconds + samplingSeconds + statisticsSeconds,
            5
        )

        print(
            String(
                format: "TASK7_PERF list=%.6fs routes=%.6fs sampling=%.6fs statistics=%.6fs totalLogic=%.6fs",
                listSeconds,
                routeSeconds,
                samplingSeconds,
                statisticsSeconds,
                routeSeconds + samplingSeconds + statisticsSeconds
            )
        )
    }

    private func timed<T>(_ operation: () -> T) -> (T, Double) {
        let start = ProcessInfo.processInfo.systemUptime
        let value = operation()
        return (
            value,
            ProcessInfo.processInfo.systemUptime - start
        )
    }
}
