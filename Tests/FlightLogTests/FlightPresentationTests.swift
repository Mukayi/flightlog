import XCTest
@testable import FlightLog

final class FlightPresentationTests: XCTestCase {
    func testAirportSearchPromptExplicitlyMentionsChineseAndCodes() {
        XCTAssertEqual(
            AirportSearchPresentation.prompt,
            "支持中文、IATA/ICAO、机场或城市"
        )
    }

    func testAirportSearchAliasTextShowsOnlyFirstThreeChineseAliases() {
        let airport = Airport(
            iata: "LHR",
            icao: "EGLL",
            name: "London Heathrow Airport",
            city: "London",
            country: "United Kingdom",
            countryCode: "GB",
            latitude: 51.4700,
            longitude: -0.4543,
            timeZoneID: "Europe/London",
            aliases: ["London", "伦敦", "希思罗", "倫敦", "Heathrow"]
        )

        XCTAssertEqual(
            AirportSearchPresentation.chineseAliasText(for: airport),
            "伦敦、希思罗、倫敦"
        )
    }

    func testDurationTextPreservesRemainingMinutes() {
        XCTAssertEqual(
            FlightDisplayFormatting.duration(minutes: 325),
            "5 小时 25 分钟"
        )
    }

    func testDurationTextShowsUnknownForMissingAndNonPositiveValues() {
        XCTAssertEqual(
            FlightDisplayFormatting.duration(minutes: nil),
            "未知"
        )
        XCTAssertEqual(
            FlightDisplayFormatting.duration(minutes: 0),
            "未知"
        )
        XCTAssertEqual(
            FlightDisplayFormatting.duration(minutes: -15),
            "未知"
        )
    }

    func testRouteDistanceTextDistinguishesUnknownPartialAndCompleteTotals() {
        XCTAssertEqual(
            FlightDisplayFormatting.routeDistance(
                kilometers: nil,
                unit: .kilometers,
                missingFlightCount: 2
            ),
            "未知"
        )
        XCTAssertEqual(
            FlightDisplayFormatting.routeDistance(
                kilometers: 1_000,
                unit: .kilometers,
                missingFlightCount: 1
            ),
            "1,000 公里（另有 1 次无法计算）"
        )
        XCTAssertEqual(
            FlightDisplayFormatting.routeDistance(
                kilometers: 1_000,
                unit: .kilometers,
                missingFlightCount: 0
            ),
            "1,000 公里"
        )
    }

    func testVisitedAirportMetricContractExplainsIATADeduplication() {
        XCTAssertEqual(VisitMetricPresentation.airportTitle, "到访机场")
        XCTAssertEqual(
            VisitMetricPresentation.airportDetail,
            "所有有 IATA 代码的出发与到达机场按 IATA 去重，同一机场多次只算一次"
        )
    }

    func testVisitedCityMetricContractExplainsCityCountryDeduplication() {
        XCTAssertEqual(VisitMetricPresentation.cityTitle, "到访城市")
        XCTAssertEqual(
            VisitMetricPresentation.cityDetail,
            "按城市+国家去重，同城多个机场只算一个城市（例如 LHR/LGW 为 2 机场 1 城市）"
        )
    }
}
