import Foundation
import XCTest
@testable import FlightLog

final class RouteMapVisualTests: XCTestCase {
    @MainActor
    func testInitialSelectedRouteIDEntersRouteMapViewSelectionPath() {
        let view = RouteMapView(initialSelectedRouteID: "PEK-YUL")

        XCTAssertEqual(view.initialSelectedRouteID, "PEK-YUL")
        XCTAssertEqual(
            RouteSelection.reconciled(
                selectedRouteID: view.initialSelectedRouteID,
                visibleRouteIDs: ["PEK-YUL", "SFO-YVR"]
            ),
            "PEK-YUL"
        )
    }

    func testSelectedRouteUsesAccentAboveWarmGoldUnselectedRoute() {
        let selected = RouteMapVisualPolicy.stroke(
            isSelected: true,
            baseLineWidth: 4
        )
        let unselected = RouteMapVisualPolicy.stroke(
            isSelected: false,
            baseLineWidth: 4
        )

        XCTAssertEqual(selected.colorRole, .routeAccent)
        XCTAssertEqual(selected.opacity, 1)
        XCTAssertEqual(selected.lineWidth, 6)
        XCTAssertEqual(unselected.colorRole, .warmGold)
        XCTAssertEqual(unselected.opacity, 0.68)
        XCTAssertEqual(unselected.lineWidth, 4)
        XCTAssertGreaterThan(selected.zIndex, unselected.zIndex)
    }

    func testOrderedSegmentsUsesStrokeZIndexAndPlacesSelectedRouteLast() {
        let segments = [
            makeSegment(routeID: "PEK-YUL", index: 1),
            makeSegment(routeID: "HND-PEK", index: 0),
            makeSegment(routeID: "PEK-YUL", index: 0),
            makeSegment(routeID: "LAX-SFO", index: 0),
        ]

        let ordered = RouteMapVisualPolicy.orderedSegments(
            segments,
            selectedID: "PEK-YUL"
        )

        XCTAssertEqual(
            ordered.map(\.id),
            ["HND-PEK#0", "LAX-SFO#0", "PEK-YUL#0", "PEK-YUL#1"]
        )
        XCTAssertTrue(
            ordered.suffix(2).allSatisfy { $0.routeID == "PEK-YUL" }
        )
    }

    func testUnknownDistanceRemainsUnknownInSelectedRouteCard() {
        let route = makeRoute(
            flights: [makeRecord(id: uuid(1), number: "CA101")],
            totalDistance: nil,
            measuredCount: 0,
            missingCount: 1
        )

        let presentation = RouteMapPresentation(route: route)

        XCTAssertEqual(presentation.distanceText, "未知")
        XCTAssertEqual(presentation.coverageText, "0/1 次可计算")
    }

    func testSelectedArchiveCardPresentsCompleteStableRouteDetails() {
        let newer = makeRecord(
            id: uuid(2),
            number: "CA202",
            date: date(2026, 2, 2)
        )
        let older = makeRecord(
            id: uuid(1),
            number: "CA101",
            date: date(2026, 1, 1)
        )
        let route = makeRoute(
            flights: [newer, older],
            totalDistance: 2_000,
            measuredCount: 2,
            missingCount: 0
        )

        let presentation = RouteMapPresentation(route: route)

        XCTAssertEqual(presentation.airportAIATA, "PEK")
        XCTAssertEqual(presentation.airportBIATA, "YUL")
        XCTAssertEqual(presentation.flightCountText, "2 次")
        XCTAssertEqual(presentation.distanceText, "2,000 公里")
        XCTAssertEqual(presentation.coverageText, "2/2 次可计算")
        XCTAssertEqual(
            presentation.includedFlights.map(\.id),
            [newer.id, older.id]
        )
        XCTAssertEqual(
            presentation.includedFlights.map(\.flightNumber),
            ["CA202", "CA101"]
        )
        XCTAssertEqual(
            presentation.includedFlights.map(\.dateText),
            ["2026年2月2日", "2026年1月1日"]
        )
        XCTAssertEqual(
            presentation.includedFlights.map(\.routeText),
            ["PEK → YUL", "PEK → YUL"]
        )
    }

    func testAirportAnnotationLabelNamesCodeAirportAndLocation() {
        XCTAssertEqual(
            RouteMapVisualPolicy.annotationLabel(for: beijing),
            "机场 PEK，北京首都国际机场，北京，中国"
        )
    }

    func testMotionPolicyCoversAppearanceAndHoverWithoutRepeating() {
        let initial = RouteMapVisualPolicy.motion(
            hasAppeared: false,
            isHovered: false,
            reduceMotion: false
        )
        let hovered = RouteMapVisualPolicy.motion(
            hasAppeared: true,
            isHovered: true,
            reduceMotion: false
        )
        let reduced = RouteMapVisualPolicy.motion(
            hasAppeared: false,
            isHovered: true,
            reduceMotion: true
        )

        XCTAssertEqual(initial.opacity, 0)
        XCTAssertEqual(initial.verticalOffset, 6)
        XCTAssertEqual(initial.repeatCount, 0)
        XCTAssertEqual(hovered.opacity, 1)
        XCTAssertEqual(hovered.animationDuration, FlightTheme.Animation.quick)
        XCTAssertEqual(hovered.scale, 1.035)
        XCTAssertEqual(hovered.verticalOffset, -2)
        XCTAssertEqual(hovered.repeatCount, 0)
        XCTAssertNil(reduced.animationDuration)
        XCTAssertEqual(reduced.opacity, 1)
        XCTAssertEqual(reduced.scale, 1)
        XCTAssertEqual(reduced.verticalOffset, 0)
        XCTAssertEqual(reduced.repeatCount, 0)
    }

    func testCompactAndStandardResponsivePoliciesRemainStable() {
        let compact = RouteMapLayout.verticalPolicy(availableHeight: 430)
        let standard = RouteMapLayout.verticalPolicy(availableHeight: 520)

        XCTAssertEqual(compact.density, .compact)
        XCTAssertGreaterThanOrEqual(
            compact.mapMinimumHeight,
            RouteMapLayout.minimumUsableMapHeight
        )
        XCTAssertGreaterThanOrEqual(
            compact.listMinimumHeight,
            RouteMapLayout.minimumUsableListHeight
        )
        XCTAssertEqual(standard.density, .standard)
        XCTAssertEqual(standard.mapMinimumHeight, 250)
        XCTAssertEqual(standard.listMinimumHeight, 240)
        XCTAssertEqual(RouteMapLayout.mode(forWidth: 720), .stacked)
    }

    private func makeRoute(
        flights: [FlightRecord],
        totalDistance: Double?,
        measuredCount: Int,
        missingCount: Int
    ) -> RouteAggregate {
        RouteAggregate(
            id: "PEK-YUL",
            airportA: beijing,
            airportB: montreal,
            flights: flights,
            airlines: ["CA · Air China"],
            totalDistanceKilometers: totalDistance,
            measuredDistanceFlightCount: measuredCount,
            missingDistanceFlightCount: missingCount
        )
    }

    private func makeSegment(
        routeID: String,
        index: Int
    ) -> RouteMapSegment {
        RouteMapSegment(
            routeID: routeID,
            segmentIndex: index,
            flightCount: 1,
            coordinates: [
                FlightCoordinate(latitude: 0, longitude: 0),
                FlightCoordinate(latitude: 1, longitude: 1),
            ]
        )
    }

    private func makeRecord(
        id: UUID,
        number: String,
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> FlightRecord {
        FlightRecord(
            id: id,
            flightNumber: number,
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: date,
            departureAirport: Airport(
                iata: beijing.iata,
                icao: "ZBAA",
                name: beijing.name,
                city: beijing.city,
                country: beijing.country,
                countryCode: "CN",
                latitude: beijing.latitude,
                longitude: beijing.longitude,
                timeZoneID: beijing.timeZoneID
            ),
            arrivalAirport: Airport(
                iata: montreal.iata,
                icao: "CYUL",
                name: montreal.name,
                city: montreal.city,
                country: montreal.country,
                countryCode: "CA",
                latitude: montreal.latitude,
                longitude: montreal.longitude,
                timeZoneID: montreal.timeZoneID
            ),
            departureDate: date,
            arrivalDate: date.addingTimeInterval(3_600),
            ownerProfileID: UserProfileDefaults.id
        )
    }

    private var beijing: AirportSnapshot {
        AirportSnapshot(
            iata: "PEK",
            name: "北京首都国际机场",
            city: "北京",
            country: "中国",
            latitude: 40.0801,
            longitude: 116.5846,
            timeZoneID: "Asia/Shanghai"
        )
    }

    private var montreal: AirportSnapshot {
        AirportSnapshot(
            iata: "YUL",
            name: "蒙特利尔特鲁多国际机场",
            city: "蒙特利尔",
            country: "加拿大",
            latitude: 45.4706,
            longitude: -73.7408,
            timeZoneID: "America/Toronto"
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
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        )!
    }
}
