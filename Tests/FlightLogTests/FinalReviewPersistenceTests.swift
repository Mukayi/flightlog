import Foundation
import SwiftData
import XCTest
@testable import FlightLog

@MainActor
final class FinalReviewPersistenceTests: XCTestCase {
    func testDedicatedDiskStoreCreatesAndReopensWithVersionedSchema() throws {
        try withTemporaryDirectory { directory in
            let storeURL = directory
                .appendingPathComponent("FlightLog", isDirectory: true)
                .appendingPathComponent("FlightLog.store")

            let first = try PersistenceController(storeURL: storeURL)
            first.container.mainContext.insert(
                makeRecord(id: uuid(1), flightNumber: "DISK1")
            )
            try first.container.mainContext.save()

            XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
            XCTAssertEqual(storeURL.lastPathComponent, "FlightLog.store")
            XCTAssertFalse(storeURL.path.contains("default.store"))
            XCTAssertEqual(FlightLogSchemaV1.versionIdentifier.major, 1)
            XCTAssertEqual(FlightLogSchemaV2.versionIdentifier.major, 2)
            XCTAssertEqual(FlightLogMigrationPlan.schemas.count, 2)

            let reopened = try PersistenceController(storeURL: storeURL)
            let records = try reopened.container.mainContext.fetch(
                FetchDescriptor<FlightRecord>()
            )
            XCTAssertEqual(records.map(\.flightNumber), ["DISK1"])
        }
    }

    func testDefaultStoreURLUsesFlightLogApplicationSupportDirectory() {
        let url = PersistenceController.defaultStoreURL

        XCTAssertEqual(url.lastPathComponent, "FlightLog.store")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "FlightLog")
        XCTAssertFalse(url.path.contains("default.store"))
    }

    func testPersistenceFailureProducesChineseRecoveryContent() {
        let recovery = PersistenceRecoveryContent(
            error: CocoaError(.fileWriteNoPermission)
        )

        XCTAssertEqual(recovery.title, "无法打开航班日志")
        XCTAssertTrue(recovery.message.contains("数据存储"))
        XCTAssertTrue(recovery.recoverySuggestion.contains("重新启动"))
    }

    func testApplicationUsesSingleWindowAndChineseLegacyImportPresentation() {
        XCTAssertTrue(FlightLogWindowPolicy.usesSingleWindow)
        let presentation = LegacyImportPresentation(recordCount: 3)
        XCTAssertEqual(presentation.title, "发现旧版 FlightLog 数据")
        XCTAssertTrue(presentation.message.contains("3"))
        XCTAssertTrue(presentation.message.contains("备份"))
        XCTAssertTrue(presentation.message.contains("保留"))
    }

    func testLegacyStoreIsBackedUpThenImportedOnceWithoutRemovingSource() throws {
        try withTemporaryDirectory { directory in
            let legacyURL = directory.appendingPathComponent("default.store")
            let dedicatedURL = directory
                .appendingPathComponent("FlightLog", isDirectory: true)
                .appendingPathComponent("FlightLog.store")
            let backupDirectory = directory.appendingPathComponent(
                "LegacyBackups",
                isDirectory: true
            )
            let markerURL = directory.appendingPathComponent(
                "legacy-import-v1.json"
            )
            let configuration = LegacyStoreMigrationConfiguration(
                sourceStoreURL: legacyURL,
                backupDirectoryURL: backupDirectory,
                markerURL: markerURL
            )

            let legacy = try PersistenceController(storeURL: legacyURL)
            legacy.container.mainContext.insert(
                makeRecord(id: uuid(1), flightNumber: "LEGACY1")
            )
            legacy.container.mainContext.insert(
                makeRecord(id: uuid(2), flightNumber: "DUP1")
            )
            try legacy.container.mainContext.save()

            let destination = try PersistenceController(storeURL: dedicatedURL)
            destination.container.mainContext.insert(
                makeRecord(id: uuid(9), flightNumber: "DUP1")
            )
            try destination.container.mainContext.save()

            let candidate = try XCTUnwrap(
                LegacyStoreMigrationService.inspect(configuration)
            )
            XCTAssertEqual(candidate.records.count, 2)
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: candidate.backupStoreURL.path
                )
            )
            let backup = try PersistenceController(
                storeURL: candidate.backupStoreURL
            )
            XCTAssertEqual(
                try backup.container.mainContext.fetch(
                    FetchDescriptor<FlightRecord>()
                ).count,
                2
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
            XCTAssertEqual(
                try LegacyStoreMigrationService.currentState(configuration)?.status,
                .deferred
            )

            let report = try LegacyStoreMigrationService.importCandidate(
                candidate,
                to: destination.container.mainContext,
                targetProfileID: UserProfileDefaults.id,
                configuration: configuration
            )

            XCTAssertEqual(report.successCount, 1)
            XCTAssertEqual(report.duplicateCount, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
            XCTAssertNil(try LegacyStoreMigrationService.inspect(configuration))

            let destinationRecords = try destination.container.mainContext.fetch(
                FetchDescriptor<FlightRecord>()
            )
            XCTAssertEqual(
                Set(destinationRecords.map(\.flightNumber)),
                Set(["DUP1", "LEGACY1"])
            )

            let reopenedLegacy = try PersistenceController(storeURL: legacyURL)
            let legacyRecords = try reopenedLegacy.container.mainContext.fetch(
                FetchDescriptor<FlightRecord>()
            )
            XCTAssertEqual(
                Set(legacyRecords.map(\.flightNumber)),
                Set(["DUP1", "LEGACY1"])
            )
        }
    }

    func testUnversionedDefaultStoreIsRecognizedByV1MigrationPlan() throws {
        try withTemporaryDirectory { directory in
            let legacyURL = directory.appendingPathComponent("default.store")
            let schema = Schema([FlightRecord.self])
            let legacy = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    "LegacyFlightLog",
                    schema: schema,
                    url: legacyURL
                )
            )
            legacy.mainContext.insert(
                makeRecord(id: uuid(1), flightNumber: "UNVERSIONED1")
            )
            try legacy.mainContext.save()
            let originalStoreData = try Data(contentsOf: legacyURL)
            let configuration = LegacyStoreMigrationConfiguration(
                sourceStoreURL: legacyURL,
                backupDirectoryURL: directory.appendingPathComponent(
                    "LegacyBackups",
                    isDirectory: true
                ),
                markerURL: directory.appendingPathComponent("marker.json")
            )

            let candidate = try XCTUnwrap(
                LegacyStoreMigrationService.inspect(configuration)
            )

            XCTAssertEqual(
                candidate.records.map(\.flightNumber),
                ["UNVERSIONED1"]
            )
            XCTAssertEqual(try Data(contentsOf: legacyURL), originalStoreData)
            XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        }
    }

    func testLegacyImportMarkerFailureLeavesDestinationUnchanged() throws {
        try withTemporaryDirectory { directory in
            let legacyURL = directory.appendingPathComponent("default.store")
            let dedicatedURL = directory.appendingPathComponent(
                "FlightLog.store"
            )
            let configuration = LegacyStoreMigrationConfiguration(
                sourceStoreURL: legacyURL,
                backupDirectoryURL: directory.appendingPathComponent(
                    "LegacyBackups",
                    isDirectory: true
                ),
                markerURL: directory.appendingPathComponent("marker.json")
            )

            let legacy = try PersistenceController(storeURL: legacyURL)
            legacy.container.mainContext.insert(
                makeRecord(id: uuid(1), flightNumber: "LEGACY1")
            )
            try legacy.container.mainContext.save()
            let candidate = try XCTUnwrap(
                LegacyStoreMigrationService.inspect(configuration)
            )

            let destination = try PersistenceController(storeURL: dedicatedURL)
            destination.container.mainContext.insert(
                makeRecord(id: uuid(9), flightNumber: "KEEP1")
            )
            try destination.container.mainContext.save()

            XCTAssertThrowsError(
                try LegacyStoreMigrationService.importCandidate(
                    candidate,
                    to: destination.container.mainContext,
                    targetProfileID: UserProfileDefaults.id,
                    configuration: configuration,
                    markerWriter: { _, _ in
                        throw CocoaError(.fileWriteNoPermission)
                    }
                )
            )

            let reopened = try PersistenceController(storeURL: dedicatedURL)
            let records = try reopened.container.mainContext.fetch(
                FetchDescriptor<FlightRecord>()
            )
            XCTAssertEqual(records.map(\.flightNumber), ["KEEP1"])
            XCTAssertEqual(
                try LegacyStoreMigrationService.currentState(configuration)?.status,
                .deferred
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        }
    }

    func testEmptyLegacyStoreDoesNotProduceImportOfferButIsBackedUp() throws {
        try withTemporaryDirectory { directory in
            let legacyURL = directory.appendingPathComponent("default.store")
            let configuration = LegacyStoreMigrationConfiguration(
                sourceStoreURL: legacyURL,
                backupDirectoryURL: directory.appendingPathComponent(
                    "LegacyBackups",
                    isDirectory: true
                ),
                markerURL: directory.appendingPathComponent("marker.json")
            )
            _ = try PersistenceController(storeURL: legacyURL)

            XCTAssertNil(try LegacyStoreMigrationService.inspect(configuration))
            let backups = try FileManager.default.contentsOfDirectory(
                at: configuration.backupDirectoryURL,
                includingPropertiesForKeys: nil
            )
            XCTAssertEqual(backups.count, 1)
            XCTAssertEqual(
                try LegacyStoreMigrationService.currentState(configuration)?.status,
                .noData
            )
        }
    }

    func testUnchangedEmptyAndIncompatibleStoresAreBackedUpOnlyOnce() throws {
        try withTemporaryDirectory { directory in
            for (name, contents, expectedStatus) in [
                ("empty.store", nil, LegacyStoreStatus.noData),
                ("broken.store", Data("not sqlite".utf8), .incompatible),
            ] {
                let source = directory.appendingPathComponent(name)
                if let contents {
                    try contents.write(to: source)
                } else {
                    _ = try PersistenceController(storeURL: source)
                }
                let configuration = migrationConfiguration(
                    source: source,
                    directory: directory,
                    markerName: "\(name).json"
                )

                XCTAssertNil(try LegacyStoreMigrationService.inspect(configuration))
                XCTAssertNil(try LegacyStoreMigrationService.inspect(configuration))

                XCTAssertEqual(
                    try LegacyStoreMigrationService.currentState(configuration)?.status,
                    expectedStatus
                )
                XCTAssertEqual(
                    try FileManager.default.contentsOfDirectory(
                        at: configuration.backupDirectoryURL,
                        includingPropertiesForKeys: nil
                    ).count,
                    1
                )
            }
        }
    }

    func testDeferredStoreDoesNotBackupAgainUntilExplicitRetry() throws {
        try withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("default.store")
            let legacy = try PersistenceController(storeURL: source)
            legacy.container.mainContext.insert(
                makeRecord(id: uuid(1), flightNumber: "DEFER1")
            )
            try legacy.container.mainContext.save()
            let configuration = migrationConfiguration(
                source: source,
                directory: directory,
                markerName: "state.json"
            )

            XCTAssertNotNil(try LegacyStoreMigrationService.inspect(configuration))
            XCTAssertNil(try LegacyStoreMigrationService.inspect(configuration))
            XCTAssertEqual(
                try LegacyStoreMigrationService.currentState(configuration)?.status,
                .deferred
            )
            XCTAssertNotNil(
                try LegacyStoreMigrationService.inspect(
                    configuration,
                    forceRetry: true
                )
            )
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(
                    at: configuration.backupDirectoryURL,
                    includingPropertiesForKeys: nil
                ).count,
                2
            )
        }
    }

    func testLegacyInspectionNormalizesFlightDateAndReportsCount() throws {
        try withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("default.store")
            let legacy = try PersistenceController(storeURL: source)
            let record = makeRecord(id: uuid(1), flightNumber: "NORMALIZE1")
            record.flightDate = record.flightDate.addingTimeInterval(86_400)
            legacy.container.mainContext.insert(record)
            try legacy.container.mainContext.save()
            let configuration = migrationConfiguration(
                source: source,
                directory: directory,
                markerName: "normalize.json"
            )

            let candidate = try XCTUnwrap(
                LegacyStoreMigrationService.inspect(configuration)
            )

            XCTAssertEqual(candidate.normalizedFlightDateCount, 1)
            XCTAssertTrue(
                FlightDateNormalization.isSameDate(
                    try XCTUnwrap(candidate.records.first).flightDate,
                    record.departureDate
                )
            )
        }
    }

    private func migrationConfiguration(
        source: URL,
        directory: URL,
        markerName: String
    ) -> LegacyStoreMigrationConfiguration {
        LegacyStoreMigrationConfiguration(
            sourceStoreURL: source,
            backupDirectoryURL: directory.appendingPathComponent(
                "\(markerName)-backups",
                isDirectory: true
            ),
            markerURL: directory.appendingPathComponent(markerName)
        )
    }

    private func withTemporaryDirectory(
        _ body: (URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try body(directory)
    }

    private func makeRecord(id: UUID, flightNumber: String) -> FlightRecord {
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
            id: id,
            flightNumber: flightNumber,
            airlineCode: "TS",
            airlineName: "Test Air",
            flightDate: base,
            departureAirport: departure,
            arrivalAirport: arrival,
            departureDate: base.addingTimeInterval(3_600),
            arrivalDate: base.addingTimeInterval(7_200),
            ownerProfileID: UserProfileDefaults.id,
            createdAt: base,
            updatedAt: base
        )
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "00000000-0000-0000-0000-%012d",
                value
            )
        )!
    }
}
