import Foundation
import XCTest
@testable import FlightLog

final class BackgroundBackupTests: XCTestCase {
    private final class CancellationProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var values = (cancelled: false, sideEffect: false)

        func markCancelled() {
            lock.withLock { values.cancelled = true }
        }

        func markSideEffect() {
            lock.withLock { values.sideEffect = true }
        }

        var snapshot: (cancelled: Bool, sideEffect: Bool) {
            lock.withLock { values }
        }
    }

    @MainActor
    func testBackupWorkSchedulerRunsCPUAndFileWorkOffMainThread() async throws {
        let ranOnMainThread = try await BackupWorkScheduler.run {
            Thread.isMainThread
        }

        XCTAssertFalse(ranOnMainThread)
    }

    func testPreparedImportAndRecordSnapshotsAreSendable() throws {
        let record = makeRecord()
        let data = try BackupService.exportJSON(records: [record])
        let preparation = try BackupService.prepareJSONImport(
            data,
            existingRecords: [],
            targetProfileID: UserProfileDefaults.id,
            mode: .merge
        )

        assertSendable(FlightRecordBackupDTO(record: record))
        assertSendable(preparation)
    }

    func testSnapshotExportOverloadsRoundTripWithoutSwiftDataModels() throws {
        let snapshot = FlightRecordBackupDTO(record: makeRecord())

        let json = try BackupService.exportJSON(
            recordSnapshots: [snapshot],
            exportedAt: Date(timeIntervalSince1970: 1_787_100_000)
        )
        let csv = try BackupService.exportCSV(recordSnapshots: [snapshot])
        let restored = try BackupService.prepareJSONImport(
            json,
            existingRecordSnapshots: [],
            targetProfileID: UserProfileDefaults.id,
            mode: .replace
        )

        XCTAssertEqual(restored.records, [snapshot])
        XCTAssertTrue(
            try XCTUnwrap(String(data: csv, encoding: .utf8))
                .contains("CA123")
        )
    }

    func testOwnedFileReadSurvivesSecurityScopeAndSourceReplacement() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("backup.json")
        try Data("original".utf8).write(to: url)

        let owned = try BackupFileIO.readSecurityScopedOwnedData(from: url)
        try Data("replacement".utf8).write(to: url)

        XCTAssertEqual(String(data: owned, encoding: .utf8), "original")
    }

    func testSchedulerCancellationCancelsDetachedWorkerBeforeSideEffect() async {
        let probe = CancellationProbe()
        let caller = Task {
            try await BackupWorkScheduler.run {
                while true {
                    if Task.isCancelled {
                        probe.markCancelled()
                        throw CancellationError()
                    }
                    Thread.sleep(forTimeInterval: 0.001)
                }
                probe.markSideEffect()
            }
        }

        try? await Task.sleep(for: .milliseconds(20))
        caller.cancel()
        do {
            _ = try await caller.value
            XCTFail("cancelled scheduler must throw")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertTrue(probe.snapshot.cancelled)
        XCTAssertFalse(probe.snapshot.sideEffect)
    }

    private func assertSendable<T: Sendable>(_: T) {}

    private func makeRecord() -> FlightRecord {
        let departure = Airport(
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
        let arrival = Airport(
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
        let base = Date(timeIntervalSince1970: 1_787_011_200)
        return FlightRecord(
            id: UUID(
                uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF"
            )!,
            flightNumber: "CA123",
            airlineCode: "CA",
            airlineName: "中国国际航空",
            flightDate: base,
            departureAirport: departure,
            arrivalAirport: arrival,
            departureDate: base.addingTimeInterval(3_600),
            arrivalDate: base.addingTimeInterval(7_200),
            notes: "后台任务",
            ownerProfileID: UserProfileDefaults.id,
            createdAt: base,
            updatedAt: base
        )
    }
}
