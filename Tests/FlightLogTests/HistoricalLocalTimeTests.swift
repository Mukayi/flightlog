import Foundation
import XCTest
@testable import FlightLog

final class HistoricalLocalTimeTests: XCTestCase {
    func testResolverReturnsOneCandidateForOrdinaryLocalTime() throws {
        let local = wallClockDate(2026, 8, 18, 10, 30)

        let resolution = try LocalWallClockResolver.resolve(
            local,
            timeZoneID: "Asia/Shanghai"
        )

        XCTAssertEqual(resolution.localDateTime, "2026-08-18T10:30:00")
        XCTAssertEqual(resolution.candidates.count, 1)
        XCTAssertEqual(
            resolution.candidates.first?.absoluteDate,
            wallClockDate(2026, 8, 18, 2, 30)
        )
        XCTAssertEqual(resolution.candidates.first?.utcOffsetSeconds, 28_800)
        XCTAssertEqual(resolution.candidates.first?.occurrence, .first)
    }

    func testResolverHandlesHalfHourDSTRepeatedTime() throws {
        let local = wallClockDate(2026, 4, 5, 1, 45)

        let resolution = try LocalWallClockResolver.resolve(
            local,
            timeZoneID: "Australia/Lord_Howe"
        )

        XCTAssertEqual(resolution.candidates.count, 2)
        XCTAssertEqual(
            resolution.candidates.map(\.utcOffsetSeconds),
            [39_600, 37_800]
        )
        XCTAssertEqual(
            resolution.candidates[1].absoluteDate
                .timeIntervalSince(resolution.candidates[0].absoluteDate),
            1_800
        )
    }

    func testResolverStillRejectsNonexistentLocalTime() {
        XCTAssertThrowsError(
            try LocalWallClockResolver.resolve(
                wallClockDate(2026, 3, 8, 2, 30),
                timeZoneID: "America/Los_Angeles"
            )
        ) { error in
            XCTAssertEqual(
                error as? LocalDateTimeConversionError,
                .nonexistentLocalTime
            )
        }
    }

    func testWriterPersistsSelectedWallClockOffsetAndDerivesFlightDate() throws {
        var draft = makeDraft()
        draft.flightDate = wallClockDate(2030, 1, 1, 0, 0)
        draft.departureAirport = losAngeles
        draft.departureLocalDate = wallClockDate(2026, 11, 1, 1, 30)
        draft.departureLocalTimeOccurrence = .second
        draft.arrivalLocalDate = wallClockDate(2026, 11, 2, 8, 0)

        let record = try FlightRecordWriter.makeRecord(
            from: draft,
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )

        XCTAssertEqual(
            record.flightDate,
            wallClockDate(2026, 11, 1, 0, 0)
        )
        XCTAssertEqual(record.departureDate, wallClockDate(2026, 11, 1, 9, 30))
        XCTAssertEqual(
            record.departureLocalDateTime,
            "2026-11-01T01:30:00"
        )
        XCTAssertEqual(record.departureUTCOffsetSeconds, -28_800)
        XCTAssertEqual(record.arrivalLocalDateTime, "2026-11-02T08:00:00")
        XCTAssertNotNil(record.arrivalUTCOffsetSeconds)
    }

    func testEditingOnlyRepeatedHourOccurrenceRecomputesAbsoluteTime() throws {
        var originalDraft = makeDraft()
        originalDraft.departureAirport = losAngeles
        originalDraft.departureLocalDate = wallClockDate(2026, 11, 1, 1, 30)
        originalDraft.departureLocalTimeOccurrence = .second
        originalDraft.arrivalLocalDate = wallClockDate(2026, 11, 1, 8, 0)
        let record = try FlightRecordWriter.makeRecord(
            from: originalDraft,
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )
        let originalDate = record.departureDate
        var edited = FlightDraft(record: record, repository: repository)
        edited.departureLocalTimeOccurrence = .first

        try FlightRecordWriter.update(
            record,
            from: edited,
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )

        XCTAssertEqual(record.departureUTCOffsetSeconds, -25_200)
        XCTAssertEqual(
            originalDate.timeIntervalSince(record.departureDate),
            3_600
        )
    }

    func testDraftReplaysSavedWallClockWithoutCurrentTimeZoneRules() throws {
        let original = try FlightRecordWriter.makeRecord(
            from: makeDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )
        original.departureLocalDateTime = "1945-08-15T12:34:00"
        original.departureUTCOffsetSeconds = 32_400
        original.departureTimeZoneID = "Etc/UTC"

        let replay = FlightDraft(record: original, repository: repository)

        XCTAssertEqual(
            replay.departureLocalDate,
            wallClockDate(1945, 8, 15, 12, 34)
        )
    }

    func testOldRecordWithoutSnapshotFallsBackToTimeZoneConversion() throws {
        let record = try FlightRecordWriter.makeRecord(
            from: makeDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )
        record.departureLocalDateTime = nil
        record.departureUTCOffsetSeconds = nil

        XCTAssertEqual(
            HistoricalLocalTime.localDateTime(
                snapshot: record.departureLocalDateTime,
                absoluteDate: record.departureDate,
                timeZoneID: record.departureTimeZoneID
            ),
            "2026-08-18T10:00:00"
        )
    }

    func testCSVAndDetailFormattingUseSavedSnapshotInsteadOfRecalculation() throws {
        let record = try FlightRecordWriter.makeRecord(
            from: makeDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )
        record.departureLocalDateTime = "1999-12-31T23:45:00"
        record.departureUTCOffsetSeconds = 20_700
        record.departureTimeZoneID = "Etc/UTC"

        let csv = try XCTUnwrap(
            String(
                data: BackupService.exportCSV(records: [record]),
                encoding: .utf8
            )
        )
        let detail = HistoricalLocalTime.displayText(
            snapshot: record.departureLocalDateTime,
            absoluteDate: record.departureDate,
            timeZoneID: record.departureTimeZoneID,
            utcOffsetSeconds: record.departureUTCOffsetSeconds
        )

        XCTAssertTrue(csv.contains("1999-12-31 23:45"))
        XCTAssertTrue(detail.contains("1999年12月31日 23:45"))
        XCTAssertTrue(detail.contains("UTC+05:45"))
    }

    func testJSONRoundTripPreservesHistoricalLocalSnapshotsAndOffsets() throws {
        let original = try FlightRecordWriter.makeRecord(
            from: makeDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )
        let data = try BackupService.exportJSON(records: [original])
        let restored = try XCTUnwrap(
            BackupService.prepareJSONImport(
                data,
                existingRecords: [],
                targetProfileID: UserProfileDefaults.id,
                mode: .replace
            ).records.first
        )

        XCTAssertEqual(
            restored.departureLocalDateTime,
            original.departureLocalDateTime
        )
        XCTAssertEqual(
            restored.departureUTCOffsetSeconds,
            original.departureUTCOffsetSeconds
        )
        XCTAssertEqual(
            restored.arrivalLocalDateTime,
            original.arrivalLocalDateTime
        )
        XCTAssertEqual(
            restored.arrivalUTCOffsetSeconds,
            original.arrivalUTCOffsetSeconds
        )
    }

    func testJSONWithoutHistoricalFieldsRemainsBackwardCompatible() throws {
        let original = try FlightRecordWriter.makeRecord(
            from: makeDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )
        let data = try BackupService.exportJSON(records: [original])
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var records = try XCTUnwrap(object["records"] as? [[String: Any]])
        for key in [
            "departureLocalDateTime",
            "departureUTCOffsetSeconds",
            "arrivalLocalDateTime",
            "arrivalUTCOffsetSeconds",
        ] {
            records[0].removeValue(forKey: key)
        }
        object["records"] = records
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let backup = try BackupService.decodeJSON(legacyData)

        XCTAssertNil(backup.records.first?.departureLocalDateTime)
        XCTAssertNil(backup.records.first?.departureUTCOffsetSeconds)
        XCTAssertNil(backup.records.first?.arrivalLocalDateTime)
        XCTAssertNil(backup.records.first?.arrivalUTCOffsetSeconds)
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
            name: "蒙特利尔特鲁多国际机场",
            city: "蒙特利尔",
            country: "加拿大",
            countryCode: "CA",
            latitude: 45.4706,
            longitude: -73.7408,
            timeZoneID: "America/Toronto"
        )
    }

    private var losAngeles: Airport {
        Airport(
            iata: "LAX",
            icao: "KLAX",
            name: "洛杉矶国际机场",
            city: "洛杉矶",
            country: "美国",
            countryCode: "US",
            latitude: 33.9416,
            longitude: -118.4085,
            timeZoneID: "America/Los_Angeles"
        )
    }

    private var repository: AirportRepository {
        AirportRepository(airports: [beijing, losAngeles, montreal])
    }

    private func makeDraft() -> FlightDraft {
        FlightDraft(
            flightDate: wallClockDate(2026, 8, 18, 0, 0),
            flightNumber: "CA123",
            airlineCode: "CA",
            airlineName: "中国国际航空",
            departureAirport: beijing,
            arrivalAirport: montreal,
            departureLocalDate: wallClockDate(2026, 8, 18, 10, 0),
            arrivalLocalDate: wallClockDate(2026, 8, 18, 8, 0)
        )
    }

    private func wallClockDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
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
