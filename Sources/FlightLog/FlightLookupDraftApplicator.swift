import Foundation

enum FlightLookupApplyError: LocalizedError, Equatable {
    case airportNotFound(String)
    case invalidLocalTime(String)

    var errorDescription: String? {
        switch self {
        case .airportNotFound(let iata):
            "机场 \(iata) 不在本地机场库中，草稿未作修改。"
        case .invalidLocalTime(let iata):
            "无法把 \(iata) 的查询时间可靠转换为当地时间，草稿未作修改。"
        }
    }
}

struct FlightLookupApplyReport: Sendable, Equatable {
    let filledFields: [String]
}

enum FlightLookupDraftApplicator {
    static func apply(
        _ result: FlightLookupResult,
        to draft: inout FlightDraft,
        repository: AirportRepository
    ) throws -> FlightLookupApplyReport {
        guard
            let departureAirport = repository.airport(
                iata: result.departure.airportIATA
            )
        else {
            throw FlightLookupApplyError.airportNotFound(
                result.departure.airportIATA
            )
        }
        guard
            let arrivalAirport = repository.airport(
                iata: result.arrival.airportIATA
            )
        else {
            throw FlightLookupApplyError.airportNotFound(
                result.arrival.airportIATA
            )
        }

        var updated = draft
        var fields: [String] = []
        if let value = nonempty(result.flightNumber) {
            updated.flightNumber = value
            fields.append("航班号")
        }
        updated.departureAirport = departureAirport
        updated.arrivalAirport = arrivalAirport
        fields.append(contentsOf: ["出发机场", "到达机场"])

        if let value = nonempty(result.airlineCode) {
            updated.airlineCode = value
            fields.append("航司代码")
        }
        if let value = nonempty(result.airlineName) {
            updated.airlineName = value
            fields.append("航司名称")
        }
        if let value = nonempty(result.aircraftType) {
            updated.aircraftType = value
            fields.append("机型")
        }
        if let time = result.departure.time {
            let local = try localSelection(
                time,
                airport: departureAirport
            )
            updated.departureLocalDate = local.date
            updated.departureLocalTimeOccurrence = local.occurrence
            fields.append("当地起飞时间（\(time.source.title)）")
        }
        if let time = result.arrival.time {
            let local = try localSelection(time, airport: arrivalAirport)
            updated.arrivalLocalDate = local.date
            updated.arrivalLocalTimeOccurrence = local.occurrence
            fields.append("当地到达时间（\(time.source.title)）")
        }
        updated.flightDate = FlightDateNormalization.canonicalDate(
            updated.departureLocalDate
        )
        draft = updated
        return FlightLookupApplyReport(filledFields: fields)
    }

    private static func localSelection(
        _ time: FlightLookupTime,
        airport: Airport
    ) throws -> (date: Date, occurrence: LocalWallClockOccurrence) {
        guard
            let wallClock = try? LocalWallClockResolver.wallClockDate(
                from: time.absoluteDate,
                timeZoneID: airport.timeZoneID
            ),
            let resolution = try? LocalWallClockResolver.resolve(
                wallClock,
                timeZoneID: airport.timeZoneID
            )
        else {
            throw FlightLookupApplyError.invalidLocalTime(airport.iata)
        }
        let occurrence = resolution.candidates.first(where: {
            abs($0.absoluteDate.timeIntervalSince(time.absoluteDate)) < 1
        })?.occurrence ?? .first
        return (wallClock, occurrence)
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
