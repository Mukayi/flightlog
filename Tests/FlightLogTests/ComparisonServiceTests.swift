import Foundation
import XCTest
@testable import FlightLog

final class ComparisonServiceTests: XCTestCase {
    private let service = ComparisonService()
    private let aliceID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let bobID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let carolID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    private let daveID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!

    func testValidatesProfileCountUniquenessAndRecordOwnership() {
        XCTAssertThrowsError(try service.compare([dataset(aliceID)])) {
            XCTAssertEqual($0 as? ComparisonServiceError, .tooFewProfiles(actual: 1))
        }
        XCTAssertThrowsError(try service.compare([
            dataset(aliceID), dataset(bobID), dataset(carolID), dataset(daveID),
            dataset(UUID()),
        ])) {
            XCTAssertEqual($0 as? ComparisonServiceError, .tooManyProfiles(actual: 5))
        }
        XCTAssertThrowsError(try service.compare([
            dataset(aliceID), dataset(aliceID),
        ])) {
            XCTAssertEqual($0 as? ComparisonServiceError, .duplicateProfileID(aliceID))
        }

        let foreign = record(owner: bobID, id: 9)
        XCTAssertThrowsError(try service.compare([
            dataset(aliceID, records: [foreign]), dataset(bobID),
        ])) {
            XCTAssertEqual(
                $0 as? ComparisonServiceError,
                .ownerProfileMismatch(
                    recordID: foreign.id,
                    expected: aliceID,
                    actual: bobID
                )
            )
        }
    }

    func testPreservesTwoAndFourProfileInputOrderIncludingEmptyProfiles() throws {
        let two = try service.compare([
            dataset(bobID), dataset(aliceID),
        ])
        XCTAssertEqual(two.profiles.map(\.profileID), [bobID, aliceID])
        XCTAssertEqual(two.profiles.map(\.statistics.totalFlightCount), [0, 0])

        let four = try service.compare([
            dataset(daveID), dataset(bobID), dataset(carolID), dataset(aliceID),
        ])
        XCTAssertEqual(
            four.profiles.map(\.profileID),
            [daveID, bobID, carolID, aliceID]
        )
        XCTAssertEqual(four.legend.map(\.profileID), four.profiles.map(\.profileID))
    }

    func testPersonalSnapshotsRemainIndependentAndCombinedSnapshotIsLabeledTotal() throws {
        let duplicateA = record(owner: aliceID, id: 1, flightNumber: "CA 123")
        let duplicateB = record(owner: aliceID, id: 2, flightNumber: "CA123")
        let bob = record(owner: bobID, id: 3, flightNumber: "CA123")

        let result = try service.compare([
            dataset(aliceID, records: [duplicateA, duplicateB]),
            dataset(bobID, records: [bob]),
        ])

        XCTAssertEqual(result.profiles.map(\.statistics.totalFlightCount), [2, 1])
        XCTAssertEqual(result.combinedStatistics.scope, .selectedProfilesTotal)
        XCTAssertEqual(result.combinedStatistics.snapshot.totalFlightCount, 3)
        XCTAssertEqual(result.sharedFlights.count, 1)
        XCTAssertEqual(
            result.sharedFlights[0].recordsByProfile.map(\.records.count),
            [2, 1]
        )
    }

    func testBusinessKeyMatchesDifferentUUIDsButNotReverseFlight() throws {
        let alice = record(
            owner: aliceID,
            id: 1,
            flightNumber: " ca 123 ",
            date: date(2026, 8, 20),
            departure: pek,
            arrival: yul
        )
        let sameBusiness = record(
            owner: bobID,
            id: 2,
            flightNumber: "CA-123",
            date: date(2026, 8, 20, 12),
            departure: pek,
            arrival: yul
        )
        let reverse = record(
            owner: bobID,
            id: 3,
            flightNumber: "CA123",
            date: date(2026, 8, 20),
            departure: yul,
            arrival: pek
        )

        let key = FlightBusinessKey(alice)
        XCTAssertEqual(key, FlightBusinessKey(sameBusiness))
        XCTAssertNotEqual(key, FlightBusinessKey(reverse))

        let result = try service.compare([
            dataset(aliceID, records: [alice]),
            dataset(bobID, records: [reverse, sameBusiness]),
        ])
        XCTAssertEqual(result.sharedFlights.map(\.key), [key])
        XCTAssertEqual(result.sharedFlights[0].recordsByProfile.map(\.profileID), [
            aliceID, bobID,
        ])
    }

    func testSharedFlightsSortByRecentDateThenFlightNumberAndRoute() throws {
        let olderA = record(
            owner: aliceID, id: 1, flightNumber: "ZZ9",
            date: date(2025, 1, 1), departure: pek, arrival: yul
        )
        let newerZA = record(
            owner: aliceID, id: 2, flightNumber: "ZA1",
            date: date(2026, 1, 1), departure: pek, arrival: yul
        )
        let newerAA = record(
            owner: aliceID, id: 3, flightNumber: "AA1",
            date: date(2026, 1, 1), departure: yul, arrival: pek
        )
        newerAA.departureLocalDateTime = "2026-01-01T01:00:00"
        let alice = [olderA, newerZA, newerAA]
        let bob = alice.enumerated().map { offset, source in
            clone(source, owner: bobID, id: 100 + offset)
        }

        let result = try service.compare([
            dataset(aliceID, records: alice), dataset(bobID, records: bob),
        ])

        XCTAssertEqual(result.sharedFlights.map(\.key.flightNumber), [
            "AA1", "ZA1", "ZZ9",
        ])
    }

    func testReverseRoutesAreSharedAndOverlayRetainsOwnershipAndZOrder() throws {
        let aliceShared = record(
            owner: aliceID, id: 1, flightNumber: "A1",
            departure: pek, arrival: yul
        )
        let aliceOnly = record(
            owner: aliceID, id: 2, flightNumber: "A2",
            departure: pek, arrival: hnd
        )
        let bobShared = record(
            owner: bobID, id: 3, flightNumber: "B1",
            departure: yul, arrival: pek
        )

        let result = try service.compare([
            dataset(aliceID, records: [aliceOnly, aliceShared]),
            dataset(bobID, records: [bobShared]),
        ])

        XCTAssertTrue(result.sharedFlights.isEmpty)
        XCTAssertEqual(result.sharedRoutes.map(\.id), ["PEK-YUL"])
        XCTAssertEqual(result.sharedRoutes[0].profiles.map(\.flightCount), [1, 1])
        XCTAssertTrue(result.sharedRoutes[0].hasValidGeometry)
        XCTAssertEqual(result.overlayRoutes.map(\.id), ["HND-PEK", "PEK-YUL"])
        XCTAssertEqual(result.overlayRoutes[0].participantIDs, [aliceID])
        XCTAssertEqual(result.overlayRoutes[0].participantCount, 1)
        XCTAssertFalse(result.overlayRoutes[0].isSharedByAll)
        XCTAssertEqual(result.overlayRoutes[1].participantIDs, [aliceID, bobID])
        XCTAssertTrue(result.overlayRoutes[1].isSharedByAll)
        XCTAssertLessThan(result.overlayRoutes[0].zOrder, result.overlayRoutes[1].zOrder)
    }

    func testSharedRouteReportsPerProfileDistanceCoverageAndStableFlights() throws {
        let invalid = Airport(
            iata: "PEK", icao: "", name: "Invalid PEK", city: "Beijing",
            country: "China", countryCode: "CN", latitude: 91, longitude: 0,
            timeZoneID: "Asia/Shanghai"
        )
        let aliceNewMissing = record(
            owner: aliceID, id: 2, flightNumber: "A2",
            date: date(2026, 2, 1), departure: invalid, arrival: yul
        )
        let aliceOldMeasured = record(
            owner: aliceID, id: 1, flightNumber: "A1",
            date: date(2026, 1, 1), departure: pek, arrival: yul
        )
        let bob = record(
            owner: bobID, id: 3, flightNumber: "B1",
            date: date(2026, 3, 1), departure: yul, arrival: pek
        )

        let route = try XCTUnwrap(service.compare([
            dataset(aliceID, records: [aliceOldMeasured, aliceNewMissing]),
            dataset(bobID, records: [bob]),
        ]).sharedRoutes.first)

        XCTAssertEqual(route.profiles[0].flights.map(\.id), [
            aliceNewMissing.id, aliceOldMeasured.id,
        ])
        XCTAssertEqual(route.profiles[0].flightCount, 2)
        XCTAssertEqual(route.profiles[0].measuredDistanceFlightCount, 1)
        XCTAssertEqual(route.profiles[0].missingDistanceFlightCount, 1)
        XCTAssertNotNil(route.profiles[0].totalDistanceKilometers)
        XCTAssertTrue(route.hasValidGeometry)
    }

    func testSharedAirportsCitiesCountriesExcludeUnknownAndResolveAliases() throws {
        let alice = record(
            owner: aliceID, id: 1, departure: pek, arrival: yul
        )
        let legacyPEK = Airport(
            iata: "pek", icao: "", name: "Capital", city: "beijing",
            country: "china", countryCode: "", latitude: pek.latitude,
            longitude: pek.longitude, timeZoneID: pek.timeZoneID
        )
        let unknown = Airport(
            iata: "??", icao: "", name: "Unknown", city: "Unknown",
            country: "未知", countryCode: "", latitude: 0, longitude: 0,
            timeZoneID: "Etc/UTC"
        )
        let bob = record(
            owner: bobID, id: 2, departure: legacyPEK, arrival: unknown
        )

        let result = try service.compare([
            dataset(aliceID, records: [alice]),
            dataset(bobID, records: [bob]),
        ])

        XCTAssertEqual(result.sharedAirports.map(\.id), ["PEK"])
        XCTAssertEqual(result.sharedAirports[0].combinedVisitCount, 2)
        XCTAssertEqual(result.sharedAirports[0].counts.map(\.count), [1, 1])
        XCTAssertEqual(result.sharedCities.map(\.label), ["Beijing"])
        XCTAssertEqual(result.sharedCountries.map(\.id), ["iso:CN"])
        XCTAssertFalse(result.sharedCountries.contains { $0.label == "未知" })
    }

    func testLocationOrderingUsesCombinedCountThenLabelAndID() throws {
        let repeatedAlice = [
            record(owner: aliceID, id: 1, departure: pek, arrival: hnd),
            record(owner: aliceID, id: 2, departure: pek, arrival: hnd),
        ]
        let repeatedBob = [
            record(owner: bobID, id: 3, departure: pek, arrival: hnd),
            record(owner: bobID, id: 4, departure: pek, arrival: hnd),
        ]

        let result = try service.compare([
            dataset(aliceID, records: repeatedAlice),
            dataset(bobID, records: repeatedBob),
        ])

        XCTAssertEqual(result.sharedAirports.map(\.id), ["HND", "PEK"])
        XCTAssertEqual(result.sharedAirports.map(\.combinedVisitCount), [4, 4])
    }

    func testYearUnionAndTrendSeriesKeepZeroPointsWithoutInventingMeasurements() throws {
        let missingDistanceAirport = Airport(
            iata: "BAD", icao: "", name: "Bad", city: "Bad City",
            country: "China", countryCode: "CN", latitude: 91, longitude: 0,
            timeZoneID: "Etc/UTC"
        )
        let alice2024 = record(
            owner: aliceID, id: 1, date: date(2024, 2, 1),
            departure: missingDistanceAirport, arrival: yul, validDuration: false
        )
        let bob2026 = record(
            owner: bobID, id: 2, date: date(2026, 3, 1),
            departure: pek, arrival: yul
        )

        let all = try service.compare([
            dataset(aliceID, records: [alice2024]),
            dataset(bobID, records: [bob2026]),
        ])
        XCTAssertEqual(all.availableYears, [2026, 2024])
        XCTAssertEqual(all.yearlySeries.map(\.profileID), [aliceID, bobID])
        XCTAssertEqual(all.yearlySeries[0].points.map(\.flightCount), [0, 1])
        XCTAssertNil(all.yearlySeries[0].points[0].totalDistanceKilometers)
        XCTAssertNil(all.yearlySeries[0].points[1].totalDistanceKilometers)
        XCTAssertEqual(all.yearlySeries[1].points.map(\.flightCount), [1, 0])

        let filtered = try service.compare([
            dataset(aliceID, records: [alice2024]),
            dataset(bobID, records: [bob2026]),
        ], selectedYear: 2024)
        XCTAssertEqual(filtered.profiles.map(\.statistics.totalFlightCount), [1, 0])
        XCTAssertEqual(
            filtered.yearlySeries.map { $0.points.map(\.year) },
            [[2024], [2024]]
        )
        XCTAssertEqual(filtered.monthlySeries[0].points.count, 12)
        XCTAssertEqual(filtered.monthlySeries[1].points.count, 12)
        XCTAssertEqual(filtered.monthlySeries[1].points.map(\.flightCount), Array(repeating: 0, count: 12))
        XCTAssertTrue(filtered.monthlySeries[1].points.allSatisfy {
            $0.totalDistanceKilometers == nil && $0.totalDurationMinutes == nil
        })
        XCTAssertTrue(filtered.sharedRoutes.isEmpty)
        XCTAssertTrue(filtered.sharedAirports.isEmpty)
    }

    func testPresentationMetadataIncludesSummarySharedCountsAndLegend() throws {
        let sharedA = record(owner: aliceID, id: 1)
        let sharedB = clone(sharedA, owner: bobID, id: 2)

        let result = try service.compare([
            dataset(aliceID, color: .orange, records: [sharedA]),
            dataset(bobID, color: .purple, records: [sharedB]),
        ])

        XCTAssertEqual(result.summaryMetrics.map(\.profileID), [aliceID, bobID])
        XCTAssertEqual(result.sharedCounts.flightCount, 1)
        XCTAssertEqual(result.sharedCounts.routeCount, 1)
        XCTAssertEqual(result.legend.map(\.color), [.orange, .purple])
        XCTAssertEqual(result.legend.map(\.profileName), ["Alice", "Bob"])
    }

    func testFourProfilesRequireEveryParticipantForSharedIntersections() throws {
        let commonA = record(owner: aliceID, id: 1)
        let commonB = clone(commonA, owner: bobID, id: 2)
        let commonC = clone(commonA, owner: carolID, id: 3)
        let daveDifferent = record(
            owner: daveID, id: 4, flightNumber: "OTHER",
            departure: pek, arrival: yul
        )

        let result = try service.compare([
            dataset(aliceID, records: [commonA]),
            dataset(bobID, records: [commonB]),
            dataset(carolID, records: [commonC]),
            dataset(daveID, records: [daveDifferent]),
        ])

        XCTAssertTrue(result.sharedFlights.isEmpty)
        XCTAssertEqual(result.sharedRoutes.map(\.id), ["PEK-YUL"])
        XCTAssertEqual(result.sharedAirports.map(\.id), ["PEK", "YUL"])
    }

    func testOverlayClassifiesThreeOfFourAsPartialWithMiddleZOrder() throws {
        let common = [
            record(owner: aliceID, id: 1, departure: pek, arrival: yul),
            record(owner: bobID, id: 2, departure: yul, arrival: pek),
            record(owner: carolID, id: 3, departure: pek, arrival: yul),
        ]
        let aliceOnly = record(
            owner: aliceID,
            id: 4,
            departure: pek,
            arrival: hnd
        )

        let result = try service.compare([
            dataset(aliceID, records: [common[0], aliceOnly]),
            dataset(bobID, records: [common[1]]),
            dataset(carolID, records: [common[2]]),
            dataset(daveID),
        ])

        let exclusive = try XCTUnwrap(
            result.overlayRoutes.first { $0.id == "HND-PEK" }
        )
        let partial = try XCTUnwrap(
            result.overlayRoutes.first { $0.id == "PEK-YUL" }
        )
        XCTAssertEqual(
            exclusive.participation,
            .exclusive(profileID: aliceID)
        )
        XCTAssertEqual(
            partial.participation,
            .sharedBySome(participantCount: 3, selectedProfileCount: 4)
        )
        XCTAssertLessThan(exclusive.zOrder, partial.zOrder)
        XCTAssertLessThan(partial.zOrder, 100)
        XCTAssertTrue(result.sharedRoutes.isEmpty)
    }

    func testComparisonOfFourThousandRecordsCompletesWithinTwoSeconds() throws {
        let owners = [aliceID, bobID, carolID, daveID]
        let datasets = owners.enumerated().map { profileIndex, owner in
            dataset(
                owner,
                records: (0..<1_000).map { offset in
                    record(
                        owner: owner,
                        id: profileIndex * 1_000 + offset + 1,
                        flightNumber: "F\(offset)",
                        date: date(2026, (offset % 12) + 1, (offset % 28) + 1),
                        departure: offset.isMultiple(of: 2) ? pek : hnd,
                        arrival: yul
                    )
                }
            )
        }
        let clock = ContinuousClock()

        let elapsed = try clock.measure {
            _ = try service.compare(datasets)
        }

        XCTAssertLessThan(
            elapsed,
            .seconds(2),
            "4 × 1000 records comparison exceeded the explicit 2 second threshold"
        )
    }

    private func dataset(
        _ id: UUID,
        color: ProfileComparisonColor = .blue,
        records: [FlightRecord] = []
    ) -> ProfileDataset {
        ProfileDataset(
            profileID: id,
            name: name(for: id),
            color: color,
            records: records
        )
    }

    private func name(for id: UUID) -> String {
        switch id {
        case aliceID: "Alice"
        case bobID: "Bob"
        case carolID: "Carol"
        case daveID: "Dave"
        default: "Other"
        }
    }

    private func record(
        owner: UUID,
        id: Int,
        flightNumber: String = "CA123",
        date: Date? = nil,
        departure: Airport? = nil,
        arrival: Airport? = nil,
        validDuration: Bool = true
    ) -> FlightRecord {
        let flightDate = date ?? self.date(2026, 8, 20)
        let departureDate = flightDate.addingTimeInterval(3_600)
        return FlightRecord(
            id: uuid(id),
            flightNumber: flightNumber,
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: flightDate,
            departureAirport: departure ?? pek,
            arrivalAirport: arrival ?? yul,
            departureDate: departureDate,
            arrivalDate: validDuration
                ? departureDate.addingTimeInterval(3_600)
                : departureDate,
            ownerProfileID: owner
        )
    }

    private func clone(
        _ source: FlightRecord,
        owner: UUID,
        id: Int
    ) -> FlightRecord {
        let departure = Airport(
            iata: source.departureAirportIATA, icao: "",
            name: source.departureAirportName, city: source.departureCity,
            country: source.departureCountry,
            countryCode: source.departureCountryCode,
            latitude: source.departureLatitude,
            longitude: source.departureLongitude,
            timeZoneID: source.departureTimeZoneID
        )
        let arrival = Airport(
            iata: source.arrivalAirportIATA, icao: "",
            name: source.arrivalAirportName, city: source.arrivalCity,
            country: source.arrivalCountry,
            countryCode: source.arrivalCountryCode,
            latitude: source.arrivalLatitude,
            longitude: source.arrivalLongitude,
            timeZoneID: source.arrivalTimeZoneID
        )
        let record = FlightRecord(
            id: uuid(id),
            flightNumber: source.flightNumber,
            airlineCode: source.airlineCode,
            airlineName: source.airlineName,
            flightDate: source.flightDate,
            departureAirport: departure,
            arrivalAirport: arrival,
            departureDate: source.departureDate,
            arrivalDate: source.arrivalDate,
            ownerProfileID: owner
        )
        record.departureLocalDateTime = source.departureLocalDateTime
        record.departureUTCOffsetSeconds = source.departureUTCOffsetSeconds
        record.arrivalLocalDateTime = source.arrivalLocalDateTime
        record.arrivalUTCOffsetSeconds = source.arrivalUTCOffsetSeconds
        return record
    }

    private var pek: Airport {
        Airport(
            iata: "PEK", icao: "ZBAA", name: "Beijing Capital",
            city: "Beijing", country: "China", countryCode: "CN",
            latitude: 40.0801, longitude: 116.5846,
            timeZoneID: "Asia/Shanghai"
        )
    }

    private var yul: Airport {
        Airport(
            iata: "YUL", icao: "CYUL", name: "Montréal–Trudeau",
            city: "Montreal", country: "Canada", countryCode: "CA",
            latitude: 45.4706, longitude: -73.7408,
            timeZoneID: "America/Toronto"
        )
    }

    private var hnd: Airport {
        Airport(
            iata: "HND", icao: "RJTT", name: "Tokyo Haneda",
            city: "Tokyo", country: "Japan", countryCode: "JP",
            latitude: 35.5494, longitude: 139.7798,
            timeZoneID: "Asia/Tokyo"
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(
            format: "00000000-0000-0000-0000-%012d", value
        ))!
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour
        ))!
    }
}
