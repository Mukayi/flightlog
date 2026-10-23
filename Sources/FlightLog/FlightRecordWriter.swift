import Foundation

enum FlightRecordWriteError: LocalizedError {
    case validation([FlightDraftField: String])
    case ownerMismatch

    var errorDescription: String? {
        switch self {
        case .validation:
            "请修正表单中的错误后再保存。"
        case .ownerMismatch:
            "这条记录不属于当前用户，无法修改。"
        }
    }
}

enum FlightRecordWriter {
    static func makeRecord(
        from draft: FlightDraft,
        repository: AirportRepository,
        ownerProfileID: UUID,
        now: Date = .now
    ) throws -> FlightRecord {
        try makeBackupSnapshot(
            from: draft,
            repository: repository,
            ownerProfileID: ownerProfileID,
            now: now
        ).makeRecord(ownerProfileID: ownerProfileID)
    }

    static func makeBackupSnapshot(
        from draft: FlightDraft,
        repository: AirportRepository,
        ownerProfileID: UUID,
        now: Date = .now
    ) throws -> FlightRecordBackupDTO {
        let validated = FlightValidator(repository: repository).validate(draft)
        guard
            validated.isValid,
            let departureAirport = validated.departureAirport,
            let arrivalAirport = validated.arrivalAirport,
            let departureDate = validated.departureDate,
            let arrivalDate = validated.arrivalDate,
            let departureLocalDateTime =
                validated.departureLocalDateTime,
            let departureUTCOffsetSeconds =
                validated.departureUTCOffsetSeconds,
            let arrivalLocalDateTime = validated.arrivalLocalDateTime,
            let arrivalUTCOffsetSeconds =
                validated.arrivalUTCOffsetSeconds
        else {
            throw FlightRecordWriteError.validation(validated.errors)
        }

        return FlightRecordBackupDTO(
            flightNumber: draft.normalizedFlightNumber,
            airlineCode: FlightRecordNormalization.code(draft.airlineCode),
            airlineName: trimmed(draft.airlineName),
            flightDate: FlightDateNormalization.canonicalDate(
                draft.departureLocalDate
            ),
            departureAirport: departureAirport,
            arrivalAirport: arrivalAirport,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            departureLocalDateTime: departureLocalDateTime,
            departureUTCOffsetSeconds: departureUTCOffsetSeconds,
            arrivalLocalDateTime: arrivalLocalDateTime,
            arrivalUTCOffsetSeconds: arrivalUTCOffsetSeconds,
            aircraftType: optionalValue(draft.aircraftType),
            cabinClass: optionalValue(draft.cabinClass),
            seat: optionalValue(draft.seat),
            notes: optionalValue(draft.notes),
            ownerProfileID: ownerProfileID,
            createdAt: now,
            updatedAt: now
        )
    }

    static func update(
        _ record: FlightRecord,
        from draft: FlightDraft,
        repository: AirportRepository,
        ownerProfileID: UUID,
        now: Date = .now
    ) throws {
        guard record.ownerProfileID == ownerProfileID else {
            throw FlightRecordWriteError.ownerMismatch
        }
        let validated = FlightValidator(repository: repository).validate(draft)
        guard
            validated.isValid,
            let departureAirport = validated.departureAirport,
            let arrivalAirport = validated.arrivalAirport,
            let departureDate = validated.departureDate,
            let arrivalDate = validated.arrivalDate,
            let departureLocalDateTime =
                validated.departureLocalDateTime,
            let departureUTCOffsetSeconds =
                validated.departureUTCOffsetSeconds,
            let arrivalLocalDateTime = validated.arrivalLocalDateTime,
            let arrivalUTCOffsetSeconds =
                validated.arrivalUTCOffsetSeconds
        else {
            throw FlightRecordWriteError.validation(validated.errors)
        }

        record.flightNumber = draft.normalizedFlightNumber
        record.airlineCode = FlightRecordNormalization.code(draft.airlineCode)
        record.airlineName = trimmed(draft.airlineName)
        record.flightDate = FlightDateNormalization.canonicalDate(
            draft.departureLocalDate
        )

        record.departureAirportIATA = departureAirport.iata
        record.departureDate = departureDate
        record.departureTimeZoneID = departureAirport.timeZoneID
        record.departureLocalDateTime = departureLocalDateTime
        record.departureUTCOffsetSeconds = departureUTCOffsetSeconds
        record.departureAirportName = departureAirport.name
        record.departureCity = departureAirport.city
        record.departureCountry = departureAirport.country
        record.departureCountryCode = departureAirport.countryCode
        record.departureLatitude = departureAirport.latitude
        record.departureLongitude = departureAirport.longitude

        record.arrivalAirportIATA = arrivalAirport.iata
        record.arrivalDate = arrivalDate
        record.arrivalTimeZoneID = arrivalAirport.timeZoneID
        record.arrivalLocalDateTime = arrivalLocalDateTime
        record.arrivalUTCOffsetSeconds = arrivalUTCOffsetSeconds
        record.arrivalAirportName = arrivalAirport.name
        record.arrivalCity = arrivalAirport.city
        record.arrivalCountry = arrivalAirport.country
        record.arrivalCountryCode = arrivalAirport.countryCode
        record.arrivalLatitude = arrivalAirport.latitude
        record.arrivalLongitude = arrivalAirport.longitude

        record.aircraftType = optionalValue(draft.aircraftType)
        record.cabinClass = optionalValue(draft.cabinClass)
        record.seat = optionalValue(draft.seat)
        record.notes = optionalValue(draft.notes)
        record.markUpdated(at: now)
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func optionalValue(_ value: String) -> String? {
        let value = trimmed(value)
        return value.isEmpty ? nil : value
    }
}
