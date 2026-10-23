import Foundation
import XCTest
@testable import FlightLog

final class FlightEditorPresentationTests: XCTestCase {
    func testSectionsHaveStableOrderAndFieldOwnership() {
        XCTAssertEqual(
            FlightEditorSectionPresentation.sections.map(\.id),
            [.identity, .routeAndTime, .travelNotes]
        )
        XCTAssertEqual(
            FlightEditorSectionPresentation.sections.map(\.title),
            ["航班身份", "航线时间", "旅行备注"]
        )
        XCTAssertEqual(
            FlightEditorSectionPresentation.identity.fields,
            [.flightDate, .flightNumber, .airlineCode, .airlineName]
        )
        XCTAssertEqual(
            FlightEditorSectionPresentation.routeAndTime.fields,
            [
                .departureAirport,
                .departureLocalDate,
                .arrivalAirport,
                .arrivalLocalDate,
            ]
        )
        XCTAssertEqual(
            FlightEditorSectionPresentation.travelNotes.fields,
            [.aircraftType, .cabinClass, .seat, .notes]
        )
    }

    func testRequiredFieldsBelongToIdentityAndRouteSections() {
        XCTAssertEqual(
            FlightEditorSectionPresentation.identity.requiredFields,
            [.flightDate, .flightNumber]
        )
        XCTAssertEqual(
            FlightEditorSectionPresentation.routeAndTime.requiredFields,
            [
                .departureAirport,
                .departureLocalDate,
                .arrivalAirport,
                .arrivalLocalDate,
            ]
        )
        XCTAssertTrue(
            FlightEditorSectionPresentation.travelNotes.requiredFields.isEmpty
        )
    }

    func testLookupMapsLocalMovementTimesIntoBoardingPass() {
        let preview = FlightEditorLookupBoardingPassPresentation.make(
            result: lookupResult,
            candidateCount: 1
        )

        XCTAssertEqual(preview.flight.flightNumber, "CA123")
        XCTAssertEqual(preview.flight.date, "2026-11-01")
        XCTAssertEqual(preview.flight.airline, "Air China · CA")
        XCTAssertEqual(preview.flight.departure.iata, "LAX")
        XCTAssertEqual(preview.flight.departure.localTime, "2026-11-01 01:30 · 实际")
        XCTAssertEqual(preview.flight.arrival.iata, "JFK")
        XCTAssertEqual(preview.flight.arrival.localTime, "2026-11-01 13:15 · 修订")
        XCTAssertEqual(preview.flight.duration, "8 小时 45 分钟")
        XCTAssertEqual(preview.actionTitle, "确认填充")
    }

    func testLookupUsesUnknownForMissingTimesAndMultipleCandidateAction() {
        let result = FlightLookupResult(
            flightNumber: "CA123",
            airlineCode: nil,
            airlineName: nil,
            aircraftType: nil,
            departure: FlightLookupMovement(
                airportIATA: "LAX",
                airportTimeZoneID: nil,
                time: nil
            ),
            arrival: FlightLookupMovement(
                airportIATA: "JFK",
                airportTimeZoneID: nil,
                time: nil
            )
        )

        let preview = FlightEditorLookupBoardingPassPresentation.make(
            result: result,
            candidateCount: 2
        )

        XCTAssertEqual(preview.flight.date, "Unknown")
        XCTAssertEqual(preview.flight.departure.localTime, "Unknown")
        XCTAssertEqual(preview.flight.arrival.localTime, "Unknown")
        XCTAssertEqual(preview.flight.duration, "Unknown")
        XCTAssertEqual(preview.actionTitle, "选择此航班")
    }

    func testLookupPreviewCannotContainNonAPITravelNotes() {
        let localOnlyValue = "靠窗座位，纪念第一次跨洋飞行"
        let preview = FlightEditorLookupBoardingPassPresentation.make(
            result: lookupResult,
            candidateCount: 1
        )

        XCTAssertFalse(
            preview.flight.accessibilityLabel.contains(localOnlyValue)
        )
        XCTAssertEqual(
            preview.displayedFields,
            [
                .flightNumber,
                .date,
                .airline,
                .route,
                .cities,
                .localTimes,
                .duration,
            ]
        )
    }

    func testValidationAndDSTActionCopyContractsRemainStable() {
        XCTAssertEqual(
            FlightEditorPresentationCopy.validationAction,
            "请修正表单中标出的字段后再保存。"
        )
        XCTAssertEqual(
            FlightEditorPresentationCopy.dstExplanation,
            "夏令时回拨导致该时间出现两次，请选择第一次或第二次。"
        )
        XCTAssertEqual(
            FlightEditorPresentationCopy.dstActionTitles,
            ["第一次", "第二次"]
        )
    }

    func testSectionContainerContainsChildrenWithoutRepeatingVisibleHeaderLabel() {
        for section in FlightEditorSectionPresentation.sections {
            XCTAssertTrue(section.accessibility.containsChildren)
            XCTAssertNil(section.accessibility.containerLabel)
            XCTAssertTrue(section.accessibility.exposesVisibleHeader)
        }
    }

    private var lookupResult: FlightLookupResult {
        FlightLookupResult(
            flightNumber: "CA123",
            airlineCode: "CA",
            airlineName: "Air China",
            aircraftType: "Boeing 787-9",
            departure: FlightLookupMovement(
                airportIATA: "LAX",
                airportTimeZoneID: "America/Los_Angeles",
                time: FlightLookupTime(
                    absoluteDate: iso("2026-11-01T09:30:00Z"),
                    local: "2026-11-01T01:30:00",
                    source: .runway
                )
            ),
            arrival: FlightLookupMovement(
                airportIATA: "JFK",
                airportTimeZoneID: "America/New_York",
                time: FlightLookupTime(
                    absoluteDate: iso("2026-11-01T18:15:00Z"),
                    local: "2026-11-01T13:15:00",
                    source: .revised
                )
            )
        )
    }

    private func iso(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
