import Foundation
import XCTest
@testable import FlightLog

final class FlightPagesPresentationTests: XCTestCase {
    func testCardFactoryUsesSavedHistoricalLocalSnapshots() {
        let record = makeRecord()
        record.departureLocalDateTime = "1945-08-15T12:34:00"
        record.departureUTCOffsetSeconds = 32_400
        record.departureTimeZoneID = "Etc/UTC"
        record.arrivalLocalDateTime = "1945-08-15T18:45:00"
        record.arrivalUTCOffsetSeconds = 20_700
        record.arrivalTimeZoneID = "Etc/UTC"

        let card = FlightCardPresentationFactory.make(record)

        XCTAssertEqual(card.departure.localTime, "12:34")
        XCTAssertEqual(card.arrival.localTime, "18:45")
    }

    func testCardFactoryNormalizesUnknownValues() {
        let record = makeRecord(
            flightNumber: "",
            airlineCode: "",
            airlineName: "",
            departure: unknownAirport,
            arrival: unknownAirport
        )

        let card = FlightCardPresentationFactory.make(record)

        XCTAssertEqual(card.flightNumber, "Unknown")
        XCTAssertEqual(card.airline, "Unknown")
        XCTAssertEqual(card.departure.iata, "Unknown")
        XCTAssertEqual(card.departure.city, "Unknown")
        XCTAssertEqual(card.arrival.iata, "Unknown")
    }

    func testDetailPresentationContainsEveryArchiveFieldAndAccurateSource() {
        let record = makeRecord(
            aircraftType: "Boeing 787-9",
            cabinClass: "公务舱",
            seat: "7A",
            notes: "历史首航",
            updatedAt: date(2026, 8, 19, 7, 8)
        )

        let detail = FlightDetailPresentation(record: record)
        let fields = detail.archiveSections.flatMap(\.fields)

        XCTAssertEqual(
            Set(fields.map(\.title)),
            Set([
                "出发机场",
                "出发时区",
                "到达机场",
                "到达时区",
                "机型",
                "舱位",
                "座位",
                "备注",
                "数据来源",
                "更新时间",
            ])
        )
        XCTAssertEqual(
            fields.first { $0.title == "数据来源" }?.value,
            "本地航班记录"
        )
        XCTAssertEqual(
            fields.first { $0.title == "机型" }?.value,
            "Boeing 787-9"
        )
        XCTAssertEqual(fields.first { $0.title == "舱位" }?.value, "公务舱")
        XCTAssertEqual(fields.first { $0.title == "座位" }?.value, "7A")
        XCTAssertEqual(fields.first { $0.title == "备注" }?.value, "历史首航")
    }

    func testDetailPresentationKeepsMissingArchiveFieldsAsUnknown() {
        let detail = FlightDetailPresentation(
            record: makeRecord(
                aircraftType: nil,
                cabinClass: " ",
                seat: nil,
                notes: ""
            )
        )
        let fields = detail.archiveSections.flatMap(\.fields)

        for title in ["机型", "舱位", "座位", "备注"] {
            XCTAssertEqual(
                fields.first { $0.title == title }?.value,
                "Unknown",
                title
            )
        }
    }

    func testJourneyTimelineUsesSnapshotOffsetAndDuration() {
        let record = makeRecord()
        record.departureLocalDateTime = "1999-12-31T23:45:00"
        record.departureUTCOffsetSeconds = 20_700
        record.departureTimeZoneID = "Etc/UTC"

        let journey = JourneyTimelinePresentation(record: record)

        XCTAssertTrue(journey.departureLocalTime.contains("1999年12月31日 23:45"))
        XCTAssertTrue(journey.departureLocalTime.contains("UTC+05:45"))
        XCTAssertEqual(journey.duration, "13 小时")
        XCTAssertTrue(journey.accessibility.value.contains("当地起飞"))
        XCTAssertTrue(journey.accessibility.value.contains("当地到达"))
        XCTAssertEqual(journey.layoutContract, .unboundedText)
    }

    func testSelectedLayoutPolicyRemovesTranslationForReduceMotion() {
        let selected = FlightRowSelectionLayoutPolicy.resolve(
            isSelected: true,
            reduceMotion: false
        )
        XCTAssertGreaterThan(selected.horizontalOffset, 0)
        XCTAssertGreaterThan(selected.borderWidth, 0)
        XCTAssertGreaterThan(selected.shadowRadius, 0)
        XCTAssertNotNil(selected.animationDuration)

        let reduced = FlightRowSelectionLayoutPolicy.resolve(
            isSelected: true,
            reduceMotion: true
        )
        XCTAssertEqual(reduced.horizontalOffset, 0)
        XCTAssertGreaterThan(reduced.borderWidth, 0)
        XCTAssertGreaterThan(reduced.shadowRadius, 0)
        XCTAssertNil(reduced.animationDuration)

        let unselected = FlightRowSelectionLayoutPolicy.resolve(
            isSelected: false,
            reduceMotion: false
        )
        XCTAssertEqual(unselected.horizontalOffset, 0)
        XCTAssertEqual(unselected.borderWidth, 0)
        XCTAssertEqual(unselected.shadowRadius, 0)
    }

    func testFlightBrowserCopySupportsChineseAndDistinctEmptyStates() {
        XCTAssertEqual(
            FlightBrowserPresentation.searchPrompt,
            "支持中文，搜索航班、航司、机场或城市"
        )
        XCTAssertEqual(
            FlightBrowserPresentation.emptyRecordsTitle,
            "创建第一枚旅程签章"
        )
        XCTAssertEqual(
            FlightBrowserPresentation.noMatchesTitle,
            "没有匹配的航班"
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
            name: "蒙特利尔皮埃尔·埃利奥特·特鲁多国际机场",
            city: "蒙特利尔",
            country: "加拿大",
            countryCode: "CA",
            latitude: 45.4706,
            longitude: -73.7408,
            timeZoneID: "America/Toronto"
        )
    }

    private var unknownAirport: Airport {
        Airport(
            iata: "",
            icao: "",
            name: "",
            city: "",
            country: "",
            countryCode: "",
            latitude: 0,
            longitude: 0,
            timeZoneID: "Etc/UTC"
        )
    }

    private func makeRecord(
        flightNumber: String = "CA937",
        airlineCode: String = "CA",
        airlineName: String = "中国国际航空",
        departure: Airport? = nil,
        arrival: Airport? = nil,
        aircraftType: String? = nil,
        cabinClass: String? = nil,
        seat: String? = nil,
        notes: String? = nil,
        updatedAt: Date? = nil
    ) -> FlightRecord {
        FlightRecord(
            flightNumber: flightNumber,
            airlineCode: airlineCode,
            airlineName: airlineName,
            flightDate: date(2026, 8, 18),
            departureAirport: departure ?? beijing,
            arrivalAirport: arrival ?? montreal,
            departureDate: date(2026, 8, 18, 2),
            arrivalDate: date(2026, 8, 18, 15),
            aircraftType: aircraftType,
            cabinClass: cabinClass,
            seat: seat,
            notes: notes,
            ownerProfileID: UserProfileDefaults.id,
            createdAt: date(2026, 8, 1),
            updatedAt: updatedAt ?? date(2026, 8, 19)
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
