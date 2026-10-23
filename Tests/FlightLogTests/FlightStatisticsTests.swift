import Foundation
import XCTest
@testable import FlightLog

final class FlightStatisticsTests: XCTestCase {
    private let service = FlightStatisticsService()

    func testSnapshotSummarizesMeasuredTotalsAndUniqueLocations() throws {
        let records = [
            makeRecord(
                id: uuid(1),
                flightNumber: "CA1",
                airlineCode: "CA",
                airlineName: "Air China",
                flightDate: date(2026, 1, 10),
                departure: airportA,
                arrival: airportB,
                durationMinutes: 60
            ),
            makeRecord(
                id: uuid(2),
                flightNumber: "JL2",
                airlineCode: "JL",
                airlineName: "Japan Airlines",
                flightDate: date(2026, 1, 11),
                departure: airportB,
                arrival: airportC,
                durationMinutes: 120
            ),
        ]

        let snapshot = service.snapshot(records)

        XCTAssertEqual(snapshot.totalFlightCount, 2)
        XCTAssertEqual(
            try XCTUnwrap(snapshot.totalDistanceKilometers),
            222.39,
            accuracy: 0.5
        )
        XCTAssertEqual(snapshot.measuredDistanceFlightCount, 2)
        XCTAssertEqual(snapshot.missingDistanceFlightCount, 0)
        XCTAssertEqual(snapshot.totalDurationMinutes, 180)
        XCTAssertEqual(snapshot.measuredDurationFlightCount, 2)
        XCTAssertEqual(snapshot.missingDurationFlightCount, 0)
        XCTAssertEqual(snapshot.uniqueAirportCount, 3)
        XCTAssertEqual(snapshot.uniqueCityCount, 3)
        XCTAssertEqual(snapshot.uniqueCountryCount, 2)
        XCTAssertEqual(
            snapshot.airportRankings.map { "\($0.id):\($0.count)" },
            ["BBB:2", "AAA:1", "CCC:1"]
        )
    }

    func testCountryAndCityKeysAliasLegacyNamesToISOWithoutMergingUnknown() {
        let coded = makeRecord(
            id: uuid(20),
            flightDate: date(2026, 4, 1),
            departure: airportA,
            arrival: airportA
        )
        let legacy = makeRecord(
            id: uuid(21),
            flightDate: date(2026, 4, 2),
            departure: airportA,
            arrival: airportA
        )
        legacy.departureCountryCode = ""
        legacy.arrivalCountryCode = ""
        let unknownAirport = Airport(
            iata: "UNK",
            icao: "",
            name: "Unknown Country Airport",
            city: airportA.city,
            country: "Unknown",
            countryCode: "",
            latitude: 5,
            longitude: 5,
            timeZoneID: "Etc/UTC"
        )
        let unknown = makeRecord(
            id: uuid(22),
            flightDate: date(2026, 4, 3),
            departure: unknownAirport,
            arrival: unknownAirport
        )

        let forward = service.snapshot([coded, legacy, unknown])
        let reversed = service.snapshot([unknown, legacy, coded])

        XCTAssertEqual(forward.uniqueCountryCount, 1)
        XCTAssertEqual(forward.uniqueCityCount, 2)
        XCTAssertEqual(reversed.uniqueCountryCount, 1)
        XCTAssertEqual(reversed.uniqueCityCount, 2)
    }

    func testRankingsCombineReverseRoutesAndBreakTiesByStableKeys() {
        let records = [
            makeRecord(
                id: uuid(1),
                flightNumber: "ZZ1",
                airlineCode: "ZZ",
                airlineName: "Zeta Air",
                flightDate: date(2026, 1, 1),
                departure: airportA,
                arrival: airportB
            ),
            makeRecord(
                id: uuid(2),
                flightNumber: "ZZ2",
                airlineCode: "ZZ",
                airlineName: "Zeta Air",
                flightDate: date(2026, 1, 2),
                departure: airportB,
                arrival: airportA
            ),
            makeRecord(
                id: uuid(3),
                flightNumber: "AA1",
                airlineCode: "AA",
                airlineName: "Alpha Air",
                flightDate: date(2026, 1, 3),
                departure: airportA,
                arrival: airportC
            ),
            makeRecord(
                id: uuid(4),
                flightNumber: "AA2",
                airlineCode: "AA",
                airlineName: "Alpha Air",
                flightDate: date(2026, 1, 4),
                departure: airportC,
                arrival: airportA
            ),
        ]

        let snapshot = service.snapshot(records)

        XCTAssertEqual(
            snapshot.airlineRankings.map { "\($0.id):\($0.count)" },
            ["AA:2", "ZZ:2"]
        )
        XCTAssertEqual(
            snapshot.routeRankings.map { "\($0.id):\($0.count)" },
            ["AAA-BBB:2", "AAA-CCC:2"]
        )
        XCTAssertEqual(
            snapshot.airportRankings.map { "\($0.id):\($0.count)" },
            ["AAA:4", "BBB:2", "CCC:2"]
        )
    }

    func testRouteRankingPlacesUnknownRoutesAfterKnownRoutesWhenTied() {
        let airportY = Airport(
            iata: "YYY",
            icao: "",
            name: "Y Airport",
            city: "Y City",
            country: "China",
            countryCode: "CN",
            latitude: 10,
            longitude: 10,
            timeZoneID: "Etc/UTC"
        )
        let airportZ = Airport(
            iata: "ZZZ",
            icao: "",
            name: "Z Airport",
            city: "Z City",
            country: "China",
            countryCode: "CN",
            latitude: 11,
            longitude: 11,
            timeZoneID: "Etc/UTC"
        )
        let known = makeRecord(
            id: uuid(30),
            flightDate: date(2026, 5, 1),
            departure: airportY,
            arrival: airportZ
        )
        let unknown = makeRecord(
            id: uuid(31),
            flightDate: date(2026, 5, 2),
            departure: airportA,
            arrival: airportB
        )
        unknown.arrivalAirportIATA = ""

        let forward = service.snapshot([unknown, known])
        let reversed = service.snapshot([known, unknown])

        XCTAssertEqual(
            forward.routeRankings.map(\.id),
            ["YYY-ZZZ", "AAA-未知"]
        )
        XCTAssertEqual(
            reversed.routeRankings.map(\.id),
            ["YYY-ZZZ", "AAA-未知"]
        )
    }

    func testOverviewRecentFlightsUseStableSecondaryKeysForSameDate() {
        let newest = makeRecord(
            id: uuid(40),
            flightNumber: "NEW1",
            flightDate: date(2026, 6, 2),
            departure: airportA,
            arrival: airportB
        )
        let laterDeparture = makeRecord(
            id: uuid(41),
            flightNumber: "CC3",
            flightDate: date(2026, 6, 1),
            departure: airportA,
            arrival: airportB
        )
        laterDeparture.departureDate = date(2026, 6, 1, 8)
        let alphaFirstID = makeRecord(
            id: uuid(42),
            flightNumber: "AA1",
            flightDate: date(2026, 6, 1),
            departure: airportA,
            arrival: airportB
        )
        let alphaSecondID = makeRecord(
            id: uuid(43),
            flightNumber: "AA1",
            flightDate: date(2026, 6, 1),
            departure: airportA,
            arrival: airportB
        )
        let beta = makeRecord(
            id: uuid(44),
            flightNumber: "BB2",
            flightDate: date(2026, 6, 1),
            departure: airportA,
            arrival: airportB
        )

        let ordered = OverviewFlightOrdering.recent([
            beta,
            alphaSecondID,
            laterDeparture,
            newest,
            alphaFirstID,
        ])

        XCTAssertEqual(ordered.map(\.id), [
            newest.id,
            laterDeparture.id,
            alphaFirstID.id,
            alphaSecondID.id,
            beta.id,
        ])
    }

    func testLongestFlightsUseDistanceThenRecentDateFlightNumberAndID() {
        let older = makeRecord(
            id: uuid(2),
            flightNumber: "ZZ9",
            airlineCode: "ZZ",
            airlineName: "Zeta Air",
            flightDate: date(2026, 1, 1),
            departure: airportA,
            arrival: airportC
        )
        let newerB = makeRecord(
            id: uuid(3),
            flightNumber: "BB2",
            airlineCode: "BB",
            airlineName: "Beta Air",
            flightDate: date(2026, 2, 1),
            departure: airportC,
            arrival: airportA
        )
        let newerA = makeRecord(
            id: uuid(1),
            flightNumber: "AA1",
            airlineCode: "AA",
            airlineName: "Alpha Air",
            flightDate: date(2026, 2, 1),
            departure: airportA,
            arrival: airportC
        )

        let snapshot = service.snapshot([older, newerB, newerA])

        XCTAssertEqual(
            snapshot.longestFlights.map { $0.id },
            [newerA.id, newerB.id, older.id]
        )
    }

    func testDomesticInternationalAndUnknownUseSnapshotISOCountryCodes() {
        let domestic = makeRecord(
            id: uuid(1),
            flightDate: date(2026, 1, 1),
            departure: airportA,
            arrival: airportB
        )
        let international = makeRecord(
            id: uuid(2),
            flightDate: date(2026, 1, 2),
            departure: airportB,
            arrival: airportC
        )
        let unknown = makeRecord(
            id: uuid(3),
            flightDate: date(2026, 1, 3),
            departure: airportC,
            arrival: airportWithoutCountryCode
        )

        let snapshot = service.snapshot([unknown, international, domestic])

        XCTAssertEqual(snapshot.domesticFlightCount, 1)
        XCTAssertEqual(snapshot.internationalFlightCount, 1)
        XCTAssertEqual(snapshot.unknownClassificationFlightCount, 1)
    }

    func testMissingDistanceAndDurationStayDistinctFromMeasuredZero() throws {
        let measuredZero = makeRecord(
            id: uuid(1),
            flightDate: date(2026, 1, 1),
            departure: airportA,
            arrival: airportA,
            durationMinutes: 60
        )
        let missing = makeRecord(
            id: uuid(2),
            flightDate: date(2026, 1, 2),
            departure: airportWithInvalidCoordinates,
            arrival: airportB,
            durationMinutes: nil
        )

        let partial = service.snapshot([missing, measuredZero])

        XCTAssertEqual(
            try XCTUnwrap(partial.totalDistanceKilometers),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(partial.measuredDistanceFlightCount, 1)
        XCTAssertEqual(partial.missingDistanceFlightCount, 1)
        XCTAssertEqual(partial.totalDurationMinutes, 60)
        XCTAssertEqual(partial.measuredDurationFlightCount, 1)
        XCTAssertEqual(partial.missingDurationFlightCount, 1)

        let entirelyMissing = service.snapshot([missing])
        XCTAssertNil(entirelyMissing.totalDistanceKilometers)
        XCTAssertNil(entirelyMissing.totalDurationMinutes)
        XCTAssertEqual(entirelyMissing.missingDistanceFlightCount, 1)
        XCTAssertEqual(entirelyMissing.missingDurationFlightCount, 1)
    }

    func testAirportVisitsCountBothEndpointsAndUnknownAirlineIsExplicit() {
        let record = makeRecord(
            id: uuid(1),
            flightNumber: "TEST1",
            airlineCode: "",
            airlineName: "",
            flightDate: date(2026, 1, 1),
            departure: airportA,
            arrival: airportA
        )

        let snapshot = service.snapshot([record])

        XCTAssertEqual(snapshot.airportRankings.first?.id, "AAA")
        XCTAssertEqual(snapshot.airportRankings.first?.count, 2)
        XCTAssertEqual(snapshot.airlineRankings.first?.id, "unknown-airline")
        XCTAssertEqual(snapshot.airlineRankings.first?.label, "未知航司")
        XCTAssertEqual(snapshot.airlineRankings.first?.count, 1)
    }

    func testYearlyAndMonthlyTrendsUseStableUTCCalendarKeys() {
        let records = [
            makeRecord(
                id: uuid(1),
                flightDate: date(2025, 12, 31, 20),
                departure: airportA,
                arrival: airportB,
                durationMinutes: 30
            ),
            makeRecord(
                id: uuid(2),
                flightDate: date(2026, 1, 1),
                departure: airportA,
                arrival: airportB,
                durationMinutes: 60
            ),
            makeRecord(
                id: uuid(3),
                flightDate: date(2026, 1, 15),
                departure: airportB,
                arrival: airportC,
                durationMinutes: 90
            ),
            makeRecord(
                id: uuid(4),
                flightDate: date(2026, 3, 1),
                departure: airportC,
                arrival: airportA,
                durationMinutes: 120
            ),
        ]

        let all = service.snapshot(records)

        XCTAssertEqual(
            all.yearlyTrend.map { "\($0.year):\($0.flightCount)" },
            ["2025:1", "2026:3"]
        )
        XCTAssertEqual(
            all.monthlyTrend.map { "\($0.month.id):\($0.flightCount)" },
            ["2025-12:1", "2026-01:2", "2026-03:1"]
        )

        let selectedYear = service.snapshot(records, filter: .year(2026))
        XCTAssertEqual(selectedYear.totalFlightCount, 3)
        XCTAssertEqual(selectedYear.monthlyTrend.count, 12)
        XCTAssertEqual(selectedYear.monthlyTrend[0].month.id, "2026-01")
        XCTAssertEqual(selectedYear.monthlyTrend[0].flightCount, 2)
        XCTAssertEqual(selectedYear.monthlyTrend[1].month.id, "2026-02")
        XCTAssertEqual(selectedYear.monthlyTrend[1].flightCount, 0)
        XCTAssertNil(selectedYear.monthlyTrend[1].totalDistanceKilometers)
        XCTAssertNil(selectedYear.monthlyTrend[1].totalDurationMinutes)
        XCTAssertEqual(selectedYear.monthlyTrend[2].flightCount, 1)
    }

    func testYearAndInclusiveDateRangeFiltersApplyToEveryStatistic() {
        let before = makeRecord(
            id: uuid(1),
            airlineCode: "AA",
            airlineName: "Alpha Air",
            flightDate: date(2025, 12, 31),
            departure: airportA,
            arrival: airportB
        )
        let lowerBoundary = makeRecord(
            id: uuid(2),
            airlineCode: "BB",
            airlineName: "Beta Air",
            flightDate: date(2026, 1, 1),
            departure: airportB,
            arrival: airportC
        )
        let upperBoundary = makeRecord(
            id: uuid(3),
            airlineCode: "BB",
            airlineName: "Beta Air",
            flightDate: date(2026, 12, 31),
            departure: airportC,
            arrival: airportB
        )
        let after = makeRecord(
            id: uuid(4),
            airlineCode: "AA",
            airlineName: "Alpha Air",
            flightDate: date(2027, 1, 1),
            departure: airportA,
            arrival: airportC
        )
        let records = [after, lowerBoundary, before, upperBoundary]

        let year = service.snapshot(records, filter: .year(2026))
        XCTAssertEqual(year.totalFlightCount, 2)
        XCTAssertEqual(year.airlineRankings.map { $0.id }, ["BB"])
        XCTAssertEqual(year.routeRankings.map { $0.id }, ["BBB-CCC"])

        let range = service.snapshot(
            records,
            filter: .dateRange(
                date(2026, 1, 1)...date(2026, 12, 31)
            )
        )
        XCTAssertEqual(range.totalFlightCount, 2)
        XCTAssertEqual(range.longestFlights.map { $0.id }, [
            upperBoundary.id,
            lowerBoundary.id,
        ])
    }

    func testEmptySnapshotDoesNotInventMeasuredTotals() {
        let snapshot = service.snapshot([])

        XCTAssertEqual(snapshot.totalFlightCount, 0)
        XCTAssertNil(snapshot.totalDistanceKilometers)
        XCTAssertNil(snapshot.totalDurationMinutes)
        XCTAssertTrue(snapshot.airportRankings.isEmpty)
        XCTAssertTrue(snapshot.airlineRankings.isEmpty)
        XCTAssertTrue(snapshot.routeRankings.isEmpty)
        XCTAssertTrue(snapshot.longestFlights.isEmpty)
        XCTAssertTrue(snapshot.yearlyTrend.isEmpty)
        XCTAssertTrue(snapshot.monthlyTrend.isEmpty)
    }

    func testViewDataDerivesYearsAndSelectedSnapshotInOneRefreshAPI() {
        let records = [
            makeRecord(
                id: uuid(1),
                flightDate: date(2025, 12, 31),
                departure: airportA,
                arrival: airportB
            ),
            makeRecord(
                id: uuid(2),
                flightDate: date(2026, 1, 1),
                departure: airportB,
                arrival: airportC
            ),
        ]

        let viewData = service.viewData(records, selectedYear: 2026)

        XCTAssertEqual(viewData.availableYears, [2026, 2025])
        XCTAssertEqual(viewData.snapshot.totalFlightCount, 1)
        XCTAssertEqual(viewData.snapshot.yearlyTrend.map(\.year), [2026])
    }

    func testSharedDistanceUnitSupportsPersistentRawValues() {
        XCTAssertEqual(DistanceUnit.kilometers.rawValue, "km")
        XCTAssertEqual(DistanceUnit.miles.rawValue, "mi")
        XCTAssertEqual(
            DistanceUnit.miles.convert(kilometers: 1_000),
            621.371_192_2,
            accuracy: 0.000_000_1
        )
        XCTAssertEqual(
            FlightMetricsService.standard.formattedDistance(
                kilometers: 1_000,
                unit: .miles
            ),
            "621 英里"
        )
    }

    func testTrendSubtitlesExposeSharedUnitsIncludingDurationHours() {
        XCTAssertEqual(
            StatisticsTrendMetric.flightCount.chartSubtitle(
                distanceUnit: .kilometers
            ),
            "航班次数（次）"
        )
        XCTAssertEqual(
            StatisticsTrendMetric.distance.chartSubtitle(
                distanceUnit: .miles
            ),
            "有效距离（mi）"
        )
        XCTAssertEqual(
            StatisticsTrendMetric.duration.chartSubtitle(
                distanceUnit: .kilometers
            ),
            "有效时长（小时）"
        )
    }

    private var airportA: Airport {
        Airport(
            iata: "AAA",
            icao: "AAAA",
            name: "Alpha Airport",
            city: "Alpha City",
            country: "China",
            countryCode: "CN",
            latitude: 0,
            longitude: 0,
            timeZoneID: "Etc/UTC"
        )
    }

    private var airportB: Airport {
        Airport(
            iata: "BBB",
            icao: "BBBB",
            name: "Beta Airport",
            city: "Beta City",
            country: "China",
            countryCode: "CN",
            latitude: 0,
            longitude: 1,
            timeZoneID: "Etc/UTC"
        )
    }

    private var airportC: Airport {
        Airport(
            iata: "CCC",
            icao: "CCCC",
            name: "Gamma Airport",
            city: "Gamma City",
            country: "Japan",
            countryCode: "JP",
            latitude: 0,
            longitude: 2,
            timeZoneID: "Etc/UTC"
        )
    }

    private var airportWithoutCountryCode: Airport {
        Airport(
            iata: "DDD",
            icao: "DDDD",
            name: "Unknown Country Airport",
            city: "Delta City",
            country: "Unknown",
            countryCode: "",
            latitude: 0,
            longitude: 3,
            timeZoneID: "Etc/UTC"
        )
    }

    private var airportWithInvalidCoordinates: Airport {
        Airport(
            iata: "BAD",
            icao: "BAD1",
            name: "Invalid Coordinate Airport",
            city: "Invalid City",
            country: "China",
            countryCode: "CN",
            latitude: 91,
            longitude: 0,
            timeZoneID: "Etc/UTC"
        )
    }

    private func makeRecord(
        id: UUID,
        flightNumber: String = "TEST1",
        airlineCode: String = "TS",
        airlineName: String = "Test Air",
        flightDate: Date,
        departure: Airport,
        arrival: Airport,
        durationMinutes: Int? = 60
    ) -> FlightRecord {
        let departureDate = flightDate.addingTimeInterval(3_600)
        let arrivalDate = if let durationMinutes {
            departureDate.addingTimeInterval(Double(durationMinutes * 60))
        } else {
            departureDate
        }
        return FlightRecord(
            id: id,
            flightNumber: flightNumber,
            airlineCode: airlineCode,
            airlineName: airlineName,
            flightDate: flightDate,
            departureAirport: departure,
            arrivalAirport: arrival,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            ownerProfileID: UserProfileDefaults.id
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
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
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        )!
    }
}
