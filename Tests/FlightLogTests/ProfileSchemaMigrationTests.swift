import CoreData
import CryptoKit
import Foundation
import SQLite3
import SwiftData
import XCTest
@testable import FlightLog

@MainActor
final class ProfileSchemaMigrationTests: XCTestCase {
    private static let publishedV1FlightRecordHash =
        "r8AG8DwtP4EIhUTj9H5Jr6rgexvXIF0q8Eo41nDFfDA="

    func testV1ModelHashMatchesFrozenPublishedStoreMetadata() throws {
        try withTemporaryStore { storeURL in
            try createV1Store(at: storeURL)

            let metadata = try NSPersistentStoreCoordinator
                .metadataForPersistentStore(
                    ofType: NSSQLiteStoreType,
                    at: storeURL
                )
            let hashes = try XCTUnwrap(
                metadata[NSStoreModelVersionHashesKey] as? [String: Data]
            )
            let identifiers = try XCTUnwrap(
                metadata[NSStoreModelVersionIdentifiersKey] as? [String]
            )

            XCTAssertEqual(
                hashes["FlightRecord"]?.base64EncodedString(),
                Self.publishedV1FlightRecordHash
            )
            XCTAssertEqual(identifiers, ["1.0.0"])
        }
    }

    func testRealV1DiskStoreMigratesEveryFlightFieldAndBackfillsOwner() throws {
        try withTemporaryStore { storeURL in
            try createV1Store(at: storeURL)

            let migrated = try PersistenceController(storeURL: storeURL)
            let records = try migrated.container.mainContext.fetch(
                FetchDescriptor<FlightRecord>()
            )
            let profiles = try migrated.container.mainContext.fetch(
                FetchDescriptor<UserProfile>()
            )

            let record = try XCTUnwrap(records.first)
            XCTAssertEqual(records.count, 1)
            XCTAssertEqual(record.id, uuid(1))
            XCTAssertEqual(record.flightNumber, "V1-001")
            XCTAssertEqual(record.airlineCode, "V1")
            XCTAssertEqual(record.airlineName, "Version One Air")
            XCTAssertEqual(record.flightDate, date(1_800_000_000))
            XCTAssertEqual(record.departureAirportIATA, "PEK")
            XCTAssertEqual(record.departureDate, date(1_800_003_600))
            XCTAssertEqual(record.departureTimeZoneID, "Asia/Shanghai")
            XCTAssertEqual(record.departureLocalDateTime, "2027-01-15T09:00")
            XCTAssertEqual(record.departureUTCOffsetSeconds, 28_800)
            XCTAssertEqual(record.departureAirportName, "北京首都国际机场")
            XCTAssertEqual(record.departureCity, "北京")
            XCTAssertEqual(record.departureCountry, "中国")
            XCTAssertEqual(record.departureCountryCode, "CN")
            XCTAssertEqual(record.departureLatitude, 40.0801)
            XCTAssertEqual(record.departureLongitude, 116.5846)
            XCTAssertEqual(record.arrivalAirportIATA, "YUL")
            XCTAssertEqual(record.arrivalDate, date(1_800_021_600))
            XCTAssertEqual(record.arrivalTimeZoneID, "America/Toronto")
            XCTAssertEqual(record.arrivalLocalDateTime, "2027-01-14T19:00")
            XCTAssertEqual(record.arrivalUTCOffsetSeconds, -18_000)
            XCTAssertEqual(record.arrivalAirportName, "蒙特利尔特鲁多国际机场")
            XCTAssertEqual(record.arrivalCity, "蒙特利尔")
            XCTAssertEqual(record.arrivalCountry, "加拿大")
            XCTAssertEqual(record.arrivalCountryCode, "CA")
            XCTAssertEqual(record.arrivalLatitude, 45.4706)
            XCTAssertEqual(record.arrivalLongitude, -73.7408)
            XCTAssertEqual(record.aircraftType, "A350")
            XCTAssertEqual(record.cabinClass, "商务舱")
            XCTAssertEqual(record.seat, "3A")
            XCTAssertEqual(record.notes, "V1 migration fixture")
            XCTAssertEqual(record.createdAt, date(1_799_900_000))
            XCTAssertEqual(record.updatedAt, date(1_799_950_000))
            XCTAssertEqual(record.ownerProfileID, UserProfileDefaults.id)
            XCTAssertEqual(profiles.count, 1)
            XCTAssertEqual(profiles.first?.id, UserProfileDefaults.id)
            XCTAssertEqual(profiles.first?.displayName, "我的档案")
        }
    }

    func testPackagedReleaseMigratesWALFixtureIdempotentlyAndPreservesFailedSource()
        throws
    {
        guard
            let appPath = ProcessInfo.processInfo.environment[
                "FLIGHTLOG_RELEASE_APP_PATH"
            ],
            !appPath.isEmpty
        else {
            throw XCTSkip(
                "Set FLIGHTLOG_RELEASE_APP_PATH to run the packaged-app migration gate."
            )
        }
        let executableURL = URL(fileURLWithPath: appPath)
            .appendingPathComponent("Contents/MacOS/FlightLog")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path)
        else {
            XCTFail("Release executable is missing: \(executableURL.path)")
            return
        }

        let temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlightLog-release-migration-\(UUID())")
        let storeURL = temporaryHome
            .appendingPathComponent("Library/Application Support/FlightLog")
            .appendingPathComponent("FlightLog.store")
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryHome) }

        do {
            let fixture = try createOpenV1Store(at: storeURL)
            let checkpoint = try forceWALCheckpoint(at: storeURL)
            XCTAssertEqual(
                checkpoint.logFrameCount,
                checkpoint.checkpointedFrameCount
            )
            let record = try XCTUnwrap(
                try fixture.mainContext.fetch(
                    FetchDescriptor<FlightLogSchemaV1.FlightRecord>()
                ).first
            )
            record.notes = "release WAL migration fixture"
            try fixture.mainContext.save()
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: storeURL.path + "-wal")
            )
            withExtendedLifetime(fixture) {}
        }

        let sourceMetadata = try NSPersistentStoreCoordinator
            .metadataForPersistentStore(
                ofType: NSSQLiteStoreType,
                at: storeURL
            )
        let sourceHashes = try XCTUnwrap(
            sourceMetadata[NSStoreModelVersionHashesKey] as? [String: Data]
        )
        XCTAssertEqual(
            sourceHashes["FlightRecord"]?.base64EncodedString(),
            Self.publishedV1FlightRecordHash
        )
        let sourceFingerprint = try SystemLegacyStoreFileAccess()
            .contentFingerprint(for: storeURL)

        try launchRelease(
            executableURL: executableURL,
            temporaryHome: temporaryHome,
            storeURL: storeURL
        )
        let first = try PersistenceController.readOnly(storeURL: storeURL)
        let firstProfiles = try first.container.mainContext.fetch(
            FetchDescriptor<UserProfile>()
        )
        let firstRecords = try first.container.mainContext.fetch(
            FetchDescriptor<FlightRecord>()
        )
        XCTAssertEqual(firstProfiles.count, 1)
        XCTAssertEqual(firstRecords.count, 1)
        XCTAssertEqual(firstRecords.first?.ownerProfileID, UserProfileDefaults.id)
        XCTAssertEqual(firstRecords.first?.notes, "release WAL migration fixture")

        try launchRelease(
            executableURL: executableURL,
            temporaryHome: temporaryHome,
            storeURL: storeURL
        )
        let second = try PersistenceController.readOnly(storeURL: storeURL)
        XCTAssertEqual(
            try second.container.mainContext.fetch(
                FetchDescriptor<UserProfile>()
            ).count,
            1
        )
        XCTAssertEqual(
            try second.container.mainContext.fetch(
                FetchDescriptor<FlightRecord>()
            ).count,
            1
        )

        let failedHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlightLog-release-failure-\(UUID())")
        let failedStoreURL = failedHome
            .appendingPathComponent("Library/Application Support/FlightLog")
            .appendingPathComponent("FlightLog.store")
        try FileManager.default.createDirectory(
            at: failedStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: failedHome) }
        let invalidSource = Data("not a SwiftData store".utf8)
        try invalidSource.write(to: failedStoreURL)
        let invalidHash = SHA256.hash(data: invalidSource)

        try launchRelease(
            executableURL: executableURL,
            temporaryHome: failedHome,
            storeURL: failedStoreURL,
            expectsMigration: false
        )
        XCTAssertEqual(
            SHA256.hash(data: try Data(contentsOf: failedStoreURL)),
            invalidHash
        )
        XCTAssertEqual(try Data(contentsOf: failedStoreURL), invalidSource)

        print(
            "MULTI_USER_MIGRATION sourceHash=\(sourceFingerprint) "
                + "beforeProfiles=0 beforeRecords=1 "
                + "afterProfiles=\(firstProfiles.count) "
                + "afterRecords=\(firstRecords.count) "
                + "secondProfiles=1 secondRecords=1 "
                + "failedSourcePreserved=true"
        )
    }

    func testReleaseMigrationGateRequiresBootstrapNotSchemaMetadataAlone() throws {
        try withTemporaryStore { storeURL in
            try createV2StoreWithoutProfiles(at: storeURL)
            XCTAssertTrue(ReleaseMigrationGate.hasV2SchemaMetadata(at: storeURL))
            XCTAssertFalse(ReleaseMigrationGate.isPostconditionMet(at: storeURL))
            XCTAssertTrue(
                ReleaseMigrationGate.wouldLegacyMetadataGateComplete(
                    on: [
                        ReleaseMigrationGate.hasV2SchemaMetadata(at: storeURL),
                    ]
                ),
                "Legacy metadata-only gate would complete before bootstrap"
            )
            XCTAssertFalse(
                ReleaseMigrationGate.wouldStablePostconditionGateComplete(
                    postconditionStates: [
                        ReleaseMigrationGate.isPostconditionMet(at: storeURL),
                        ReleaseMigrationGate.isPostconditionMet(at: storeURL),
                        ReleaseMigrationGate.isPostconditionMet(at: storeURL),
                    ]
                ),
                "Stable gate must not complete while profiles are missing"
            )

            _ = try PersistenceController(storeURL: storeURL)

            XCTAssertTrue(ReleaseMigrationGate.isPostconditionMet(at: storeURL))
            XCTAssertTrue(
                ReleaseMigrationGate.wouldStablePostconditionGateComplete(
                    postconditionStates: [
                        true,
                        true,
                        true,
                    ]
                )
            )
        }
    }

    func testReleaseMigrationGateAcceptsAnyPersistedProfileWithNoRecords() throws {
        try withTemporaryStore { storeURL in
            let profileID = uuid(41)
            let schema = Schema(versionedSchema: FlightLogSchemaV2.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    "FlightLogV2NonDefaultProfileFixture",
                    schema: schema,
                    url: storeURL
                )
            )
            container.mainContext.insert(
                UserProfile(
                    id: profileID,
                    displayName: "保留用户",
                    sortOrder: 0,
                    comparisonColorRawValue: "orange"
                )
            )
            try container.mainContext.save()

            XCTAssertTrue(ReleaseMigrationGate.hasV2SchemaMetadata(at: storeURL))
            XCTAssertTrue(
                ReleaseMigrationGate.isPostconditionMet(at: storeURL),
                "An empty flight log is complete once V2 has a persisted profile"
            )
        }
    }

    func testReleaseMigrationGateRejectsRecordWithUnknownOwner() throws {
        try withTemporaryStore { storeURL in
            let profileID = uuid(42)
            let schema = Schema(versionedSchema: FlightLogSchemaV2.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    "FlightLogV2UnknownOwnerFixture",
                    schema: schema,
                    url: storeURL
                )
            )
            container.mainContext.insert(
                UserProfile(
                    id: profileID,
                    displayName: "保留用户",
                    sortOrder: 0,
                    comparisonColorRawValue: "orange"
                )
            )
            container.mainContext.insert(
                makeRecord(id: uuid(43), ownerProfileID: uuid(99))
            )
            try container.mainContext.save()

            XCTAssertFalse(ReleaseMigrationGate.isPostconditionMet(at: storeURL))
        }
    }

    func testReleaseMigrationGateStateMachineRequiresConsecutiveStablePolls() {
        XCTAssertFalse(
            ReleaseMigrationGate.wouldStablePostconditionGateComplete(
                postconditionStates: [false, true, false, true, false, true]
            ),
            "A flicker before bootstrap must reset stable completion"
        )
        XCTAssertFalse(
            ReleaseMigrationGate.wouldStablePostconditionGateComplete(
                postconditionStates: [true, true]
            ),
            "Two stable polls are insufficient"
        )
        XCTAssertTrue(
            ReleaseMigrationGate.wouldStablePostconditionGateComplete(
                postconditionStates: [false, false, true, true, true]
            ),
            "Three consecutive stable polls should complete the gate"
        )
        XCTAssertFalse(
            ReleaseMigrationGate.wouldLegacyMetadataGateComplete(
                on: [false, false, false]
            )
        )
        XCTAssertTrue(
            ReleaseMigrationGate.wouldLegacyMetadataGateComplete(
                on: [false, true, false]
            ),
            "Legacy gate completes on first metadata signal regardless of stability"
        )
    }

    func testReleaseMigrationGateRegressionDelayedBootstrapSave() throws {
        try withTemporaryStore { storeURL in
            try createV1Store(at: storeURL)
            var saveCount = 0
            let controller = try PersistenceController(
                storeURL: storeURL,
                bootstrapSave: { context in
                    saveCount += 1
                    if saveCount == 1 {
                        Thread.sleep(forTimeInterval: 0.35)
                    }
                    try context.save()
                }
            )
            defer { _ = controller }

            XCTAssertTrue(ReleaseMigrationGate.isPostconditionMet(at: storeURL))
            XCTAssertGreaterThanOrEqual(saveCount, 1)
        }
    }

    func testNewStoreBootstrapsDefaultProfile() throws {
        try withTemporaryStore { storeURL in
            let controller = try PersistenceController(storeURL: storeURL)

            let profiles = try controller.container.mainContext.fetch(
                FetchDescriptor<UserProfile>()
            )

            XCTAssertEqual(profiles.count, 1)
            XCTAssertEqual(profiles.first?.id, UserProfileDefaults.id)
            XCTAssertEqual(profiles.first?.displayName, UserProfileDefaults.displayName)
            XCTAssertEqual(profiles.first?.sortOrder, 0)
            XCTAssertFalse(
                try XCTUnwrap(profiles.first?.comparisonColorRawValue).isEmpty
            )
        }
    }

    func testReadOnlyLegacyInspectionLeavesEntireV1WALStoreSetUnchanged() throws {
        try withTemporaryStore { storeURL in
            let container = try createOpenV1Store(at: storeURL)
            let checkpoint = try forceWALCheckpoint(at: storeURL)
            XCTAssertEqual(
                checkpoint.logFrameCount,
                checkpoint.checkpointedFrameCount
            )
            let record = try XCTUnwrap(
                try container.mainContext.fetch(
                    FetchDescriptor<FlightLogSchemaV1.FlightRecord>()
                ).first
            )
            record.notes = "written after forced checkpoint"
            try container.mainContext.save()
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: storeURL.path + "-wal"
                )
            )
            let original = try storeSetSnapshot(for: storeURL)

            XCTAssertThrowsError(
                try PersistenceController.readOnly(storeURL: storeURL)
            )
            let records = try LegacyStoreRecordReader.read(from: storeURL)

            XCTAssertEqual(records.map(\.flightNumber), ["V1-001"])
            XCTAssertEqual(try storeSetSnapshot(for: storeURL), original)
            withExtendedLifetime(container) {}
        }
    }

    func testRepeatedStartupDoesNotDuplicateDefaultProfile() throws {
        try withTemporaryStore { storeURL in
            _ = try PersistenceController(storeURL: storeURL)
            let reopened = try PersistenceController(storeURL: storeURL)

            let profiles = try reopened.container.mainContext.fetch(
                FetchDescriptor<UserProfile>()
            )

            XCTAssertEqual(profiles.map(\.id), [UserProfileDefaults.id])
        }
    }

    func testRepairPreservesExistingProfilesAndValidOwners() throws {
        try withTemporaryStore { storeURL in
            let first = try PersistenceController(storeURL: storeURL)
            let secondProfileID = uuid(2)
            first.container.mainContext.insert(
                UserProfile(
                    id: secondProfileID,
                    displayName: "工作",
                    createdAt: date(1_800_000_000),
                    sortOrder: 1,
                    comparisonColorRawValue: "orange"
                )
            )
            first.container.mainContext.insert(
                makeRecord(id: uuid(3), ownerProfileID: secondProfileID)
            )
            try first.container.mainContext.save()

            let reopened = try PersistenceController(storeURL: storeURL)
            let profiles = try reopened.container.mainContext.fetch(
                FetchDescriptor<UserProfile>()
            )
            let records = try reopened.container.mainContext.fetch(
                FetchDescriptor<FlightRecord>()
            )

            XCTAssertEqual(Set(profiles.map(\.id)), [UserProfileDefaults.id, secondProfileID])
            XCTAssertEqual(records.first?.ownerProfileID, secondProfileID)
        }
    }

    func testStartupDoesNotResurrectDeletedDefaultAndUsesStableExistingFallback()
        throws
    {
        try withTemporaryStore { storeURL in
            let fallbackID = uuid(6)
            do {
                let first = try PersistenceController(storeURL: storeURL)
                first.container.mainContext.insert(
                    UserProfile(
                        id: fallbackID,
                        displayName: "保留用户",
                        createdAt: date(1_700_000_000),
                        sortOrder: 4,
                        comparisonColorRawValue: "orange"
                    )
                )
                let defaultProfile = try XCTUnwrap(
                    try first.container.mainContext.fetch(
                        FetchDescriptor<UserProfile>()
                    ).first { $0.id == UserProfileDefaults.id }
                )
                first.container.mainContext.delete(defaultProfile)
                first.container.mainContext.insert(
                    makeRecord(id: uuid(4), ownerProfileID: nil)
                )
                first.container.mainContext.insert(
                    makeRecord(id: uuid(5), ownerProfileID: uuid(99))
                )
                try first.container.mainContext.save()
            }

            let reopened = try PersistenceController(storeURL: storeURL)
            let profiles = try reopened.container.mainContext.fetch(
                FetchDescriptor<UserProfile>()
            )
            let records = try reopened.container.mainContext.fetch(
                FetchDescriptor<FlightRecord>()
            )

            XCTAssertEqual(profiles.map(\.id), [fallbackID])
            XCTAssertEqual(records.count, 2)
            XCTAssertTrue(
                records.allSatisfy {
                    $0.ownerProfileID == fallbackID
                }
            )
        }
    }

    func testRepairSaveFailureThrowsWithoutChangingStoreSet() throws {
        try withTemporaryStore { storeURL in
            try createV2StoreNeedingRepair(at: storeURL)
            let schema = Schema(versionedSchema: FlightLogSchemaV2.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    "ReadOnlyRepairFailure",
                    schema: schema,
                    url: storeURL,
                    allowsSave: false
                )
            )
            let original = try storeSetSnapshot(for: storeURL)

            XCTAssertThrowsError(
                try ProfileStoreBootstrap.repair(in: ModelContext(container))
            )
            XCTAssertEqual(try storeSetSnapshot(for: storeURL), original)
        }
    }

    func testRepairWithNoChangesDoesNotAttemptSave() throws {
        try withTemporaryStore { storeURL in
            _ = try PersistenceController(storeURL: storeURL)
            let schema = Schema(versionedSchema: FlightLogSchemaV2.self)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(
                    "ReadOnlyNoOpRepair",
                    schema: schema,
                    url: storeURL,
                    allowsSave: false
                )
            )

            XCTAssertNoThrow(
                try ProfileStoreBootstrap.repair(in: ModelContext(container))
            )
        }
    }

    func testFailedMigrationNeverDeletesOrReplacesSourceStore() throws {
        try withTemporaryStore { storeURL in
            let original = Data("not a SwiftData store".utf8)
            try original.write(to: storeURL)

            XCTAssertThrowsError(try PersistenceController(storeURL: storeURL))
            XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
            XCTAssertEqual(try Data(contentsOf: storeURL), original)
        }
    }

    func testV1MigrationBootstrapFailureRestoresExactWALStoreSetAndRetriesCleanly()
        throws
    {
        try withTemporaryStore { storeURL in
            do {
                let fixture = try createOpenV1Store(at: storeURL)
                _ = try forceWALCheckpoint(at: storeURL)
                let record = try XCTUnwrap(
                    try fixture.mainContext.fetch(
                        FetchDescriptor<FlightLogSchemaV1.FlightRecord>()
                    ).first
                )
                record.notes = "rollback WAL payload"
                try fixture.mainContext.save()
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: storeURL.path + "-wal")
                )
                withExtendedLifetime(fixture) {}
            }
            let original = try storeSetSnapshot(for: storeURL)
            var failpointReached = false

            XCTAssertThrowsError(
                try PersistenceController(
                    storeURL: storeURL,
                    bootstrapSave: { _ in
                        failpointReached = true
                        throw CocoaError(.fileWriteUnknown)
                    }
                )
            )

            XCTAssertTrue(failpointReached)
            XCTAssertEqual(try storeSetSnapshot(for: storeURL), original)
            XCTAssertFalse(
                try FileManager.default.contentsOfDirectory(
                    atPath: storeURL.deletingLastPathComponent().path
                ).contains { $0.contains("migration-backup") }
            )

            let retried = try PersistenceController(storeURL: storeURL)
            let profiles = try retried.container.mainContext.fetch(
                FetchDescriptor<UserProfile>()
            )
            let records = try retried.container.mainContext.fetch(
                FetchDescriptor<FlightRecord>()
            )
            XCTAssertEqual(profiles.map(\.id), [UserProfileDefaults.id])
            XCTAssertEqual(records.count, 1)
            XCTAssertEqual(records.first?.notes, "rollback WAL payload")
            XCTAssertEqual(records.first?.ownerProfileID, UserProfileDefaults.id)
            XCTAssertFalse(
                try FileManager.default.contentsOfDirectory(
                    atPath: storeURL.deletingLastPathComponent().path
                ).contains { $0.contains("migration-backup") }
            )
        }
    }

    func testEveryRestoreFaultRetainsManifestBackupAndRecoversOnNextStartup()
        throws
    {
        for restorePoint in V1MigrationRestorePoint.allCases {
            try withTemporaryStore { storeURL in
                do {
                    let fixture = try createOpenV1Store(at: storeURL)
                    _ = try forceWALCheckpoint(at: storeURL)
                    let record = try XCTUnwrap(
                        try fixture.mainContext.fetch(
                            FetchDescriptor<FlightLogSchemaV1.FlightRecord>()
                        ).first
                    )
                    record.notes = "fault \(restorePoint.rawValue) WAL payload"
                    try fixture.mainContext.save()
                    withExtendedLifetime(fixture) {}
                }
                if restorePoint == .quarantineExtraSidecar {
                    try? FileManager.default.removeItem(
                        atPath: storeURL.path + "-shm"
                    )
                }
                let original = try storeSetSnapshot(for: storeURL)
                var injected = false

                XCTAssertThrowsError(
                    try PersistenceController(
                        storeURL: storeURL,
                        bootstrapSave: { _ in
                            throw CocoaError(.fileWriteUnknown)
                        },
                        migrationRestoreFault: { reachedPoint in
                            if reachedPoint == restorePoint, !injected {
                                injected = true
                                throw CocoaError(.fileWriteUnknown)
                            }
                        }
                    ),
                    "restore fault \(restorePoint.rawValue) 应中断恢复"
                )
                XCTAssertTrue(injected, "未触发 \(restorePoint.rawValue)")
                try assertPendingBackupPreserves(
                    original: original,
                    storeURL: storeURL
                )

                let recovered = try PersistenceController(storeURL: storeURL)
                let records = try recovered.container.mainContext.fetch(
                    FetchDescriptor<FlightRecord>()
                )
                XCTAssertEqual(records.count, 1)
                XCTAssertEqual(
                    records.first?.notes,
                    "fault \(restorePoint.rawValue) WAL payload"
                )
                XCTAssertEqual(
                    records.first?.ownerProfileID,
                    UserProfileDefaults.id
                )
                XCTAssertFalse(
                    try FileManager.default.contentsOfDirectory(
                        atPath: storeURL.deletingLastPathComponent().path
                    ).contains {
                        $0.contains("migration-backup")
                            || $0.contains("migration-staging")
                            || $0.contains("quarantine")
                    },
                    "成功恢复后不应残留事务文件：\(restorePoint.rawValue)"
                )
            }
        }
    }

    func testCommitRenameFailureRestoresV1BeforeInitializerCanPublishContainer()
        throws
    {
        try withTemporaryStore { storeURL in
            try createV1Store(at: storeURL)
            let original = try storeSetSnapshot(for: storeURL)
            var reached = false

            XCTAssertThrowsError(
                try PersistenceController(
                    storeURL: storeURL,
                    migrationTransactionFault: { point in
                        guard point == .beforeCommitRename else { return }
                        reached = true
                        throw CocoaError(.fileWriteUnknown)
                    }
                )
            )
            XCTAssertTrue(reached)
            XCTAssertEqual(try storeSetSnapshot(for: storeURL), original)
            XCTAssertFalse(
                try transactionArtifacts(for: storeURL).contains {
                    $0.contains("migration-backup")
                }
            )
        }
    }

    func testCommitRenameThenDeleteInterruptionReopensV2WithoutRestore()
        throws
    {
        try withTemporaryStore { storeURL in
            try createV1Store(at: storeURL)
            var reached = false

            XCTAssertThrowsError(
                try PersistenceController(
                    storeURL: storeURL,
                    migrationTransactionFault: { point in
                        guard point == .afterCommitRenameBeforeDelete else {
                            return
                        }
                        reached = true
                        throw CocoaError(.fileWriteUnknown)
                    }
                )
            )
            XCTAssertTrue(reached)
            let interrupted = try transactionArtifacts(for: storeURL)
            XCTAssertFalse(interrupted.contains {
                $0.contains("migration-backup")
            })
            XCTAssertTrue(interrupted.contains {
                $0.contains("migration-committed")
            })

            let reopened = try PersistenceController(storeURL: storeURL)
            XCTAssertEqual(
                try reopened.container.mainContext.fetch(
                    FetchDescriptor<FlightRecord>()
                ).first?.notes,
                "V1 migration fixture"
            )
            XCTAssertTrue(try transactionArtifacts(for: storeURL).isEmpty)
        }
    }

    func testRecoveryRenameThenDeleteInterruptionReopensAndMigratesNormally()
        throws
    {
        try withTemporaryStore { storeURL in
            try createV1Store(at: storeURL)
            var reached = false

            XCTAssertThrowsError(
                try PersistenceController(
                    storeURL: storeURL,
                    bootstrapSave: { _ in
                        throw CocoaError(.fileWriteUnknown)
                    },
                    migrationTransactionFault: { point in
                        guard point == .afterRecoveryRenameBeforeDelete else {
                            return
                        }
                        reached = true
                        throw CocoaError(.fileWriteUnknown)
                    }
                )
            )
            XCTAssertTrue(reached)
            let interrupted = try transactionArtifacts(for: storeURL)
            XCTAssertFalse(interrupted.contains {
                $0.contains("migration-backup")
            })
            XCTAssertTrue(interrupted.contains {
                $0.contains("migration-recovered")
            })

            let reopened = try PersistenceController(storeURL: storeURL)
            XCTAssertEqual(
                try reopened.container.mainContext.fetch(
                    FetchDescriptor<FlightRecord>()
                ).first?.notes,
                "V1 migration fixture"
            )
            XCTAssertTrue(try transactionArtifacts(for: storeURL).isEmpty)
        }
    }

    func testProfileNameNormalizationAndValidation() {
        XCTAssertEqual(
            UserProfileNameValidator.normalize("  Alice \n  Zhang  "),
            "Alice Zhang"
        )
        XCTAssertNoThrow(
            try UserProfileNameValidator.validatedName(
                "  Alice \n  Zhang  ",
                existingNames: ["Bob"]
            )
        )
        XCTAssertThrowsError(
            try UserProfileNameValidator.validatedName(
                "alice",
                existingNames: ["ALICE"]
            )
        ) { error in
            XCTAssertEqual(error as? UserProfileNameValidationError, .duplicate)
        }
        XCTAssertThrowsError(
            try UserProfileNameValidator.validatedName(" \n ", existingNames: [])
        ) { error in
            XCTAssertEqual(error as? UserProfileNameValidationError, .invalidLength)
        }
        XCTAssertThrowsError(
            try UserProfileNameValidator.validatedName(
                String(repeating: "名", count: 31),
                existingNames: []
            )
        ) { error in
            XCTAssertEqual(error as? UserProfileNameValidationError, .invalidLength)
        }
        XCTAssertEqual(
            try UserProfileNameValidator.validatedName(
                String(repeating: "名", count: 30),
                existingNames: []
            ),
            String(repeating: "名", count: 30)
        )
    }

    func testProfileNameCanonicalUnicodeAndEditingExclusion() throws {
        let firstID = uuid(20)
        let otherID = uuid(21)
        let decomposedCafe = "Cafe\u{301}"

        XCTAssertEqual(UserProfileNameValidator.normalize(decomposedCafe), "Café")
        XCTAssertThrowsError(
            try UserProfileNameValidator.validatedName(
                decomposedCafe,
                existingProfiles: [
                    .init(id: firstID, displayName: "CAFÉ")
                ]
            )
        ) { error in
            XCTAssertEqual(error as? UserProfileNameValidationError, .duplicate)
        }
        XCTAssertThrowsError(
            try UserProfileNameValidator.validatedName(
                "Ａｌｉｃｅ",
                existingProfiles: [
                    .init(id: firstID, displayName: "Alice")
                ]
            )
        ) { error in
            XCTAssertEqual(error as? UserProfileNameValidationError, .duplicate)
        }
        XCTAssertEqual(
            try UserProfileNameValidator.validatedName(
                decomposedCafe,
                existingProfiles: [
                    .init(id: firstID, displayName: "CAFÉ")
                ],
                excludingProfileID: firstID
            ),
            "Café"
        )
        XCTAssertEqual(
            try UserProfileNameValidator.validatedName(
                decomposedCafe,
                existingProfiles: [
                    .init(id: firstID, displayName: "CAFÉ"),
                    .init(id: otherID, displayName: "cafe")
                ],
                excludingProfileID: firstID
            ),
            "Café"
        )
    }

    private func createV1Store(at storeURL: URL) throws {
        _ = try createOpenV1Store(at: storeURL)
    }

    private func createOpenV1Store(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: FlightLogSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                "FlightLogV1Fixture",
                schema: schema,
                url: storeURL
            )
        )
        container.mainContext.insert(
            FlightLogSchemaV1.FlightRecord(
                id: uuid(1),
                flightNumber: "V1-001",
                airlineCode: "V1",
                airlineName: "Version One Air",
                flightDate: date(1_800_000_000),
                departureAirportIATA: "PEK",
                departureDate: date(1_800_003_600),
                departureTimeZoneID: "Asia/Shanghai",
                departureLocalDateTime: "2027-01-15T09:00",
                departureUTCOffsetSeconds: 28_800,
                departureAirportName: "北京首都国际机场",
                departureCity: "北京",
                departureCountry: "中国",
                departureCountryCode: "CN",
                departureLatitude: 40.0801,
                departureLongitude: 116.5846,
                arrivalAirportIATA: "YUL",
                arrivalDate: date(1_800_021_600),
                arrivalTimeZoneID: "America/Toronto",
                arrivalLocalDateTime: "2027-01-14T19:00",
                arrivalUTCOffsetSeconds: -18_000,
                arrivalAirportName: "蒙特利尔特鲁多国际机场",
                arrivalCity: "蒙特利尔",
                arrivalCountry: "加拿大",
                arrivalCountryCode: "CA",
                arrivalLatitude: 45.4706,
                arrivalLongitude: -73.7408,
                aircraftType: "A350",
                cabinClass: "商务舱",
                seat: "3A",
                notes: "V1 migration fixture",
                createdAt: date(1_799_900_000),
                updatedAt: date(1_799_950_000)
            )
        )
        try container.mainContext.save()
        return container
    }

    private func createV2StoreNeedingRepair(at storeURL: URL) throws {
        let schema = Schema(versionedSchema: FlightLogSchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                "FlightLogV2RepairFixture",
                schema: schema,
                url: storeURL
            )
        )
        let defaultProfile = UserProfile(
            id: UserProfileDefaults.id,
            displayName: UserProfileDefaults.displayName,
            sortOrder: 0,
            comparisonColorRawValue:
                UserProfileDefaults.comparisonColorRawValue
        )
        container.mainContext.insert(defaultProfile)
        container.mainContext.insert(
            makeRecord(id: uuid(30), ownerProfileID: nil)
        )
        container.mainContext.insert(
            makeRecord(id: uuid(31), ownerProfileID: uuid(99))
        )
        try container.mainContext.save()
    }

    private func createV2StoreWithoutProfiles(at storeURL: URL) throws {
        let schema = Schema(versionedSchema: FlightLogSchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                "FlightLogV2NoProfilesFixture",
                schema: schema,
                url: storeURL
            )
        )
        container.mainContext.insert(
            makeRecord(id: uuid(40), ownerProfileID: nil)
        )
        try container.mainContext.save()
    }

    private func makeRecord(id: UUID, ownerProfileID: UUID?) -> FlightRecord {
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
        let record = FlightRecord(
            id: id,
            flightNumber: "OWNER1",
            airlineCode: "TS",
            airlineName: "Test Air",
            flightDate: date(1_800_000_000),
            departureAirport: departure,
            arrivalAirport: arrival,
            departureDate: date(1_800_003_600),
            arrivalDate: date(1_800_021_600),
            ownerProfileID: ownerProfileID ?? UserProfileDefaults.id,
            createdAt: date(1_799_900_000),
            updatedAt: date(1_799_950_000)
        )
        if ownerProfileID == nil {
            record.ownerProfileID = nil
        }
        return record
    }

    private func withTemporaryStore(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("FlightLog.store"))
    }

    private struct FileSnapshot: Equatable {
        let exists: Bool
        let sha256: String?
        let size: UInt64?
        let modificationTime: Date?
    }

    private struct StoreSetSnapshot: Equatable {
        let files: [String: FileSnapshot]
        let directoryContents: [String]
    }

    private func storeSetSnapshot(for storeURL: URL) throws -> StoreSetSnapshot {
        var files: [String: FileSnapshot] = [:]
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            guard FileManager.default.fileExists(atPath: url.path) else {
                files[suffix] = FileSnapshot(
                    exists: false,
                    sha256: nil,
                    size: nil,
                    modificationTime: nil
                )
                continue
            }
            let data = try Data(contentsOf: url)
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
            files[suffix] = FileSnapshot(
                exists: true,
                sha256: SHA256.hash(data: data).map {
                    String(format: "%02x", $0)
                }.joined(),
                size: (attributes[.size] as? NSNumber)?.uint64Value,
                modificationTime: attributes[.modificationDate] as? Date
            )
        }
        let directoryContents = try FileManager.default.contentsOfDirectory(
            atPath: storeURL.deletingLastPathComponent().path
        ).sorted()
        return StoreSetSnapshot(
            files: files,
            directoryContents: directoryContents
        )
    }

    private func assertPendingBackupPreserves(
        original: StoreSetSnapshot,
        storeURL: URL
    ) throws {
        let parent = storeURL.deletingLastPathComponent()
        let backupNames = try FileManager.default.contentsOfDirectory(
            atPath: parent.path
        ).filter { $0.contains(".migration-backup-") }
        XCTAssertEqual(backupNames.count, 1)
        let backup = parent.appendingPathComponent(
            try XCTUnwrap(backupNames.first),
            isDirectory: true
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: backup.appendingPathComponent("manifest.json").path
            )
        )
        for suffix in ["", "-wal", "-shm"] {
            let expected = try XCTUnwrap(original.files[suffix])
            guard expected.exists else { continue }
            let copy = backup.appendingPathComponent(
                storeURL.lastPathComponent + suffix
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
            let data = try Data(contentsOf: copy)
            let hash = SHA256.hash(data: data).map {
                String(format: "%02x", $0)
            }.joined()
            XCTAssertEqual(hash, expected.sha256)
            XCTAssertEqual(UInt64(data.count), expected.size)
        }
    }

    private func transactionArtifacts(for storeURL: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            atPath: storeURL.deletingLastPathComponent().path
        ).filter {
            $0.contains("migration-backup")
                || $0.contains("migration-committed")
                || $0.contains("migration-recovered")
        }
    }

    private func forceWALCheckpoint(
        at storeURL: URL
    ) throws -> (logFrameCount: Int32, checkpointedFrameCount: Int32) {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            storeURL.path,
            &database,
            SQLITE_OPEN_READWRITE,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            defer { sqlite3_close(database) }
            throw NSError(
                domain: "ProfileSchemaMigrationTests.SQLite",
                code: Int(openResult)
            )
        }
        defer { sqlite3_close(database) }
        var logFrameCount: Int32 = 0
        var checkpointedFrameCount: Int32 = 0
        let checkpointResult = sqlite3_wal_checkpoint_v2(
            database,
            nil,
            SQLITE_CHECKPOINT_FULL,
            &logFrameCount,
            &checkpointedFrameCount
        )
        guard checkpointResult == SQLITE_OK else {
            throw NSError(
                domain: "ProfileSchemaMigrationTests.SQLite",
                code: Int(checkpointResult)
            )
        }
        return (logFrameCount, checkpointedFrameCount)
    }

    private func launchRelease(
        executableURL: URL,
        temporaryHome: URL,
        storeURL: URL,
        expectsMigration: Bool = true
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = temporaryHome.path
        environment["CFFIXED_USER_HOME"] = temporaryHome.path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
        }

        if expectsMigration {
            let completed = ReleaseMigrationGate.awaitPostcondition(
                storeURL: storeURL,
                process: process,
                timeout: 12
            )
            if !completed {
                if !process.isRunning {
                    XCTFail(
                        "Release app exited before migration completed "
                            + "(status \(process.terminationStatus))."
                    )
                } else {
                    XCTFail(
                        "Release app did not reach stable migration postcondition "
                            + "(V2 schema + default profile + owner backfill, "
                            + "\(ReleaseMigrationGate.stablePollCount) consecutive polls) "
                            + "within 12 seconds."
                    )
                }
            }
        } else {
            Thread.sleep(forTimeInterval: 1)
            XCTAssertTrue(
                process.isRunning,
                "Recovery UI process exited unexpectedly."
            )
        }
    }

    private func date(_ timestamp: TimeInterval) -> Date {
        Date(timeIntervalSince1970: timestamp)
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
