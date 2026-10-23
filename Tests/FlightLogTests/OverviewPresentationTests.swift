import Foundation
import XCTest
@testable import FlightLog

final class OverviewPresentationTests: XCTestCase {
    private let statistics = FlightStatisticsService()

    func testHeroUsesActiveProfileNameWithoutCollectingExtraIdentityData() {
        let record = makeRecord(
            id: uuid(1),
            flightNumber: "MU5101",
            flightDate: date(2022, 6, 1)
        )

        let presentation = makePresentation(
            [record],
            holderDisplayName: "Alice Zhang"
        )

        XCTAssertEqual(presentation.hero.title, "我的飞行护照")
        XCTAssertEqual(presentation.hero.holder, "Alice Zhang")
        XCTAssertEqual(presentation.hero.firstFlightYear, "2022")
        XCTAssertEqual(presentation.hero.totalFlights, "1 次")
        XCTAssertEqual(
            Set(Mirror(reflecting: presentation.hero).children.compactMap(\.label)),
            ["title", "holder", "firstFlightYear", "totalFlights", "totalDistance"]
        )
    }

    func testHeroUsesNaturalEmptyValues() {
        let presentation = makePresentation([], holderDisplayName: nil)

        XCTAssertEqual(presentation.hero.holder, UserProfileDefaults.displayName)
        XCTAssertEqual(presentation.hero.firstFlightYear, "—")
        XCTAssertEqual(presentation.hero.totalFlights, "0 次")
        XCTAssertEqual(presentation.hero.totalDistance, "未知")
    }

    func testMetricsHaveStableSixItemOrderAndSeparateDetailedExplanations() {
        let presentation = makePresentation([makeRecord(id: uuid(1))])

        XCTAssertEqual(
            presentation.metrics.map(\.id),
            [.flights, .distance, .duration, .airports, .cities, .countries]
        )
        XCTAssertEqual(
            presentation.metrics.map(\.card.title),
            ["飞行次数", "累计里程", "累计时长", "到访机场", "到访城市", "到访国家"]
        )
        XCTAssertTrue(presentation.metrics.allSatisfy { $0.card.detail == nil })
        XCTAssertTrue(presentation.metrics.allSatisfy { !$0.explanation.isEmpty })
    }

    func testAirportExplanationExplicitlyLimitsDeduplicationToIATACodes() throws {
        let presentation = makePresentation([makeRecord(id: uuid(1))])
        let airport = try XCTUnwrap(
            presentation.metrics.first { $0.id == .airports }
        )

        XCTAssertTrue(airport.explanation.contains("仅统计有 IATA 代码"))
        XCTAssertTrue(airport.explanation.contains("去重"))
    }

    func testYearbookPointsPreserveIntegerYearsAndHoverText() {
        let records = [
            makeRecord(id: uuid(1), flightDate: date(2024, 2, 1)),
            makeRecord(id: uuid(2), flightDate: date(2025, 2, 1)),
            makeRecord(id: uuid(3), flightDate: date(2025, 3, 1)),
        ]

        let presentation = makePresentation(records)

        XCTAssertEqual(presentation.yearbook.map(\.year), [2024, 2025])
        XCTAssertEqual(
            presentation.yearbook.map(\.hoverText),
            ["2024 年 · 1 次航班", "2025 年 · 2 次航班"]
        )
    }

    func testRecentFlightsMapToCompactBoardingPassesAndSharedDistanceUnit() throws {
        let older = makeRecord(
            id: uuid(1),
            flightNumber: "CA100",
            flightDate: date(2024, 1, 2),
            durationMinutes: 90
        )
        let newer = makeRecord(
            id: uuid(2),
            flightNumber: "MU200",
            flightDate: date(2025, 3, 4),
            durationMinutes: 125
        )

        let presentation = makePresentation([older, newer], unit: .miles)
        let boarding = try XCTUnwrap(presentation.recentFlights.first)
        let distanceMetric = try XCTUnwrap(
            presentation.metrics.first { $0.id == .distance }
        )

        XCTAssertEqual(presentation.distanceUnit, .miles)
        XCTAssertTrue(distanceMetric.card.value.hasSuffix("英里"))
        XCTAssertEqual(boarding.id, newer.id)
        XCTAssertEqual(boarding.boardingPass.flightNumber, "MU200")
        XCTAssertEqual(boarding.boardingPass.date, "2025年3月4日")
        XCTAssertEqual(boarding.boardingPass.departure.iata, "PVG")
        XCTAssertEqual(boarding.boardingPass.departure.localTime, "08:00")
        XCTAssertEqual(boarding.boardingPass.arrival.iata, "PEK")
        XCTAssertEqual(boarding.boardingPass.arrival.localTime, "10:05")
        XCTAssertEqual(boarding.boardingPass.duration, "2 小时 5 分钟")
    }

    @MainActor
    func testOpenFlightRequestsSelectFlightsAndConsumeOnceEvenForRepeatedID() {
        let state = AppCommandState()
        let id = uuid(7)

        state.requestOpenFlight(id: id)

        XCTAssertEqual(state.selection, .flights)
        XCTAssertEqual(state.takeOpenFlightRequest(), id)
        XCTAssertNil(state.takeOpenFlightRequest())

        state.requestOpenFlight(id: id)

        XCTAssertEqual(state.selection, .flights)
        XCTAssertEqual(state.takeOpenFlightRequest(), id)
        XCTAssertNil(state.takeOpenFlightRequest())
    }

    func testOpenFlightResolutionClearsOnlySearchAndFiltersHidingTarget() throws {
        let target = makeRecord(
            id: uuid(8),
            flightNumber: "MU200",
            flightDate: date(2025, 3, 4)
        )
        let other = makeRecord(
            id: uuid(9),
            flightNumber: "CA100",
            flightDate: date(2024, 1, 2)
        )

        let searchResolution = try XCTUnwrap(
            FlightOpenRequestResolution.resolve(
                requestedID: target.id,
                records: [target, other],
                searchText: "CA100",
                sortOrder: .dateDescending,
                filter: FlightListFilter()
            )
        )
        XCTAssertEqual(searchResolution.selectedID, target.id)
        XCTAssertEqual(searchResolution.searchText, "")
        XCTAssertEqual(searchResolution.filter, FlightListFilter())

        let filterResolution = try XCTUnwrap(
            FlightOpenRequestResolution.resolve(
                requestedID: target.id,
                records: [target, other],
                searchText: "",
                sortOrder: .dateDescending,
                filter: FlightListFilter(year: 2024)
            )
        )
        XCTAssertEqual(filterResolution.selectedID, target.id)
        XCTAssertEqual(filterResolution.searchText, "")
        XCTAssertEqual(filterResolution.filter, FlightListFilter())
    }

    func testOpenFlightResolutionPreservesNonBlockingQueryAndIgnoresMissingID() throws {
        let target = makeRecord(
            id: uuid(10),
            flightNumber: "MU200",
            flightDate: date(2025, 3, 4)
        )
        let filter = FlightListFilter(year: 2025, airline: "MU")

        let resolution = try XCTUnwrap(
            FlightOpenRequestResolution.resolve(
                requestedID: target.id,
                records: [target],
                searchText: "MU",
                sortOrder: .dateDescending,
                filter: filter
            )
        )

        XCTAssertEqual(resolution.selectedID, target.id)
        XCTAssertEqual(resolution.searchText, "MU")
        XCTAssertEqual(resolution.filter, filter)
        XCTAssertNil(
            FlightOpenRequestResolution.resolve(
                requestedID: uuid(999),
                records: [target],
                searchText: "MU",
                sortOrder: .dateDescending,
                filter: filter
            )
        )
    }

    private func makePresentation(
        _ records: [FlightRecord],
        unit: DistanceUnit = .kilometers,
        holderDisplayName: String? = UserProfileDefaults.displayName
    ) -> OverviewPresentation {
        OverviewPresentation(
            records: records,
            snapshot: statistics.snapshot(records),
            distanceUnit: unit,
            holderDisplayName: holderDisplayName
        )
    }

    private func makeRecord(
        id: UUID,
        flightNumber: String = "TEST1",
        flightDate: Date = Date(timeIntervalSince1970: 1_704_067_200),
        durationMinutes: Int = 60
    ) -> FlightRecord {
        let departure = Airport(
            iata: "PVG",
            icao: "ZSPD",
            name: "上海浦东国际机场",
            city: "上海",
            country: "中国",
            countryCode: "CN",
            latitude: 31.1443,
            longitude: 121.8083,
            timeZoneID: "Asia/Shanghai"
        )
        let arrival = Airport(
            iata: "PEK",
            icao: "ZBAA",
            name: "北京首都国际机场",
            city: "北京",
            country: "中国",
            countryCode: "CN",
            latitude: 40.0799,
            longitude: 116.6031,
            timeZoneID: "Asia/Shanghai"
        )
        let departureDate = date(
            Calendar(identifier: .gregorian).component(.year, from: flightDate),
            Calendar(identifier: .gregorian).component(.month, from: flightDate),
            Calendar(identifier: .gregorian).component(.day, from: flightDate),
            0
        )
        return FlightRecord(
            id: id,
            flightNumber: flightNumber,
            airlineCode: String(flightNumber.prefix(2)),
            airlineName: "测试航空",
            flightDate: flightDate,
            departureAirport: departure,
            arrivalAirport: arrival,
            departureDate: departureDate,
            arrivalDate: departureDate.addingTimeInterval(
                TimeInterval(durationMinutes * 60)
            ),
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
