import Foundation
import SwiftData
import XCTest
@testable import FlightLog

final class BackupServiceTests: XCTestCase {
    private let beijing = Airport(
        iata: "PEK",
        icao: "ZBAA",
        name: "Beijing Capital International Airport",
        city: "Beijing",
        country: "China",
        countryCode: "CN",
        latitude: 40.0801,
        longitude: 116.5846,
        timeZoneID: "Asia/Shanghai"
    )

    private let montreal = Airport(
        iata: "YUL",
        icao: "CYUL",
        name: "Montréal–Trudeau International Airport",
        city: "Montréal",
        country: "Canada",
        countryCode: "CA",
        latitude: 45.4706,
        longitude: -73.7408,
        timeZoneID: "America/Toronto"
    )

    func testCSVParserHandlesBOMCommaQuotesEscapedQuotesAndEmbeddedNewlines() throws {
        let csv = "\u{FEFF}first,second,third\r\n"
            + "one,\"two,parts\",\"say \"\"hello\"\"\"\r\n"
            + "two,\"line one\nline two\",done"

        let rows = try CSVDocumentParser.parse(Data(csv.utf8))

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].lineNumber, 1)
        XCTAssertEqual(rows[0].fields, ["first", "second", "third"])
        XCTAssertEqual(rows[1].lineNumber, 2)
        XCTAssertEqual(rows[1].fields, ["one", "two,parts", "say \"hello\""])
        XCTAssertEqual(rows[2].lineNumber, 3)
        XCTAssertEqual(rows[2].fields, ["two", "line one\nline two", "done"])
    }

    func testCSVParserRejectsEmptyInvalidUTF8AndOversizedInputInChinese() {
        assertBackupError(Data(), contains: "为空")
        assertBackupError(Data([0xFF, 0xFE]), contains: "UTF-8")

        let limits = BackupLimits(
            maximumFileSize: 4,
            maximumRowCount: 10,
            maximumFieldLength: 10
        )
        assertBackupError(Data("12345".utf8), limits: limits, contains: "过大")
    }

    func testCSVParserRejectsOversizedFieldAndUnclosedQuote() {
        let limits = BackupLimits(
            maximumFileSize: 1_024,
            maximumRowCount: 10,
            maximumFieldLength: 4
        )
        assertBackupError(
            Data("header\n12345".utf8),
            limits: limits,
            contains: "字段"
        )
        assertBackupError(
            Data("header\n\"unfinished".utf8),
            contains: "引号"
        )
    }

    func testCSVImportCreatesValidRecordThroughRepositoryValidatorAndWriter() throws {
        let now = date(2026, 8, 20, 12, 0)
        let csv = csvDocument(rows: [
            [
                " ca 123 ",
                "2026-08-18",
                " ca ",
                " Air China ",
                "pek",
                "2026-08-18 10:00",
                "yul",
                "2026-08-18 08:00",
                "Boeing 787-9",
                "Business",
                "3A",
                "Window",
            ],
        ])

        let preparation = try BackupService.prepareCSVImport(
            Data(csv.utf8),
            repository: repository,
            existingRecords: [],
            targetProfileID: UserProfileDefaults.id,
            now: now
        )

        XCTAssertEqual(preparation.report.successCount, 1)
        XCTAssertEqual(preparation.report.failureCount, 0)
        XCTAssertEqual(preparation.report.duplicateCount, 0)
        XCTAssertEqual(preparation.records.count, 1)
        let record = try XCTUnwrap(preparation.records.first)
        XCTAssertEqual(record.flightNumber, "CA123")
        XCTAssertEqual(record.airlineCode, "CA")
        XCTAssertEqual(record.airlineName, "Air China")
        XCTAssertEqual(record.flightDate, date(2026, 8, 18, 0, 0))
        XCTAssertEqual(record.departureAirportIATA, "PEK")
        XCTAssertEqual(record.departureAirportName, beijing.name)
        XCTAssertEqual(record.arrivalAirportIATA, "YUL")
        XCTAssertEqual(record.arrivalAirportName, montreal.name)
        XCTAssertEqual(record.departureDate, date(2026, 8, 18, 2, 0))
        XCTAssertEqual(record.arrivalDate, date(2026, 8, 18, 12, 0))
        XCTAssertEqual(record.createdAt, now)
        XCTAssertEqual(record.updatedAt, now)
    }

    func testCSVImportReportsMissingAirportAndContinuesWithValidRows() throws {
        let csv = csvDocument(rows: [
            csvRow(flightNumber: "BAD1", departureIATA: "ZZZ"),
            csvRow(flightNumber: "GOOD1"),
        ])

        let preparation = try BackupService.prepareCSVImport(
            Data(csv.utf8),
            repository: repository,
            existingRecords: [],
            targetProfileID: UserProfileDefaults.id
        )

        XCTAssertEqual(preparation.report.successCount, 1)
        XCTAssertEqual(preparation.report.failureCount, 1)
        XCTAssertEqual(preparation.records.map(\.flightNumber), ["GOOD1"])
        let issue = try XCTUnwrap(preparation.report.issues.first)
        XCTAssertEqual(issue.rowNumber, 2)
        XCTAssertEqual(issue.kind, .failure)
        XCTAssertTrue(issue.reason.contains("ZZZ"))
        XCTAssertTrue(issue.reason.contains("机场"))
    }

    func testCSVImportReportsInvalidDateAndMissingRequiredFieldPerRow() throws {
        var missingTime = csvRow(flightNumber: "BAD2")
        missingTime[5] = ""
        let csv = csvDocument(rows: [
            csvRow(flightNumber: "BAD1", flightDate: "2026-02-30"),
            missingTime,
            csvRow(flightNumber: "GOOD1"),
        ])

        let preparation = try BackupService.prepareCSVImport(
            Data(csv.utf8),
            repository: repository,
            existingRecords: [],
            targetProfileID: UserProfileDefaults.id
        )

        XCTAssertEqual(preparation.report.successCount, 1)
        XCTAssertEqual(preparation.report.failureCount, 2)
        XCTAssertEqual(preparation.records.map(\.flightNumber), ["GOOD1"])
        XCTAssertEqual(preparation.report.issues.map(\.rowNumber), [2, 3])
        XCTAssertTrue(preparation.report.issues[0].reason.contains("日期"))
        XCTAssertTrue(
            preparation.report.issues[1].reason.contains(
                "departureLocalDateTime"
            )
        )
    }

    func testCSVImportSkipsDuplicatesAgainstExistingRecordsAndInsideFile() throws {
        let existing = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            flightNumber: "EXIST1"
        )
        let csv = csvDocument(rows: [
            csvRow(flightNumber: "EXIST1"),
            csvRow(flightNumber: "NEW1"),
            csvRow(flightNumber: " new 1 "),
        ])

        let preparation = try BackupService.prepareCSVImport(
            Data(csv.utf8),
            repository: repository,
            existingRecords: [existing],
            targetProfileID: UserProfileDefaults.id
        )

        XCTAssertEqual(preparation.report.successCount, 1)
        XCTAssertEqual(preparation.report.failureCount, 0)
        XCTAssertEqual(preparation.report.duplicateCount, 2)
        XCTAssertEqual(preparation.records.map(\.flightNumber), ["NEW1"])
        XCTAssertEqual(
            preparation.report.issues.map(\.kind),
            [.duplicate, .duplicate]
        )
        XCTAssertTrue(preparation.report.issues[0].reason.contains("现有"))
        XCTAssertTrue(preparation.report.issues[1].reason.contains("文件"))
    }

    func testSuccessfulImportReportCanCopyAllCountsWithoutIssues() throws {
        let csv = csvDocument(rows: [
            csvRow(flightNumber: "GOOD1"),
        ])

        let report = try BackupService.prepareCSVImport(
            Data(csv.utf8),
            repository: repository,
            existingRecords: [],
            targetProfileID: UserProfileDefaults.id
        ).report

        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertTrue(report.canCopy)
        XCTAssertEqual(
            report.summary,
            "成功 1 条，失败 0 条，重复跳过 0 条"
        )
        XCTAssertEqual(
            report.copyText,
            "CSV 导入结果\n成功 1 条，失败 0 条，重复跳过 0 条"
        )
    }

    @MainActor
    func testCSVImportImmediatelyAppliesValidRowsAndGeneratesReport() throws {
        let container = try makeContainerWithDefaultProfile()
        let context = container.mainContext
        let csv = csvDocument(rows: [
            csvRow(flightNumber: "BAD1", departureIATA: "ZZZ"),
            csvRow(flightNumber: "GOOD1"),
        ])

        let preparation = try BackupService.prepareCSVImport(
            Data(csv.utf8),
            repository: repository,
            existingRecords: [],
            targetProfileID: UserProfileDefaults.id
        )
        try BackupService.apply(
            preparation,
            to: context,
            targetProfileID: UserProfileDefaults.id
        )

        let persisted = try context.fetch(FetchDescriptor<FlightRecord>())
        XCTAssertEqual(persisted.map(\.flightNumber), ["GOOD1"])
        XCTAssertEqual(preparation.report.successCount, 1)
        XCTAssertEqual(preparation.report.failureCount, 1)
        XCTAssertEqual(preparation.report.duplicateCount, 0)
        XCTAssertEqual(preparation.report.issues.first?.rowNumber, 2)
        XCTAssertEqual(preparation.report.issues.first?.kind, .failure)
    }

    func testCSVExportAndImportRoundTripsCommonFields() throws {
        let notes = "Window, \"quiet\"\nSecond line"
        let record = makeRecord(notes: notes)

        let data = try BackupService.exportCSV(records: [record])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.hasPrefix(BackupService.csvHeaders.joined(separator: ",")))
        XCTAssertTrue(text.contains("\"Window, \"\"quiet\"\"\nSecond line\""))

        let preparation = try BackupService.prepareCSVImport(
            data,
            repository: repository,
            existingRecords: [],
            targetProfileID: UserProfileDefaults.id,
            now: record.createdAt
        )
        let restored = try XCTUnwrap(preparation.records.first)
        XCTAssertEqual(restored.flightNumber, record.flightNumber)
        XCTAssertEqual(restored.flightDate, record.flightDate)
        XCTAssertEqual(restored.departureAirportIATA, "PEK")
        XCTAssertEqual(restored.arrivalAirportIATA, "YUL")
        XCTAssertEqual(restored.departureDate, record.departureDate)
        XCTAssertEqual(restored.arrivalDate, record.arrivalDate)
        XCTAssertEqual(restored.aircraftType, record.aircraftType)
        XCTAssertEqual(restored.cabinClass, record.cabinClass)
        XCTAssertEqual(restored.seat, record.seat)
        XCTAssertEqual(restored.notes, notes)
    }

    func testJSONBackupRoundTripsEveryRecordFieldAndTimestamps() throws {
        let exportedAt = Date(
            timeIntervalSince1970: 1_787_100_000.123_456_7
        )
        let original = makeRecord(
            id: UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!,
            notes: "完整备份",
            createdAt: Date(
                timeIntervalSince1970: 1_787_000_000.987_654_3
            ),
            updatedAt: Date(
                timeIntervalSince1970: 1_787_050_000.543_210_9
            )
        )

        let data = try BackupService.exportJSON(
            records: [original],
            exportedAt: exportedAt
        )
        let backup = try BackupService.decodeJSON(data)

        XCTAssertEqual(backup.schemaVersion, BackupService.currentSchemaVersion)
        XCTAssertEqual(backup.exportedAt, exportedAt)
        XCTAssertEqual(backup.records, [FlightRecordBackupDTO(record: original)])

        let preparation = try BackupService.prepareJSONImport(
            data,
            existingRecords: [],
            targetProfileID: UserProfileDefaults.id,
            mode: .replace
        )
        XCTAssertEqual(preparation.report.successCount, 1)
        let restored = try XCTUnwrap(preparation.records.first).makeRecord(
            ownerProfileID: UserProfileDefaults.id
        )
        assertRecord(restored, equals: original)
    }

    func testJSONRestoreAtomicallyRejectsFlightDateDifferentFromDepartureLocalDate()
        throws
    {
        let record = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            flightNumber: "BADDATE1"
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: BackupService.exportJSON(records: [record])
            ) as? [String: Any]
        )
        var records = try XCTUnwrap(object["records"] as? [[String: Any]])
        records[0]["flightDate"] =
            record.flightDate.timeIntervalSince1970 + 86_400
        object["records"] = records
        let data = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(
            try BackupService.prepareJSONImport(
                data,
                existingRecords: [],
                targetProfileID: UserProfileDefaults.id,
                mode: .replace
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("flightDate"))
            XCTAssertTrue(error.localizedDescription.contains("出发当地日期"))
        }
    }

    func testJSONBackupIncludesNilOptionalRecordFieldsExplicitly() throws {
        let record = makeRecord(notes: nil)
        record.aircraftType = nil
        record.cabinClass = nil
        record.seat = nil

        let data = try BackupService.exportJSON(
            records: [record],
            exportedAt: date(2026, 8, 20, 12, 0)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let records = try XCTUnwrap(object["records"] as? [[String: Any]])
        let encoded = try XCTUnwrap(records.first)

        for key in ["aircraftType", "cabinClass", "seat", "notes"] {
            XCTAssertTrue(encoded.keys.contains(key), "缺少 JSON 字段 \(key)")
            XCTAssertTrue(encoded[key] is NSNull, "\(key) 应明确编码为 null")
        }
    }

    func testJSONExportIsStableForEquivalentRecordSets() throws {
        let exportedAt = date(2026, 8, 20, 12, 0)
        let first = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            flightNumber: "CA1"
        )
        let second = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            flightNumber: "CA2"
        )

        let forwardJSON = try BackupService.exportJSON(
            records: [first, second],
            exportedAt: exportedAt
        )
        let reverseJSON = try BackupService.exportJSON(
            records: [second, first],
            exportedAt: exportedAt
        )
        let forwardCSV = try BackupService.exportCSV(records: [first, second])
        let reverseCSV = try BackupService.exportCSV(records: [second, first])

        XCTAssertEqual(forwardJSON, reverseJSON)
        XCTAssertEqual(forwardCSV, reverseCSV)
    }

    func testDatasetFingerprintIsStableAcrossExistingRecordOrder() {
        let first = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            flightNumber: "FIRST1"
        )
        let second = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            flightNumber: "SECOND1"
        )

        XCTAssertEqual(
            FlightDatasetFingerprint(records: [first, second]),
            FlightDatasetFingerprint(records: [second, first])
        )
    }

    func testDatasetFingerprintChangesWhenBusinessKeyChangesForSameUUID() {
        let record = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            flightNumber: "FIRST1"
        )
        let original = FlightDatasetFingerprint(records: [record])

        record.flightNumber = "SECOND1"
        let changed = FlightDatasetFingerprint(records: [record])

        XCTAssertNotEqual(original, changed)
    }

    func testDatasetFingerprintChangesWhenNotesChangeWithoutUpdatedAtChange() {
        let record = makeRecord(notes: "原备注")
        let originalUpdatedAt = record.updatedAt
        let original = FlightDatasetFingerprint(records: [record])

        record.notes = "同一 updatedAt 下的新备注"
        XCTAssertEqual(record.updatedAt, originalUpdatedAt)

        XCTAssertNotEqual(
            original,
            FlightDatasetFingerprint(records: [record])
        )
    }

    func testDatasetFingerprintChangesWhenCoordinatesChangeWithoutUpdatedAtChange() {
        let record = makeRecord()
        let originalUpdatedAt = record.updatedAt
        let original = FlightDatasetFingerprint(records: [record])

        record.departureLatitude += 0.001
        record.arrivalLongitude -= 0.001
        XCTAssertEqual(record.updatedAt, originalUpdatedAt)

        XCTAssertNotEqual(
            original,
            FlightDatasetFingerprint(records: [record])
        )
    }

    func testJSONImportRejectsUnknownFutureSchemaVersionExplicitly() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": BackupService.currentSchemaVersion + 1,
            "exportedAt": "2026-08-20T12:00:00Z",
            "records": [],
        ])

        XCTAssertThrowsError(try BackupService.decodeJSON(data)) { error in
            XCTAssertEqual(
                error as? BackupServiceError,
                .unsupportedSchemaVersion(BackupService.currentSchemaVersion + 1)
            )
            XCTAssertTrue(error.localizedDescription.contains("不支持"))
            XCTAssertTrue(
                error.localizedDescription.contains(
                    "\(BackupService.currentSchemaVersion + 1)"
                )
            )
        }
    }

    func testJSONMergeSkipsDuplicateAgainstExistingRecord() throws {
        let existing = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            flightNumber: "CA123"
        )
        let backupRecord = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            flightNumber: " ca 123 "
        )
        let data = try BackupService.exportJSON(
            records: [backupRecord],
            exportedAt: date(2026, 8, 20, 12, 0)
        )

        let preparation = try BackupService.prepareJSONImport(
            data,
            existingRecords: [existing],
            targetProfileID: UserProfileDefaults.id,
            mode: .merge
        )

        XCTAssertTrue(preparation.records.isEmpty)
        XCTAssertEqual(preparation.report.successCount, 0)
        XCTAssertEqual(preparation.report.failureCount, 0)
        XCTAssertEqual(preparation.report.duplicateCount, 1)
        XCTAssertEqual(preparation.report.issues.first?.kind, .duplicate)
    }

    @MainActor
    func testJSONImportRejectsRecordCountLimitBeforeWriting() throws {
        let container = try makeContainerWithDefaultProfile()
        let context = container.mainContext
        let existing = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            flightNumber: "KEEP1"
        )
        context.insert(existing)
        try context.save()
        let first = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            flightNumber: "NEW1"
        )
        let second = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            flightNumber: "NEW2"
        )
        let data = try BackupService.exportJSON(
            records: [first, second],
            exportedAt: date(2026, 8, 20, 12, 0)
        )
        let limits = BackupLimits(
            maximumFileSize: 10 * 1_024 * 1_024,
            maximumRowCount: 1,
            maximumFieldLength: 10_000
        )

        XCTAssertThrowsError(
            try BackupService.restoreJSON(
                data,
                to: context,
                existingRecords: [existing],
                targetProfileID: UserProfileDefaults.id,
                mode: .replace,
                limits: limits
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("JSON"))
            XCTAssertTrue(error.localizedDescription.contains("1"))
            XCTAssertFalse(error.localizedDescription.contains("CSV"))
        }

        let persisted = try context.fetch(FetchDescriptor<FlightRecord>())
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.id, existing.id)
        XCTAssertEqual(persisted.first?.flightNumber, "KEEP1")
    }

    func testJSONImportRejectsNonCanonicalThreeCharacterIATA() throws {
        var dto = FlightRecordBackupDTO(record: makeRecord())
        dto.departureAirportIATA = "P-E-K"
        let data = try BackupService.encodeJSON(
            v2Backup(records: [dto])
        )

        XCTAssertThrowsError(
            try BackupService.prepareJSONImport(
                data,
                existingRecords: [],
                targetProfileID: UserProfileDefaults.id,
                mode: .replace
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("IATA"))
            XCTAssertTrue(error.localizedDescription.contains("3"))
        }
    }

    func testJSONImportRejectsThreeCharacterIATAContainingDigit() throws {
        var dto = FlightRecordBackupDTO(record: makeRecord())
        dto.departureAirportIATA = "A1B"
        let data = try BackupService.encodeJSON(
            v2Backup(records: [dto])
        )

        XCTAssertThrowsError(
            try BackupService.prepareJSONImport(
                data,
                existingRecords: [],
                targetProfileID: UserProfileDefaults.id,
                mode: .replace
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("IATA"))
            XCTAssertTrue(error.localizedDescription.contains("A-Z"))
        }
    }

    func testJSONImportAcceptsUnknownCanonicalIATAWithoutAirportRepository() throws {
        var dto = FlightRecordBackupDTO(record: makeRecord())
        dto.departureAirportIATA = "ZZZ"
        dto.arrivalAirportIATA = "YYY"
        let data = try BackupService.encodeJSON(
            v2Backup(records: [dto])
        )

        let preparation = try BackupService.prepareJSONImport(
            data,
            existingRecords: [],
            targetProfileID: UserProfileDefaults.id,
            mode: .replace
        )

        XCTAssertEqual(preparation.records.first?.departureAirportIATA, "ZZZ")
        XCTAssertEqual(preparation.records.first?.arrivalAirportIATA, "YYY")
    }

    func testJSONMergeSkipsSameTargetBusinessKeyEvenWhenUUIDAlsoConflicts() throws {
        let firstID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        )!
        let existingFirst = makeRecord(
            id: firstID,
            flightNumber: "FIRST1"
        )
        let existingSecond = makeRecord(
            id: UUID(
                uuidString: "00000000-0000-0000-0000-000000000002"
            )!,
            flightNumber: "SECOND1"
        )
        let conflicting = makeRecord(
            id: firstID,
            flightNumber: "SECOND1",
            notes: "与另一业务键冲突"
        )
        let data = try BackupService.exportJSON(
            records: [conflicting],
            exportedAt: date(2026, 8, 20, 12, 0)
        )

        let preparation = try BackupService.prepareJSONImport(
            data,
            existingRecords: [existingFirst, existingSecond],
            targetProfileID: UserProfileDefaults.id,
            mode: .merge
        )
        XCTAssertTrue(preparation.records.isEmpty)
        XCTAssertEqual(preparation.report.duplicateCount, 1)
    }

    func testJSONMergeSkipsSameTargetBusinessKeyBeforeUUIDRemap() throws {
        let sharedID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        )!
        let existing = makeRecord(
            id: sharedID,
            flightNumber: "CA123",
            notes: "原备注"
        )
        let conflicting = makeRecord(
            id: sharedID,
            flightNumber: "CA123",
            notes: "修改后的备注"
        )
        let data = try BackupService.exportJSON(
            records: [conflicting],
            exportedAt: date(2026, 8, 20, 12, 0)
        )

        let preparation = try BackupService.prepareJSONImport(
            data,
            existingRecords: [existing],
            targetProfileID: UserProfileDefaults.id,
            mode: .merge
        )
        XCTAssertTrue(preparation.records.isEmpty)
        XCTAssertEqual(preparation.report.duplicateCount, 1)
    }

    @MainActor
    func testJSONRestoreValidatesAllRecordsBeforeReplacingExistingData() throws {
        let container = try makeContainerWithDefaultProfile()
        let context = container.mainContext
        let existing = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            flightNumber: "KEEP1"
        )
        context.insert(existing)
        try context.save()

        var validDTO = FlightRecordBackupDTO(
            record: makeRecord(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                flightNumber: "GOOD1"
            )
        )
        validDTO.notes = "valid"
        var invalidDTO = validDTO
        invalidDTO.id = UUID(
            uuidString: "00000000-0000-0000-0000-000000000003"
        )!
        invalidDTO.flightNumber = "BAD1"
        invalidDTO.arrivalDate = invalidDTO.departureDate
        let invalidBackup = v2Backup(records: [validDTO, invalidDTO])
        let data = try BackupService.encodeJSON(invalidBackup)

        XCTAssertThrowsError(
            try BackupService.restoreJSON(
                data,
                to: context,
                existingRecords: [existing],
                targetProfileID: UserProfileDefaults.id,
                mode: .replace
            )
        )

        let persisted = try context.fetch(FetchDescriptor<FlightRecord>())
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.id, existing.id)
        XCTAssertEqual(persisted.first?.flightNumber, "KEEP1")
    }

    @MainActor
    func testJSONReplaceRestoresBackupWithSameRecordIdentity() throws {
        let container = try makeContainerWithDefaultProfile()
        let context = container.mainContext
        let sharedID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000001"
        )!
        let existing = makeRecord(
            id: sharedID,
            flightNumber: "OLD1",
            notes: "旧数据"
        )
        context.insert(existing)
        try context.save()

        let restoredSameIdentity = makeRecord(
            id: sharedID,
            flightNumber: "NEW1",
            notes: "备份数据"
        )
        let restoredSecond = makeRecord(
            id: UUID(
                uuidString: "00000000-0000-0000-0000-000000000002"
            )!,
            flightNumber: "NEW2"
        )
        let data = try BackupService.exportJSON(
            records: [restoredSameIdentity, restoredSecond],
            exportedAt: date(2026, 8, 20, 12, 0)
        )

        let report = try BackupService.restoreJSON(
            data,
            to: context,
            existingRecords: [existing],
            targetProfileID: UserProfileDefaults.id,
            mode: .replace
        )

        let persisted = try context.fetch(
            FetchDescriptor<FlightRecord>(
                sortBy: [SortDescriptor(\.flightNumber)]
            )
        )
        XCTAssertEqual(report.successCount, 2)
        XCTAssertEqual(persisted.map(\.flightNumber), ["NEW1", "NEW2"])
        XCTAssertEqual(persisted.first?.id, sharedID)
        XCTAssertEqual(persisted.first?.notes, "备份数据")
    }

    @MainActor
    func testJSONMergeRejectsStalePreparedPlanWithoutWriting() throws {
        let container = try makeContainerWithDefaultProfile()
        let context = container.mainContext
        let existing = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            flightNumber: "KEEP1"
        )
        context.insert(existing)
        try context.save()
        let incoming = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            flightNumber: "NEW1"
        )
        let data = try BackupService.exportJSON(
            records: [incoming],
            exportedAt: date(2026, 8, 20, 12, 0)
        )
        let preparation = try BackupService.prepareJSONImport(
            data,
            existingRecords: [existing],
            targetProfileID: UserProfileDefaults.id,
            mode: .merge
        )
        let concurrent = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            flightNumber: "ADDED1"
        )
        context.insert(concurrent)
        try context.save()

        XCTAssertThrowsError(
            try BackupService.apply(
                preparation,
                to: context,
                targetProfileID: UserProfileDefaults.id
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "数据已变化，请重新确认。"
            )
        }

        let persisted = try context.fetch(FetchDescriptor<FlightRecord>())
        XCTAssertEqual(
            Set(persisted.map(\.flightNumber)),
            Set(["KEEP1", "ADDED1"])
        )
    }

    @MainActor
    func testJSONReplaceRejectsStalePreparedPlanWithoutDeletingConcurrentRecord() throws {
        let container = try makeContainerWithDefaultProfile()
        let context = container.mainContext
        let existing = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            flightNumber: "KEEP1"
        )
        context.insert(existing)
        try context.save()
        let replacement = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            flightNumber: "RESTORE1"
        )
        let data = try BackupService.exportJSON(
            records: [replacement],
            exportedAt: date(2026, 8, 20, 12, 0)
        )
        let preparation = try BackupService.prepareJSONImport(
            data,
            existingRecords: [existing],
            targetProfileID: UserProfileDefaults.id,
            mode: .replace
        )
        let concurrent = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            flightNumber: "ADDED1"
        )
        context.insert(concurrent)
        try context.save()

        XCTAssertThrowsError(
            try BackupService.apply(
                preparation,
                to: context,
                targetProfileID: UserProfileDefaults.id
            )
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "数据已变化，请重新确认。"
            )
        }

        let persisted = try context.fetch(FetchDescriptor<FlightRecord>())
        XCTAssertEqual(
            Set(persisted.map(\.flightNumber)),
            Set(["KEEP1", "ADDED1"])
        )
        XCTAssertFalse(
            persisted.contains { $0.flightNumber == "RESTORE1" }
        )
    }

    private var repository: AirportRepository {
        AirportRepository(airports: [beijing, montreal])
    }

    private func csvDocument(rows: [[String]]) -> String {
        ([BackupService.csvHeaders] + rows)
            .map { $0.map(csvEscape).joined(separator: ",") }
            .joined(separator: "\n")
    }

    private func csvRow(
        flightNumber: String,
        flightDate: String = "2026-08-18",
        departureIATA: String = "PEK"
    ) -> [String] {
        [
            flightNumber,
            flightDate,
            "CA",
            "Air China",
            departureIATA,
            "2026-08-18 10:00",
            "YUL",
            "2026-08-18 08:00",
            "Boeing 787-9",
            "Business",
            "3A",
            "Test",
        ]
    }

    private func csvEscape(_ value: String) -> String {
        guard
            value.contains(",")
                || value.contains("\"")
                || value.contains("\n")
                || value.contains("\r")
        else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func assertBackupError(
        _ data: Data,
        limits: BackupLimits = .standard,
        contains fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try CSVDocumentParser.parse(data, limits: limits),
            file: file,
            line: line
        ) { error in
            XCTAssertTrue(
                error.localizedDescription.contains(fragment),
                "错误“\(error.localizedDescription)”应包含“\(fragment)”",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private func makeContainerWithDefaultProfile() throws -> ModelContainer {
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlightLogSchemaV2.self),
            migrationPlan: FlightLogMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.insert(
            UserProfile(
                id: UserProfileDefaults.id,
                displayName: UserProfileDefaults.displayName,
                sortOrder: 0,
                comparisonColorRawValue: UserProfileDefaults
                    .comparisonColorRawValue
            )
        )
        try container.mainContext.save()
        return container
    }

    private func makeRecord(
        id: UUID = UUID(
            uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF"
        )!,
        flightNumber: String = "CA123",
        notes: String? = "Test",
        createdAt: Date = Date(timeIntervalSince1970: 1_787_000_000.125),
        updatedAt: Date = Date(timeIntervalSince1970: 1_787_050_000.625)
    ) -> FlightRecord {
        FlightRecord(
            id: id,
            flightNumber: flightNumber,
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: date(2026, 8, 18, 0, 0),
            departureAirport: beijing,
            arrivalAirport: montreal,
            departureDate: date(2026, 8, 18, 2, 0),
            arrivalDate: date(2026, 8, 18, 12, 0),
            aircraftType: "Boeing 787-9",
            cabinClass: "Business",
            seat: "3A",
            notes: notes,
            ownerProfileID: UserProfileDefaults.id,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func assertRecord(
        _ actual: FlightRecord,
        equals expected: FlightRecord,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.id, expected.id, file: file, line: line)
        XCTAssertEqual(
            actual.flightNumber,
            expected.flightNumber,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.airlineCode,
            expected.airlineCode,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.airlineName,
            expected.airlineName,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.flightDate, expected.flightDate, file: file, line: line)
        XCTAssertEqual(
            actual.departureAirportIATA,
            expected.departureAirportIATA,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.departureDate,
            expected.departureDate,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.departureTimeZoneID,
            expected.departureTimeZoneID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.departureAirportName,
            expected.departureAirportName,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.departureCity, expected.departureCity, file: file, line: line)
        XCTAssertEqual(
            actual.departureCountry,
            expected.departureCountry,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.departureCountryCode,
            expected.departureCountryCode,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.departureLatitude,
            expected.departureLatitude,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.departureLongitude,
            expected.departureLongitude,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.arrivalAirportIATA,
            expected.arrivalAirportIATA,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.arrivalDate, expected.arrivalDate, file: file, line: line)
        XCTAssertEqual(
            actual.arrivalTimeZoneID,
            expected.arrivalTimeZoneID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.arrivalAirportName,
            expected.arrivalAirportName,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.arrivalCity, expected.arrivalCity, file: file, line: line)
        XCTAssertEqual(
            actual.arrivalCountry,
            expected.arrivalCountry,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.arrivalCountryCode,
            expected.arrivalCountryCode,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.arrivalLatitude,
            expected.arrivalLatitude,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.arrivalLongitude,
            expected.arrivalLongitude,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.aircraftType, expected.aircraftType, file: file, line: line)
        XCTAssertEqual(actual.cabinClass, expected.cabinClass, file: file, line: line)
        XCTAssertEqual(actual.seat, expected.seat, file: file, line: line)
        XCTAssertEqual(actual.notes, expected.notes, file: file, line: line)
        XCTAssertEqual(actual.createdAt, expected.createdAt, file: file, line: line)
        XCTAssertEqual(actual.updatedAt, expected.updatedAt, file: file, line: line)
    }

    private func v2Backup(
        records: [FlightRecordBackupDTO]
    ) -> FlightBackupDTO {
        FlightBackupDTO(
            schemaVersion: BackupService.currentSchemaVersion,
            exportedAt: date(2026, 8, 20, 12, 0),
            scope: .singleProfile,
            profiles: [
                UserProfileBackupDTO(
                    id: UserProfileDefaults.id,
                    displayName: UserProfileDefaults.displayName,
                    createdAt: Date(timeIntervalSince1970: 0),
                    sortOrder: 0,
                    color: UserProfileDefaults.comparisonColorRawValue
                ),
            ],
            records: records
        )
    }

    private func date(
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
