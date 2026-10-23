import Foundation

enum LocalDateTimeConversionError: Error, Equatable {
    case invalidTimeZone
    case nonexistentLocalTime
    case ambiguousLocalTime
}

enum LocalDateTimeConverter {
    static func absoluteDate(
        from wallClockDate: Date,
        timeZoneID: String
    ) throws -> Date {
        let resolution = try LocalWallClockResolver.resolve(
            wallClockDate,
            timeZoneID: timeZoneID
        )
        guard !resolution.isAmbiguous else {
            throw LocalDateTimeConversionError.ambiguousLocalTime
        }
        return resolution.candidates[0].absoluteDate
    }

    static func wallClockDate(
        from absoluteDate: Date,
        timeZoneID: String
    ) throws -> Date {
        try LocalWallClockResolver.wallClockDate(
            from: absoluteDate,
            timeZoneID: timeZoneID
        )
    }
}

struct FlightValidationResult {
    let errors: [FlightDraftField: String]
    let departureAirport: Airport?
    let arrivalAirport: Airport?
    let departureDate: Date?
    let arrivalDate: Date?
    let departureLocalDateTime: String?
    let departureUTCOffsetSeconds: Int?
    let arrivalLocalDateTime: String?
    let arrivalUTCOffsetSeconds: Int?

    var isValid: Bool {
        errors.isEmpty
    }

    var durationMinutes: Int? {
        guard
            let departureDate,
            let arrivalDate
        else {
            return nil
        }
        return FlightMetricsService.standard.durationMinutes(
            departureDate: departureDate,
            arrivalDate: arrivalDate
        )
    }
}

struct FlightValidator {
    let repository: AirportRepository

    func validate(_ draft: FlightDraft) -> FlightValidationResult {
        var errors: [FlightDraftField: String] = [:]

        if draft.normalizedFlightNumber.isEmpty {
            errors[.flightNumber] = "请输入航班号。"
        } else if draft.normalizedFlightNumber.count > 20 {
            errors[.flightNumber] = "航班号不能超过 20 个字符。"
        }

        validateLength(
            draft.airlineCode,
            maximum: 10,
            field: .airlineCode,
            label: "航司代码",
            errors: &errors
        )
        validateLength(
            draft.airlineName,
            maximum: 120,
            field: .airlineName,
            label: "航司名称",
            errors: &errors
        )
        validateLength(
            draft.aircraftType,
            maximum: 80,
            field: .aircraftType,
            label: "机型",
            errors: &errors
        )
        validateLength(
            draft.cabinClass,
            maximum: 40,
            field: .cabinClass,
            label: "舱位",
            errors: &errors
        )
        validateLength(
            draft.seat,
            maximum: 20,
            field: .seat,
            label: "座位",
            errors: &errors
        )
        validateLength(
            draft.notes,
            maximum: 2_000,
            field: .notes,
            label: "备注",
            errors: &errors
        )

        let departureAirport = canonicalAirport(
            draft.departureAirport,
            field: .departureAirport,
            requiredMessage: "请选择出发机场。",
            usesSavedSnapshot: draft.usesSavedDepartureAirport,
            errors: &errors
        )
        let arrivalAirport = canonicalAirport(
            draft.arrivalAirport,
            field: .arrivalAirport,
            requiredMessage: "请选择到达机场。",
            usesSavedSnapshot: draft.usesSavedArrivalAirport,
            errors: &errors
        )

        if
            let departureAirport,
            let arrivalAirport,
            departureAirport.iata == arrivalAirport.iata
        {
            errors[.arrivalAirport] = "到达机场不能与出发机场相同。"
        }

        let departureResolution = convertedDate(
            draft.departureLocalDate,
            airport: departureAirport,
            unchangedAbsoluteDate: draft.unchangedDepartureDate,
            unchangedLocalDateTime: draft.unchangedDepartureLocalDateTime,
            unchangedUTCOffsetSeconds:
                draft.unchangedDepartureUTCOffsetSeconds,
            occurrence: draft.departureLocalTimeOccurrence,
            field: .departureLocalDate,
            errors: &errors
        )
        let arrivalResolution = convertedDate(
            draft.arrivalLocalDate,
            airport: arrivalAirport,
            unchangedAbsoluteDate: draft.unchangedArrivalDate,
            unchangedLocalDateTime: draft.unchangedArrivalLocalDateTime,
            unchangedUTCOffsetSeconds:
                draft.unchangedArrivalUTCOffsetSeconds,
            occurrence: draft.arrivalLocalTimeOccurrence,
            field: .arrivalLocalDate,
            errors: &errors
        )
        let departureDate = departureResolution?.absoluteDate
        let arrivalDate = arrivalResolution?.absoluteDate

        if
            let departureDate,
            let arrivalDate,
            arrivalDate <= departureDate
        {
            errors[.arrivalLocalDate] = "到达时间必须晚于起飞时间。"
        }

        return FlightValidationResult(
            errors: errors,
            departureAirport: departureAirport,
            arrivalAirport: arrivalAirport,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            departureLocalDateTime: departureResolution?.localDateTime,
            departureUTCOffsetSeconds:
                departureResolution?.utcOffsetSeconds,
            arrivalLocalDateTime: arrivalResolution?.localDateTime,
            arrivalUTCOffsetSeconds: arrivalResolution?.utcOffsetSeconds
        )
    }

    private func canonicalAirport(
        _ airport: Airport?,
        field: FlightDraftField,
        requiredMessage: String,
        usesSavedSnapshot: Bool,
        errors: inout [FlightDraftField: String]
    ) -> Airport? {
        guard let airport else {
            errors[field] = requiredMessage
            return nil
        }
        if usesSavedSnapshot {
            return airport
        }
        guard let canonical = repository.airport(iata: airport.iata) else {
            errors[field] = "请选择机场库中的有效机场。"
            return nil
        }
        return canonical
    }

    private func convertedDate(
        _ wallClockDate: Date,
        airport: Airport?,
        unchangedAbsoluteDate: Date?,
        unchangedLocalDateTime: String?,
        unchangedUTCOffsetSeconds: Int?,
        occurrence: LocalWallClockOccurrence,
        field: FlightDraftField,
        errors: inout [FlightDraftField: String]
    ) -> ValidatedLocalDateTime? {
        guard let airport else { return nil }
        if let unchangedAbsoluteDate {
            let localDateTime = unchangedLocalDateTime
                ?? LocalWallClockResolver.stableString(from: wallClockDate)
            let offset = unchangedUTCOffsetSeconds
                ?? TimeZone(identifier: airport.timeZoneID)?
                .secondsFromGMT(for: unchangedAbsoluteDate)
                ?? 0
            return ValidatedLocalDateTime(
                absoluteDate: unchangedAbsoluteDate,
                localDateTime: localDateTime,
                utcOffsetSeconds: offset
            )
        }
        do {
            let resolution = try LocalWallClockResolver.resolve(
                wallClockDate,
                timeZoneID: airport.timeZoneID
            )
            let candidate = resolution.candidate(for: occurrence)
            return ValidatedLocalDateTime(
                absoluteDate: candidate.absoluteDate,
                localDateTime: resolution.localDateTime,
                utcOffsetSeconds: candidate.utcOffsetSeconds
            )
        } catch {
            errors[field] = "该机场当地时间无效，请重新选择。"
            return nil
        }
    }

    private func validateLength(
        _ value: String,
        maximum: Int,
        field: FlightDraftField,
        label: String,
        errors: inout [FlightDraftField: String]
    ) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).count > maximum {
            errors[field] = "\(label)不能超过 \(maximum) 个字符。"
        }
    }
}

private struct ValidatedLocalDateTime {
    let absoluteDate: Date
    let localDateTime: String
    let utcOffsetSeconds: Int
}
