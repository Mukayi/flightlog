import Foundation

struct FlightBusinessKey: Hashable, Sendable {
    let flightNumber: String
    let localDepartureDate: Date
    let departureIATA: String
    let arrivalIATA: String

    init(_ record: FlightRecord) {
        self.init(
            flightNumber: record.flightNumber,
            departureDate: record.departureDate,
            departureLocalDateTime: record.departureLocalDateTime,
            departureTimeZoneID: record.departureTimeZoneID,
            departureIATA: record.departureAirportIATA,
            arrivalIATA: record.arrivalAirportIATA
        )
    }

    init(_ dto: FlightRecordBackupDTO) {
        self.init(
            flightNumber: dto.flightNumber,
            departureDate: dto.departureDate,
            departureLocalDateTime: dto.departureLocalDateTime,
            departureTimeZoneID: dto.departureTimeZoneID,
            departureIATA: dto.departureAirportIATA,
            arrivalIATA: dto.arrivalAirportIATA
        )
    }

    private init(
        flightNumber: String,
        departureDate: Date,
        departureLocalDateTime: String?,
        departureTimeZoneID: String,
        departureIATA: String,
        arrivalIATA: String
    ) {
        self.flightNumber = FlightRecordNormalization.code(flightNumber)
        localDepartureDate = FlightDateNormalization.canonicalDate(
            HistoricalLocalTime.wallClockDate(
                snapshot: departureLocalDateTime,
                absoluteDate: departureDate,
                timeZoneID: departureTimeZoneID
            )
        )
        self.departureIATA = FlightRecordNormalization.code(departureIATA)
        self.arrivalIATA = FlightRecordNormalization.code(arrivalIATA)
    }
}
