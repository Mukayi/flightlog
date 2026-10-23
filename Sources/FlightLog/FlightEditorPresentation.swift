import Foundation

enum FlightEditorSectionID: String, Equatable {
    case identity
    case routeAndTime
    case travelNotes
}

struct FlightEditorSectionAccessibility: Equatable {
    let containsChildren: Bool
    let containerLabel: String?
    let exposesVisibleHeader: Bool
}

struct FlightEditorSectionPresentation: Equatable {
    let id: FlightEditorSectionID
    let title: String
    let narrative: String
    let eyebrow: String
    let fields: [FlightDraftField]
    let requiredFields: [FlightDraftField]

    var accessibility: FlightEditorSectionAccessibility {
        FlightEditorSectionAccessibility(
            containsChildren: true,
            containerLabel: nil,
            exposesVisibleHeader: true
        )
    }

    static let identity = FlightEditorSectionPresentation(
        id: .identity,
        title: "航班身份",
        narrative: "记录航班号与承运航司，并可按当地起飞日期联网查询。",
        eyebrow: "PASSPORT PAGE 01",
        fields: [.flightDate, .flightNumber, .airlineCode, .airlineName],
        requiredFields: [.flightDate, .flightNumber]
    )

    static let routeAndTime = FlightEditorSectionPresentation(
        id: .routeAndTime,
        title: "航线时间",
        narrative: "以机场当地时间记录起降，跨时区与夏令时会在保存时准确换算。",
        eyebrow: "PASSPORT PAGE 02",
        fields: [
            .departureAirport,
            .departureLocalDate,
            .arrivalAirport,
            .arrivalLocalDate,
        ],
        requiredFields: [
            .departureAirport,
            .departureLocalDate,
            .arrivalAirport,
            .arrivalLocalDate,
        ]
    )

    static let travelNotes = FlightEditorSectionPresentation(
        id: .travelNotes,
        title: "旅行备注",
        narrative: "补充机型、舱位、座位与只属于这段旅程的私人记忆。",
        eyebrow: "PASSPORT PAGE 03",
        fields: [.aircraftType, .cabinClass, .seat, .notes],
        requiredFields: []
    )

    static let sections = [identity, routeAndTime, travelNotes]
}

struct FlightEditorLookupBoardingPassPresentation: Equatable {
    let flight: FlightPresentation
    let actionTitle: String
    let displayedFields: [FlightPresentationField]

    static func make(
        result: FlightLookupResult,
        candidateCount: Int
    ) -> FlightEditorLookupBoardingPassPresentation {
        let departureTime = movementTime(result.departure)
        let arrivalTime = movementTime(result.arrival)
        let date = departureTime.map { String($0.prefix(10)) }
        let duration = duration(
            departure: result.departure.time,
            arrival: result.arrival.time
        )
        let airline = [result.airlineName, result.airlineCode]
            .compactMap { value -> String? in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " · ")

        return FlightEditorLookupBoardingPassPresentation(
            flight: FlightPresentation(
                flightNumber: result.flightNumber,
                date: date,
                airline: airline,
                departure: FlightEndpointPresentation(
                    iata: result.departure.airportIATA,
                    city: nil,
                    localTime: departureTime
                ),
                arrival: FlightEndpointPresentation(
                    iata: result.arrival.airportIATA,
                    city: nil,
                    localTime: arrivalTime
                ),
                duration: duration
            ),
            actionTitle: candidateCount == 1
                ? "确认填充"
                : "选择此航班",
            displayedFields: FlightCardDensity.full.visibleFields
        )
    }

    private static func movementTime(
        _ movement: FlightLookupMovement
    ) -> String? {
        guard let time = movement.time else { return nil }
        return "\(FlightLookupPresentation.localTime(time.local)) · \(time.source.title)"
    }

    private static func duration(
        departure: FlightLookupTime?,
        arrival: FlightLookupTime?
    ) -> String? {
        guard
            let departure,
            let arrival,
            arrival.absoluteDate > departure.absoluteDate
        else {
            return nil
        }
        let minutes = Int(
            arrival.absoluteDate.timeIntervalSince(departure.absoluteDate) / 60
        )
        return FlightDisplayFormatting.duration(minutes: minutes)
    }
}

enum FlightEditorPresentationCopy {
    static let validationAction = "请修正表单中标出的字段后再保存。"
    static let dstExplanation =
        "夏令时回拨导致该时间出现两次，请选择第一次或第二次。"
    static let dstActionTitles = LocalWallClockOccurrence.allCases.map(\.title)
}
