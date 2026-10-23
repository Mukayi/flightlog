import Foundation
import XCTest
@testable import FlightLog

final class FlightMetricsTests: XCTestCase {
    private let metrics = FlightMetricsService()

    func testKnownJFKToLHRDistanceUsesSnapshotCoordinatesWithinTolerance() {
        let record = makeRecord(
            departure: newYork,
            arrival: london
        )

        let distance = metrics.distanceKilometers(for: record)

        XCTAssertNotNil(distance)
        XCTAssertEqual(distance!, 5_540, accuracy: 35)
    }

    func testDistanceIsSymmetricAndRejectsInvalidCoordinates() {
        let start = FlightCoordinate(latitude: 35.5494, longitude: 139.7798)
        let end = FlightCoordinate(latitude: 33.9416, longitude: -118.4085)
        let invalid = FlightCoordinate(latitude: 91, longitude: 0)

        let forward = metrics.distanceKilometers(from: start, to: end)
        let reverse = metrics.distanceKilometers(from: end, to: start)

        XCTAssertNotNil(forward)
        XCTAssertEqual(forward!, reverse!, accuracy: 0.000_001)
        XCTAssertNil(metrics.distanceKilometers(from: invalid, to: end))
    }

    func testDistanceFormattingSupportsKilometersAndMiles() {
        XCTAssertEqual(
            metrics.formattedDistance(
                kilometers: 1_000,
                unit: .kilometers
            ),
            "1,000 公里"
        )
        XCTAssertEqual(
            metrics.formattedDistance(
                kilometers: 1_000,
                unit: .miles
            ),
            "621 英里"
        )
    }

    func testDurationUsesAbsoluteDatesAndRejectsNonPositiveIntervals() {
        let departure = Date(timeIntervalSince1970: 1_000)
        let arrival = departure.addingTimeInterval(5 * 3_600 + 25 * 60)

        XCTAssertEqual(
            metrics.durationMinutes(
                departureDate: departure,
                arrivalDate: arrival
            ),
            325
        )
        XCTAssertNil(
            metrics.durationMinutes(
                departureDate: arrival,
                arrivalDate: departure
            )
        )
        XCTAssertNil(
            metrics.durationMinutes(
                departureDate: departure,
                arrivalDate: departure
            )
        )
    }

    private var newYork: Airport {
        Airport(
            iata: "JFK",
            icao: "KJFK",
            name: "John F. Kennedy International Airport",
            city: "New York",
            country: "United States",
            countryCode: "US",
            latitude: 40.6413,
            longitude: -73.7781,
            timeZoneID: "America/New_York"
        )
    }

    private var london: Airport {
        Airport(
            iata: "LHR",
            icao: "EGLL",
            name: "London Heathrow Airport",
            city: "London",
            country: "United Kingdom",
            countryCode: "GB",
            latitude: 51.4700,
            longitude: -0.4543,
            timeZoneID: "Europe/London"
        )
    }

    private func makeRecord(
        departure: Airport,
        arrival: Airport
    ) -> FlightRecord {
        let departureDate = Date(timeIntervalSince1970: 1_000)
        return FlightRecord(
            flightNumber: "TEST1",
            airlineCode: "TS",
            airlineName: "Test Air",
            flightDate: departureDate,
            departureAirport: departure,
            arrivalAirport: arrival,
            departureDate: departureDate,
            arrivalDate: departureDate.addingTimeInterval(3_600),
            ownerProfileID: UserProfileDefaults.id
        )
    }
}

final class GreatCircleRouteSamplerTests: XCTestCase {
    func testSamplingCrossesDateLineAndSplitsMapSegments() throws {
        let start = FlightCoordinate(latitude: 10, longitude: 170)
        let end = FlightCoordinate(latitude: 10, longitude: -170)

        let points = GreatCircleRouteSampler.sample(
            from: start,
            to: end,
            segmentCount: 8
        )
        let segments = GreatCircleRouteSampler.sampleSegments(
            from: start,
            to: end,
            segmentCount: 8
        )

        XCTAssertEqual(points.count, 9)
        let first = try XCTUnwrap(points.first)
        let last = try XCTUnwrap(points.last)
        XCTAssertEqual(first.latitude, start.latitude, accuracy: 0.000_001)
        XCTAssertEqual(first.longitude, start.longitude, accuracy: 0.000_001)
        XCTAssertEqual(last.latitude, end.latitude, accuracy: 0.000_001)
        XCTAssertEqual(last.longitude, end.longitude, accuracy: 0.000_001)
        XCTAssertTrue(points.contains { abs($0.longitude) >= 179 })
        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(
            segments.allSatisfy { segment in
                zip(segment, segment.dropFirst()).allSatisfy {
                    abs($0.longitude - $1.longitude) <= 180
                }
            }
        )
    }

    func testReverseSamplingMirrorsForwardGreatCircle() {
        let start = FlightCoordinate(latitude: 35.5494, longitude: 139.7798)
        let end = FlightCoordinate(latitude: 33.9416, longitude: -118.4085)

        let forward = GreatCircleRouteSampler.sample(
            from: start,
            to: end,
            segmentCount: 16
        )
        let reverse = GreatCircleRouteSampler.sample(
            from: end,
            to: start,
            segmentCount: 16
        )

        XCTAssertEqual(forward.count, reverse.count)
        for (lhs, rhs) in zip(forward, reverse.reversed()) {
            XCTAssertEqual(lhs.latitude, rhs.latitude, accuracy: 0.000_001)
            XCTAssertLessThanOrEqual(
                longitudeDifference(lhs.longitude, rhs.longitude),
                0.000_001
            )
        }
    }

    func testSamplingSameCoordinateIsSafeAndInvalidCoordinateIsEmpty() {
        let coordinate = FlightCoordinate(latitude: 40, longitude: 116)
        let invalid = FlightCoordinate(latitude: .nan, longitude: 0)

        XCTAssertEqual(
            GreatCircleRouteSampler.sample(
                from: coordinate,
                to: coordinate,
                segmentCount: 8
            ),
            [coordinate, coordinate]
        )
        XCTAssertTrue(
            GreatCircleRouteSampler.sample(
                from: invalid,
                to: coordinate,
                segmentCount: 8
            ).isEmpty
        )
    }

    private func longitudeDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }
}

final class RouteAggregationTests: XCTestCase {
    private let metrics = FlightMetricsService()

    func testAggregatorCombinesReverseFlightsIntoRecognizableStableRoute() throws {
        let outbound = makeRecord(
            id: uuid(1),
            flightNumber: "CA1",
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: date(2026, 1, 10),
            departure: beijing,
            arrival: montreal
        )
        let returnFlight = makeRecord(
            id: uuid(2),
            flightNumber: "AC2",
            airlineCode: "AC",
            airlineName: "Air Canada",
            flightDate: date(2026, 1, 15),
            departure: montreal,
            arrival: beijing
        )
        let other = makeRecord(
            id: uuid(3),
            flightNumber: "JL3",
            airlineCode: "JL",
            airlineName: "Japan Airlines",
            flightDate: date(2026, 2, 1),
            departure: tokyo,
            arrival: beijing
        )

        let routes = RouteAggregator(metrics: metrics).aggregate(
            [returnFlight, other, outbound]
        )

        XCTAssertEqual(routes.map(\.id), ["HND-PEK", "PEK-YUL"])
        let roundTrip = routes.first { $0.id == "PEK-YUL" }
        XCTAssertNotNil(roundTrip)
        XCTAssertEqual(roundTrip?.flightCount, 2)
        XCTAssertEqual(roundTrip?.airportA.iata, "PEK")
        XCTAssertEqual(roundTrip?.airportB.iata, "YUL")
        XCTAssertEqual(
            roundTrip?.flights.map(\.id),
            [returnFlight.id, outbound.id]
        )
        XCTAssertEqual(
            roundTrip?.airlines,
            ["AC · Air Canada", "CA · Air China"]
        )

        let expectedDistance = metrics.distanceKilometers(for: outbound)!
            + metrics.distanceKilometers(for: returnFlight)!
        XCTAssertEqual(
            try XCTUnwrap(roundTrip?.totalDistanceKilometers),
            expectedDistance,
            accuracy: 0.001
        )
    }

    func testAggregatorUsesFirstValidSnapshotsWhenNewestFlightCoordinatesAreInvalid() throws {
        let invalidBeijing = Airport(
            iata: "PEK",
            icao: "ZBAA",
            name: "无效北京快照",
            city: "北京",
            country: "中国",
            countryCode: "CN",
            latitude: 120,
            longitude: 116.5846,
            timeZoneID: "Asia/Shanghai"
        )
        let invalidNewest = makeRecord(
            id: uuid(1),
            flightNumber: "CA1",
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: date(2026, 2, 1),
            departure: invalidBeijing,
            arrival: montreal
        )
        let validOlder = makeRecord(
            id: uuid(2),
            flightNumber: "CA2",
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: date(2026, 1, 1),
            departure: beijing,
            arrival: montreal
        )

        let route = RouteAggregator(metrics: metrics).aggregate(
            [validOlder, invalidNewest]
        ).first

        XCTAssertNotNil(route)
        XCTAssertTrue(route!.hasValidGeometry)
        XCTAssertEqual(route?.airportA.latitude, beijing.latitude)
        XCTAssertEqual(route?.airportA.longitude, beijing.longitude)
        XCTAssertEqual(route?.measuredDistanceFlightCount, 1)
        XCTAssertEqual(route?.missingDistanceFlightCount, 1)
        XCTAssertEqual(
            try XCTUnwrap(route?.totalDistanceKilometers),
            try XCTUnwrap(metrics.distanceKilometers(for: validOlder)),
            accuracy: 0.001
        )
        XCTAssertFalse(
            GreatCircleRouteSampler.sampleSegments(
                from: route!.airportA.coordinate,
                to: route!.airportB.coordinate,
                segmentCount: 8
            ).isEmpty
        )
    }

    func testAggregatorOrderingDoesNotDependOnInputOrder() {
        let first = makeRecord(
            id: uuid(1),
            flightNumber: "CA1",
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: date(2026, 1, 10),
            departure: beijing,
            arrival: montreal
        )
        let second = makeRecord(
            id: uuid(2),
            flightNumber: "JL2",
            airlineCode: "JL",
            airlineName: "Japan Airlines",
            flightDate: date(2026, 2, 1),
            departure: tokyo,
            arrival: beijing
        )
        let aggregator = RouteAggregator(metrics: metrics)

        let forward = aggregator.aggregate([first, second])
        let reversed = aggregator.aggregate([second, first])

        XCTAssertEqual(forward.map(\.id), reversed.map(\.id))
        XCTAssertEqual(
            forward.map { $0.flights.map(\.id) },
            reversed.map { $0.flights.map(\.id) }
        )
    }

    func testAggregatorDistinguishesUnknownDistanceFromMeasuredZero() throws {
        let invalidAirport = Airport(
            iata: "BAD",
            icao: "",
            name: "无效坐标机场",
            city: "未知",
            country: "未知",
            countryCode: "",
            latitude: 120,
            longitude: 0,
            timeZoneID: "Etc/UTC"
        )
        let sameAirport = makeRecord(
            id: uuid(1),
            flightNumber: "CA1",
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: date(2026, 1, 10),
            departure: beijing,
            arrival: beijing
        )
        let invalid = makeRecord(
            id: uuid(2),
            flightNumber: "BAD2",
            airlineCode: "",
            airlineName: "",
            flightDate: date(2026, 1, 11),
            departure: invalidAirport,
            arrival: beijing
        )

        let routes = RouteAggregator(metrics: metrics).aggregate(
            [sameAirport, invalid]
        )

        XCTAssertEqual(routes.map(\.id), ["BAD-PEK", "PEK-PEK"])
        let unknownRoute = try XCTUnwrap(
            routes.first { $0.id == "BAD-PEK" }
        )
        XCTAssertNil(unknownRoute.totalDistanceKilometers)
        XCTAssertEqual(unknownRoute.measuredDistanceFlightCount, 0)
        XCTAssertEqual(unknownRoute.missingDistanceFlightCount, 1)

        let measuredZeroRoute = try XCTUnwrap(
            routes.first { $0.id == "PEK-PEK" }
        )
        XCTAssertEqual(
            try XCTUnwrap(measuredZeroRoute.totalDistanceKilometers),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(measuredZeroRoute.measuredDistanceFlightCount, 1)
        XCTAssertEqual(measuredZeroRoute.missingDistanceFlightCount, 0)
    }

    func testRouteFilterCombinesInclusiveDateAirlineAndAirportCriteria() {
        let before = makeRecord(
            id: uuid(1),
            flightNumber: "CA1",
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: date(2025, 12, 31),
            departure: beijing,
            arrival: montreal
        )
        let lowerBoundary = makeRecord(
            id: uuid(2),
            flightNumber: "CA2",
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: date(2026, 1, 1),
            departure: beijing,
            arrival: montreal
        )
        let upperBoundary = makeRecord(
            id: uuid(3),
            flightNumber: "CA3",
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: date(2026, 12, 31),
            departure: montreal,
            arrival: beijing
        )
        let wrongAirline = makeRecord(
            id: uuid(4),
            flightNumber: "JL4",
            airlineCode: "JL",
            airlineName: "Japan Airlines",
            flightDate: date(2026, 6, 1),
            departure: montreal,
            arrival: beijing
        )
        let filter = RouteFilter(
            dateRange: date(2026, 1, 1)...date(2026, 12, 31),
            airline: "air china",
            airportIATA: " yul "
        )

        let result = filter.apply(
            to: [before, wrongAirline, upperBoundary, lowerBoundary]
        )

        XCTAssertEqual(
            Set(result.map(\.id)),
            Set([lowerBoundary.id, upperBoundary.id])
        )
    }

    func testRouteSelectionClearsAFilteredRouteAndKeepsAVisibleRoute() {
        XCTAssertNil(
            RouteSelection.reconciled(
                selectedRouteID: "PEK-YUL",
                visibleRouteIDs: ["HND-PEK"]
            )
        )
        XCTAssertEqual(
            RouteSelection.reconciled(
                selectedRouteID: "PEK-YUL",
                visibleRouteIDs: ["PEK-YUL"]
            ),
            "PEK-YUL"
        )
    }

    func testRouteLineWidthScalesMonotonicallyAndClampsInvalidCounts() {
        let single = RouteVisualScale.lineWidth(
            flightCount: 1,
            maximumFlightCount: 9
        )
        let repeated = RouteVisualScale.lineWidth(
            flightCount: 4,
            maximumFlightCount: 9
        )
        let maximum = RouteVisualScale.lineWidth(
            flightCount: 9,
            maximumFlightCount: 9
        )

        XCTAssertEqual(single, 2, accuracy: 0.000_001)
        XCTAssertGreaterThan(repeated, single)
        XCTAssertLessThan(repeated, maximum)
        XCTAssertEqual(maximum, 8, accuracy: 0.000_001)
        XCTAssertEqual(
            RouteVisualScale.lineWidth(
                flightCount: 0,
                maximumFlightCount: 0
            ),
            2,
            accuracy: 0.000_001
        )
    }

    private var beijing: Airport {
        Airport(
            iata: "PEK",
            icao: "ZBAA",
            name: "北京首都国际机场",
            city: "北京",
            country: "中国",
            countryCode: "CN",
            latitude: 40.0801,
            longitude: 116.5846,
            timeZoneID: "Asia/Shanghai"
        )
    }

    private var montreal: Airport {
        Airport(
            iata: "YUL",
            icao: "CYUL",
            name: "蒙特利尔特鲁多国际机场",
            city: "蒙特利尔",
            country: "加拿大",
            countryCode: "CA",
            latitude: 45.4706,
            longitude: -73.7408,
            timeZoneID: "America/Toronto"
        )
    }

    private var tokyo: Airport {
        Airport(
            iata: "HND",
            icao: "RJTT",
            name: "东京羽田机场",
            city: "东京",
            country: "日本",
            countryCode: "JP",
            latitude: 35.5494,
            longitude: 139.7798,
            timeZoneID: "Asia/Tokyo"
        )
    }

    private func makeRecord(
        id: UUID,
        flightNumber: String,
        airlineCode: String,
        airlineName: String,
        flightDate: Date,
        departure: Airport,
        arrival: Airport
    ) -> FlightRecord {
        FlightRecord(
            id: id,
            flightNumber: flightNumber,
            airlineCode: airlineCode,
            airlineName: airlineName,
            flightDate: flightDate,
            departureAirport: departure,
            arrivalAirport: arrival,
            departureDate: flightDate.addingTimeInterval(3_600),
            arrivalDate: flightDate.addingTimeInterval(7_200),
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

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
