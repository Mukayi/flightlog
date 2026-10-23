import Foundation
import SwiftData
import XCTest
@testable import FlightLog

@MainActor
final class FlightEditorConcurrencyTests: XCTestCase {
    func testStaleEditorDetectsOtherContextUpdateAndDoesNotOverwrite() throws {
        let container = try makeContainer()
        let firstContext = ModelContext(container)
        let staleContext = ModelContext(container)
        let openedAt = date(2026, 8, 18, 0, 0)
        let concurrentAt = date(2026, 8, 18, 1, 0)
        let record = try FlightRecordWriter.makeRecord(
            from: makeDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id,
            now: openedAt
        )
        firstContext.insert(record)
        try firstContext.save()

        let staleRecord = try XCTUnwrap(
            staleContext.fetch(FetchDescriptor<FlightRecord>()).first
        )
        var staleDraft = FlightDraft(
            record: staleRecord,
            repository: repository
        )
        staleDraft.notes = "陈旧编辑器内容"

        let currentRecord = try XCTUnwrap(
            firstContext.fetch(FetchDescriptor<FlightRecord>()).first
        )
        var concurrentDraft = FlightDraft(
            record: currentRecord,
            repository: repository
        )
        concurrentDraft.notes = "另一个上下文已保存"
        try FlightRecordWriter.update(
            currentRecord,
            from: concurrentDraft,
            repository: repository,
            ownerProfileID: UserProfileDefaults.id,
            now: concurrentAt
        )
        try firstContext.save()

        XCTAssertThrowsError(
            try FlightEditorSaveService.save(
                draft: staleDraft,
                editingID: staleRecord.id,
                openedUpdatedAt: openedAt,
                ownerProfileID: UserProfileDefaults.id,
                repository: repository,
                in: staleContext,
                allowDuplicate: false,
                now: date(2026, 8, 18, 2, 0)
            )
        ) { error in
            XCTAssertEqual(error as? FlightEditorSaveError, .editConflict)
            XCTAssertTrue(error.localizedDescription.contains("其他操作"))
        }

        let verificationContext = ModelContext(container)
        let persisted = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<FlightRecord>()).first
        )
        XCTAssertEqual(persisted.notes, "另一个上下文已保存")
        XCTAssertEqual(persisted.updatedAt, concurrentAt)
    }

    func testNewEditorChecksDuplicatesFromLatestContextFetch() throws {
        let container = try makeContainer()
        let editorContext = ModelContext(container)
        let concurrentContext = ModelContext(container)
        let existing = try FlightRecordWriter.makeRecord(
            from: makeDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id,
            now: date(2026, 8, 18, 0, 0)
        )
        concurrentContext.insert(existing)
        try concurrentContext.save()

        let outcome = try FlightEditorSaveService.save(
            draft: makeDraft(),
            editingID: nil,
            openedUpdatedAt: nil,
            ownerProfileID: UserProfileDefaults.id,
            repository: repository,
            in: editorContext,
            allowDuplicate: false,
            now: date(2026, 8, 18, 1, 0)
        )

        XCTAssertEqual(outcome, .requiresDuplicateConfirmation(count: 1))
        let verificationContext = ModelContext(container)
        XCTAssertEqual(
            try verificationContext.fetch(FetchDescriptor<FlightRecord>()).count,
            1
        )
    }

    func testConfirmedDuplicateStillUsesLatestFetchAndCanSave() throws {
        let container = try makeContainer()
        let editorContext = ModelContext(container)
        let concurrentContext = ModelContext(container)
        concurrentContext.insert(
            try FlightRecordWriter.makeRecord(
                from: makeDraft(),
                repository: repository,
                ownerProfileID: UserProfileDefaults.id,
                now: date(2026, 8, 18, 0, 0)
            )
        )
        try concurrentContext.save()

        let outcome = try FlightEditorSaveService.save(
            draft: makeDraft(),
            editingID: nil,
            openedUpdatedAt: nil,
            ownerProfileID: UserProfileDefaults.id,
            repository: repository,
            in: editorContext,
            allowDuplicate: true,
            now: date(2026, 8, 18, 1, 0)
        )

        guard case .saved = outcome else {
            XCTFail("明确确认重复后应保存")
            return
        }
        let verificationContext = ModelContext(container)
        XCTAssertEqual(
            try verificationContext.fetch(FetchDescriptor<FlightRecord>()).count,
            2
        )
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: FlightLogSchemaV2.self),
            migrationPlan: FlightLogMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private var repository: AirportRepository {
        AirportRepository(airports: [beijing, montreal])
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

    private func makeDraft() -> FlightDraft {
        FlightDraft(
            flightDate: date(2026, 8, 18, 0, 0),
            flightNumber: "CA123",
            airlineCode: "CA",
            airlineName: "中国国际航空",
            departureAirport: beijing,
            arrivalAirport: montreal,
            departureLocalDate: date(2026, 8, 18, 10, 0),
            arrivalLocalDate: date(2026, 8, 18, 8, 0),
            notes: "初始内容"
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
