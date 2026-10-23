import Foundation
import SwiftData
import XCTest
@testable import FlightLog

final class ProfileBackupTask4Tests: XCTestCase {
    private let profileA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let profileB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    func testV2CurrentAndFullExportsRoundTripProfilesOwnersAndStableOrder() throws {
        let exportedAt = Date(timeIntervalSince1970: 1_787_100_000)
        let a = profile(profileA, "甲", order: 1, color: "blue")
        let b = profile(profileB, "乙", order: 0, color: "orange")
        let recordA = record(id: uuid(1), owner: profileA, number: "CA1")
        let recordB = record(id: uuid(2), owner: profileB, number: "MU2")

        let current = try BackupService.exportCurrent(
            profile: a,
            records: [recordA],
            exportedAt: exportedAt
        )
        let fullForward = try BackupService.exportAll(
            profiles: [a, b],
            records: [recordA, recordB],
            exportedAt: exportedAt
        )
        let fullReverse = try BackupService.exportAll(
            profiles: [b, a],
            records: [recordB, recordA],
            exportedAt: exportedAt
        )

        let currentBackup = try BackupService.decodeJSON(current)
        XCTAssertEqual(BackupService.currentSchemaVersion, 2)
        XCTAssertEqual(currentBackup.scope, .singleProfile)
        XCTAssertEqual(currentBackup.profiles, [UserProfileBackupDTO(profile: a)])
        XCTAssertEqual(currentBackup.records.first?.ownerProfileID, profileA)
        XCTAssertFalse(currentBackup.legacySingleProfile)
        XCTAssertEqual(fullForward, fullReverse)
        let full = try BackupService.decodeJSON(fullForward)
        XCTAssertEqual(full.scope, .fullArchive)
        XCTAssertEqual(full.profiles.map(\.id), [profileB, profileA])
        XCTAssertEqual(Set(full.records.compactMap(\.ownerProfileID)), [profileA, profileB])
    }

    func testV2ExportRejectsOrphanAndStillHonorsFileLimit() throws {
        let a = profile(profileA, "甲", order: 0, color: "blue")
        let orphan = record(id: uuid(1), owner: profileB, number: "CA1")

        XCTAssertThrowsError(
            try BackupService.exportAll(profiles: [a], records: [orphan])
        ) { error in
            XCTAssertEqual(error as? BackupServiceError, .orphanRecord(uuid(1), profileB))
        }

        let tiny = BackupLimits(
            maximumFileSize: 20,
            maximumRowCount: 10,
            maximumFieldLength: 10_000
        )
        XCTAssertThrowsError(
            try BackupService.exportCurrent(profile: a, records: [], limits: tiny)
        ) { error in
            XCTAssertEqual(error as? BackupServiceError, .exportedFileTooLarge(maximum: 20))
        }
    }

    func testV1DecodeIsLegacyAndRequiresExplicitTargetMapping() throws {
        let legacyRecord = FlightRecordBackupDTO(record: record(
            id: uuid(1),
            owner: profileA,
            number: "CA1"
        ))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: try BackupService.exportJSON(recordSnapshots: [legacyRecord])
            ) as? [String: Any]
        )
        object["schemaVersion"] = 1
        object.removeValue(forKey: "scope")
        object.removeValue(forKey: "profiles")
        var rows = try XCTUnwrap(object["records"] as? [[String: Any]])
        rows[0].removeValue(forKey: "ownerProfileID")
        object["records"] = rows
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try BackupService.decodeJSON(data)
        XCTAssertTrue(decoded.legacySingleProfile)
        XCTAssertNil(decoded.records[0].ownerProfileID)
        XCTAssertThrowsError(
            try BackupService.prepareJSONImport(
                data,
                existingRecordSnapshots: [],
                mode: .merge
            )
        ) { error in
            XCTAssertEqual(error as? BackupServiceError, .legacyTargetRequired)
        }

        let prepared = try BackupService.prepareJSONImport(
            data,
            existingRecordSnapshots: [],
            targetProfileID: profileB,
            mode: .merge
        )
        XCTAssertEqual(prepared.targetProfileID, profileB)
        XCTAssertEqual(prepared.sourceSchemaVersion, 1)
        XCTAssertEqual(
            prepared.mappingPlan.localProfileID(
                for: ProfileImportMappingPlan.legacySourceProfileID
            ),
            profileB
        )
    }

    func testLegacyEncoderWritesTrueV1EnvelopeWithoutV2OwnershipKeys() throws {
        let snapshot = FlightRecordBackupDTO(
            record: record(id: uuid(1), owner: profileA, number: "CA1")
        )
        let data = try BackupService.encodeLegacyV1JSON(
            recordSnapshots: [snapshot],
            exportedAt: Date(timeIntervalSince1970: 100)
        )
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(root["schemaVersion"] as? Int, 1)
        XCTAssertNil(root["profiles"])
        XCTAssertNil(root["scope"])
        let rows = try XCTUnwrap(root["records"] as? [[String: Any]])
        XCTAssertNil(rows[0]["ownerProfileID"])

        let prepared = try BackupService.prepareLegacyV1Import(
            data,
            existingRecordSnapshots: [],
            targetProfileID: profileB,
            mode: .merge
        )
        XCTAssertEqual(prepared.targetProfileID, profileB)
        XCTAssertEqual(prepared.sourceSchemaVersion, 1)
    }

    func testGeneralEncoderRejectsV1WhileLegacyEncoderStillRoundTrips() throws {
        let snapshot = FlightRecordBackupDTO(
            record: record(id: uuid(80), owner: profileA, number: "V1")
        )
        let v1 = FlightBackupDTO(
            schemaVersion: 1,
            exportedAt: Date(timeIntervalSince1970: 100),
            records: [snapshot]
        )
        XCTAssertThrowsError(try BackupService.encodeJSON(v1)) { error in
            XCTAssertEqual(
                error as? BackupServiceError,
                .unsupportedSchemaVersion(1)
            )
        }

        let data = try BackupService.encodeLegacyV1JSON(
            recordSnapshots: [snapshot]
        )
        let decoded = try BackupService.decodeJSON(data)
        XCTAssertTrue(decoded.legacySingleProfile)
        XCTAssertNil(decoded.records.first?.ownerProfileID)
    }

    func testFlightBackupDTOInitializerPreservesEmptyV2InputWithoutDefaults() {
        let backup = FlightBackupDTO(
            schemaVersion: 2,
            exportedAt: Date(timeIntervalSince1970: 100),
            scope: nil,
            profiles: [],
            records: []
        )

        XCTAssertNil(backup.scope)
        XCTAssertTrue(backup.profiles.isEmpty)
        XCTAssertTrue(backup.records.isEmpty)
    }

    func testValidV2EnvelopeRoundTripsThroughGeneralEncoder() throws {
        let profile = UserProfileBackupDTO(
            id: profileA,
            displayName: "甲",
            createdAt: Date(timeIntervalSince1970: 100),
            sortOrder: 0,
            color: "blue"
        )
        let original = FlightBackupDTO(
            schemaVersion: 2,
            exportedAt: Date(timeIntervalSince1970: 200),
            scope: .singleProfile,
            profiles: [profile],
            records: []
        )

        let decoded = try BackupService.decodeJSON(
            BackupService.encodeJSON(original)
        )

        XCTAssertEqual(decoded, original)
    }

    func testExportAllRejectsEmptyProfileListEvenWithNoRecords() {
        XCTAssertThrowsError(
            try BackupService.exportAll(
                profileSnapshots: [],
                recordSnapshots: []
            )
        ) { error in
            XCTAssertEqual(error as? BackupServiceError, .invalidJSON)
        }
    }

    func testV1RejectsAnyV2ProfilesScopeOrOwnerKeyEvenWhenNullOrEmpty() throws {
        let base = try JSONSerialization.jsonObject(
            with: try BackupService.encodeLegacyV1JSON(
                recordSnapshots: [
                    FlightRecordBackupDTO(
                        record: record(
                            id: uuid(1),
                            owner: profileA,
                            number: "CA1"
                        )
                    ),
                ]
            )
        ) as! [String: Any]

        for mutate in [
            { (root: inout [String: Any]) in root["profiles"] = [] },
            { (root: inout [String: Any]) in root["scope"] = NSNull() },
            { (root: inout [String: Any]) in
                var rows = root["records"] as! [[String: Any]]
                rows[0]["ownerProfileID"] = NSNull()
                root["records"] = rows
            },
        ] {
            var root = base
            mutate(&root)
            XCTAssertThrowsError(
                try BackupService.decodeJSON(
                    JSONSerialization.data(withJSONObject: root)
                )
            )
        }
    }

    func testMappingPlanValidatesCompletenessTargetsNamesAndDuplicateDestinations() throws {
        let sources = [
            UserProfileBackupDTO(profile: profile(profileA, "甲", order: 0, color: "blue")),
            UserProfileBackupDTO(profile: profile(profileB, "乙", order: 1, color: "orange")),
        ]
        let localID = uuid(9)
        let locals = [
            UserProfileBackupDTO(
                id: localID,
                displayName: "本地",
                createdAt: Date(timeIntervalSince1970: 1),
                sortOrder: 0,
                color: "green"
            ),
        ]

        XCTAssertNoThrow(try ProfileImportMappingPlan(entries: [
            .init(sourceProfileID: profileA, destination: .existing(localID)),
            .init(
                sourceProfileID: profileB,
                destination: .create(
                    localProfileID: uuid(10),
                    displayName: "新用户",
                    color: "purple"
                )
            ),
        ]).validated(sourceProfiles: sources, localProfiles: locals))

        for invalid in [
            ProfileImportMappingPlan(entries: [
                .init(sourceProfileID: profileA, destination: .existing(localID)),
            ]),
            ProfileImportMappingPlan(entries: [
                .init(sourceProfileID: profileA, destination: .existing(localID)),
                .init(sourceProfileID: profileB, destination: .existing(localID)),
            ]),
            ProfileImportMappingPlan(entries: [
                .init(
                    sourceProfileID: profileA,
                    destination: .create(
                        localProfileID: uuid(10),
                        displayName: "本地",
                        color: "red"
                    )
                ),
                .init(
                    sourceProfileID: profileB,
                    destination: .create(
                        localProfileID: uuid(11),
                        displayName: "新用户",
                        color: "blue"
                    )
                ),
            ]),
        ] {
            XCTAssertThrowsError(
                try invalid.validated(sourceProfiles: sources, localProfiles: locals)
            )
        }

        let invalidColor = ProfileImportMappingPlan(entries: [
            .init(
                sourceProfileID: profileA,
                destination: .create(
                    localProfileID: uuid(12),
                    displayName: "颜色错误",
                    color: "chartreuse"
                )
            ),
            .init(sourceProfileID: profileB, destination: .existing(localID)),
        ])
        XCTAssertThrowsError(
            try invalidColor.validated(
                sourceProfiles: sources,
                localProfiles: locals
            )
        )
    }

    @MainActor
    func testMappedMergeKeepsSameFlightAcrossProfilesAndRemapsGlobalUUIDConflict() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insert(profile(profileA, "甲", order: 0, color: "blue"), into: context)
        insert(profile(profileB, "乙", order: 1, color: "orange"), into: context)
        context.insert(record(id: uuid(1), owner: profileA, number: "CA1"))
        try context.save()

        let incoming = FlightRecordBackupDTO(
            record: record(id: uuid(1), owner: profileB, number: "CA1")
        )
        let mapping = ProfileImportMappingPlan(entries: [
            .init(sourceProfileID: profileB, destination: .existing(profileB)),
        ])
        let prepared = PreparedFlightImport(
            records: [incoming],
            report: FlightImportReport(format: .json, successCount: 1),
            mode: .merge,
            mappingPlan: mapping,
            sourceSchemaVersion: 2,
            sourceScope: .singleProfile,
            existingDatasetFingerprint: FlightDatasetFingerprint(
                profiles: [
                    UserProfileBackupDTO(profile: profile(profileA, "甲", order: 0, color: "blue")),
                    UserProfileBackupDTO(profile: profile(profileB, "乙", order: 1, color: "orange")),
                ],
                recordSnapshots: []
            ),
            occupiedRecordIDs: [uuid(1)]
        )

        let report = try BackupService.apply(prepared, to: context)
        let persisted = try context.fetch(FetchDescriptor<FlightRecord>())
        XCTAssertEqual(persisted.count, 2)
        XCTAssertEqual(Set(persisted.compactMap(\.ownerProfileID)), [profileA, profileB])
        XCTAssertEqual(report.remappedUUIDCount, 1)
        XCTAssertTrue(report.copyText.contains("UUID"))
        XCTAssertEqual(
            persisted.first { $0.ownerProfileID == profileB }?.id,
            BackupService.stableRemappedRecordID(
                sourceID: uuid(1),
                targetProfileID: profileB,
                attempt: 0
            )
        )
    }

    @MainActor
    func testReplaceCurrentLeavesOtherProfilesUntouched() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insert(profile(profileA, "甲", order: 0, color: "blue"), into: context)
        insert(profile(profileB, "乙", order: 1, color: "orange"), into: context)
        let oldA = record(id: uuid(1), owner: profileA, number: "OLDA")
        let keepB = record(id: uuid(2), owner: profileB, number: "KEEPB")
        context.insert(oldA)
        context.insert(keepB)
        try context.save()
        let incoming = FlightRecordBackupDTO(
            record: record(id: uuid(3), owner: profileA, number: "NEWA")
        )
        let plan = PreparedFlightImport(
            records: [incoming],
            report: FlightImportReport(format: .json, successCount: 1),
            mode: .replace,
            targetProfileID: profileA,
            existingDatasetFingerprint: FlightDatasetFingerprint(
                recordSnapshots: [FlightRecordBackupDTO(record: oldA)]
            )
        )

        _ = try BackupService.apply(plan, to: context, targetProfileID: profileA)
        let rows = try context.fetch(FetchDescriptor<FlightRecord>())
        XCTAssertEqual(rows.first { $0.ownerProfileID == profileA }?.flightNumber, "NEWA")
        XCTAssertEqual(rows.first { $0.ownerProfileID == profileB }?.flightNumber, "KEEPB")
    }

    @MainActor
    func testBackgroundSnapshotUsesSelectedExistingTargetNotCurrentPage() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        insert(profile(profileA, "当前甲", order: 0, color: "blue"), into: context)
        insert(profile(profileB, "目标乙", order: 1, color: "orange"), into: context)
        let current = record(id: uuid(70), owner: profileA, number: "AONLY")
        let target = record(id: uuid(71), owner: profileB, number: "DUP1")
        context.insert(current)
        context.insert(target)
        try context.save()

        let snapshot = try await BackupDatasetSnapshot.load(from: container)

        XCTAssertEqual(
            snapshot.records(forExistingProfileID: profileB).map(\.id),
            [target.id]
        )
        XCTAssertEqual(snapshot.recordCount(forExistingProfileID: profileB), 1)
        XCTAssertEqual(snapshot.occupiedRecordIDs, [current.id, target.id])

        let incoming = FlightRecordBackupDTO(
            record: record(id: uuid(72), owner: profileB, number: "DUP1")
        )
        let data = try BackupService.exportCurrent(
            profileSnapshot: UserProfileBackupDTO(profile: profile(
                profileB,
                "来源乙",
                order: 0,
                color: "orange"
            )),
            recordSnapshots: [incoming]
        )
        let merge = try BackupService.prepareJSONImport(
            data,
            existingRecordSnapshots: snapshot.records(
                forExistingProfileID: profileB
            ),
            targetProfileID: profileB,
            mode: .merge
        )
        let replace = try BackupService.prepareJSONImport(
            data,
            existingRecordSnapshots: snapshot.records(
                forExistingProfileID: profileB
            ),
            targetProfileID: profileB,
            mode: .replace
        )
        XCTAssertEqual(merge.report.duplicateCount, 1)
        XCTAssertTrue(merge.records.isEmpty)
        XCTAssertEqual(replace.records.count, 1)

        let csv = """
        \(BackupService.csvHeaders.joined(separator: ","))
        DUP1,2026-08-18,CA,Air China,PEK,2026-08-18 10:00,YUL,2026-08-18 08:00,,,,
        """
        let csvPlan = try BackupService.prepareCSVImport(
            Data(csv.utf8),
            repository: AirportRepository(airports: [
                Airport(
                    iata: "PEK",
                    icao: "ZBAA",
                    name: "Beijing",
                    city: "Beijing",
                    country: "China",
                    countryCode: "CN",
                    latitude: 40,
                    longitude: 116,
                    timeZoneID: "Asia/Shanghai"
                ),
                Airport(
                    iata: "YUL",
                    icao: "CYUL",
                    name: "Montreal",
                    city: "Montreal",
                    country: "Canada",
                    countryCode: "CA",
                    latitude: 45,
                    longitude: -73,
                    timeZoneID: "America/Toronto"
                ),
            ]),
            existingRecordSnapshots: snapshot.records(
                forExistingProfileID: profileB
            ),
            targetProfileID: profileB
        )
        XCTAssertEqual(csvPlan.report.duplicateCount, 1)
        XCTAssertTrue(csvPlan.records.isEmpty)
    }

    @MainActor
    func testFullRestoreReplacesAllProfilesAndRecordsPreservingIDs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlightLog-full-restore-\(UUID())")
        let storeURL = directory.appendingPathComponent("FlightLog.store")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema(versionedSchema: FlightLogSchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: FlightLogMigrationPlan.self,
            configurations: ModelConfiguration(
                "FullRestoreNoDefault",
                schema: schema,
                url: storeURL
            )
        )
        let context = container.mainContext
        let oldID = uuid(90)
        insert(profile(oldID, "旧用户", order: 0, color: "gray"), into: context)
        context.insert(record(id: uuid(91), owner: oldID, number: "OLD1"))
        try context.save()

        let sourceA = profile(profileA, "甲", order: 1, color: "blue")
        let sourceB = profile(profileB, "乙", order: 0, color: "orange")
        let sourceRecordA = record(id: uuid(1), owner: profileA, number: "CA1")
        let sourceRecordB = record(id: uuid(2), owner: profileB, number: "MU2")
        let data = try BackupService.exportAll(
            profiles: [sourceA, sourceB],
            records: [sourceRecordA, sourceRecordB]
        )
        let mapping = ProfileImportMappingPlan(entries: [
            .init(sourceProfileID: profileA, destination: .existing(profileA)),
            .init(sourceProfileID: profileB, destination: .existing(profileB)),
        ])
        let prepared = try BackupService.prepareJSONImport(
            data,
            existingRecordSnapshots: [
                FlightRecordBackupDTO(
                    record: record(id: uuid(91), owner: oldID, number: "OLD1")
                ),
            ],
            mappingPlan: mapping,
            mode: .fullRestore
        )
        let plan = PreparedFlightImport(
            records: prepared.records,
            report: prepared.report,
            mode: .fullRestore,
            mappingPlan: mapping,
            sourceSchemaVersion: 2,
            sourceScope: .fullArchive,
            sourceProfiles: prepared.sourceProfiles,
            existingDatasetFingerprint: FlightDatasetFingerprint(
                profiles: [
                    UserProfileBackupDTO(
                        profile: profile(
                            oldID,
                            "旧用户",
                            order: 0,
                            color: "gray"
                        )
                    ),
                ],
                recordSnapshots: [
                    FlightRecordBackupDTO(
                        record: record(
                            id: uuid(91),
                            owner: oldID,
                            number: "OLD1"
                        )
                    ),
                ]
            ),
            fingerprintScope: .fullDataset,
            occupiedRecordIDs: [uuid(91)]
        )

        _ = try BackupService.apply(plan, to: context)

        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        let records = try context.fetch(FetchDescriptor<FlightRecord>())
        XCTAssertEqual(Set(profiles.map(\.id)), [profileA, profileB])
        XCTAssertEqual(Set(records.map(\.id)), [uuid(1), uuid(2)])
        XCTAssertEqual(Set(records.compactMap(\.ownerProfileID)), [profileA, profileB])

        let reopened = try PersistenceController(storeURL: storeURL)
        let reopenedProfiles = try reopened.container.mainContext.fetch(
            FetchDescriptor<UserProfile>()
        )
        let reopenedRecords = try reopened.container.mainContext.fetch(
            FetchDescriptor<FlightRecord>()
        )
        XCTAssertEqual(Set(reopenedProfiles.map(\.id)), [profileA, profileB])
        XCTAssertFalse(
            reopenedProfiles.contains { $0.id == UserProfileDefaults.id }
        )
        XCTAssertEqual(Set(reopenedRecords.map(\.id)), [uuid(1), uuid(2)])
    }

    @MainActor
    func testProfileChangeMakesMappedPlanStaleWithoutWriting() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let local = profile(profileA, "甲", order: 0, color: "blue")
        insert(local, into: context)
        try context.save()
        let incoming = FlightRecordBackupDTO(
            record: record(id: uuid(1), owner: profileB, number: "NEW1")
        )
        let plan = PreparedFlightImport(
            records: [incoming],
            report: FlightImportReport(format: .json, successCount: 1),
            mode: .merge,
            mappingPlan: ProfileImportMappingPlan(entries: [
                .init(sourceProfileID: profileB, destination: .existing(profileA)),
            ]),
            sourceSchemaVersion: 2,
            sourceScope: .singleProfile,
            sourceProfiles: [
                UserProfileBackupDTO(
                    id: profileB,
                    displayName: "来源",
                    createdAt: Date(timeIntervalSince1970: 1),
                    sortOrder: 0,
                    color: "orange"
                ),
            ],
            existingDatasetFingerprint: FlightDatasetFingerprint(
                profiles: [UserProfileBackupDTO(profile: local)],
                recordSnapshots: []
            )
        )
        local.displayName = "已改名"
        try context.save()

        XCTAssertThrowsError(try BackupService.apply(plan, to: context)) { error in
            XCTAssertEqual(error as? BackupServiceError, .staleImportPlan)
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<FlightRecord>()).isEmpty)
        XCTAssertEqual(plan.mappingPlan.localProfileID(for: profileB), profileA)
    }

    @MainActor
    func testConfirmationUsesUpdatedFirstAndAllMappingsWithoutCachedTarget()
        async throws
    {
        let container = try makeContainer()
        let context = container.mainContext
        let localC = uuid(30)
        for value in [
            profile(profileA, "甲", order: 0, color: "blue"),
            profile(profileB, "乙", order: 1, color: "orange"),
            profile(localC, "丙", order: 2, color: "green"),
        ] {
            insert(value, into: context)
        }
        try context.save()
        let sourceA = uuid(40)
        let sourceB = uuid(41)
        let sourceProfiles = [
            UserProfileBackupDTO(
                id: sourceA,
                displayName: "来源一",
                createdAt: Date(timeIntervalSince1970: 1),
                sortOrder: 0,
                color: "blue"
            ),
            UserProfileBackupDTO(
                id: sourceB,
                displayName: "来源二",
                createdAt: Date(timeIntervalSince1970: 2),
                sortOrder: 1,
                color: "orange"
            ),
        ]
        let sourceRows = [
            FlightRecordBackupDTO(
                record: record(id: uuid(42), owner: sourceA, number: "SRC1")
            ),
            FlightRecordBackupDTO(
                record: record(id: uuid(43), owner: sourceB, number: "SRC2")
            ),
        ]
        let data = try BackupService.encodeJSON(
            FlightBackupDTO(
                schemaVersion: 2,
                exportedAt: Date(timeIntervalSince1970: 3),
                scope: .fullArchive,
                profiles: sourceProfiles,
                records: sourceRows
            )
        )
        let initial = ProfileImportMappingPlan(entries: [
            .init(sourceProfileID: sourceA, destination: .existing(profileA)),
            .init(sourceProfileID: sourceB, destination: .existing(profileB)),
        ])
        let prepared = try BackupService.prepareJSONImport(
            data,
            existingRecordSnapshots: [],
            mappingPlan: initial,
            mode: .merge
        )
        XCTAssertThrowsError(
            try ImportConfirmationState.preparedJSON(
                sourceData: data,
                mode: .merge,
                preparation: prepared,
                existingRecordCount: 0,
                targetProfileID: profileA
            )
        )
        let state = try ImportConfirmationState.preparedJSON(
            sourceData: data,
            mode: .merge,
            preparation: prepared,
            existingRecordCount: 0
        )
        let changed = ProfileImportMappingPlan(entries: [
            .init(sourceProfileID: sourceA, destination: .existing(localC)),
            .init(sourceProfileID: sourceB, destination: .existing(profileA)),
        ])

        try await state.updateMapping(changed, in: context)
        guard case .applied = try state.confirm(in: context) else {
            XCTFail("updated mapping should apply")
            return
        }

        let rows = try context.fetch(FetchDescriptor<FlightRecord>())
        XCTAssertEqual(rows.first { $0.flightNumber == "SRC1" }?.ownerProfileID, localC)
        XCTAssertEqual(rows.first { $0.flightNumber == "SRC2" }?.ownerProfileID, profileA)
    }

    @MainActor
    func testFullRestoreReconfirmsForEveryFullDatasetMutationWithoutDeleting() throws {
        enum Mutation: CaseIterable {
            case addRecord
            case renameProfile
            case changeOwner
            case changeNotes
        }

        for mutation in Mutation.allCases {
            let container = try makeContainer()
            let context = container.mainContext
            let localA = profile(profileA, "保留甲", order: 0, color: "blue")
            let localB = profile(profileB, "保留乙", order: 1, color: "orange")
            insert(localA, into: context)
            insert(localB, into: context)
            let keep = record(id: uuid(50), owner: profileA, number: "KEEP")
            context.insert(keep)
            try context.save()

            let restoreProfile = profile(uuid(60), "恢复用户", order: 0, color: "green")
            let restoreRecord = record(
                id: uuid(61),
                owner: restoreProfile.id,
                number: "RESTORE"
            )
            let data = try BackupService.exportAll(
                profiles: [restoreProfile],
                records: [restoreRecord]
            )
            let mapping = ProfileImportMappingPlan(entries: [
                .init(
                    sourceProfileID: restoreProfile.id,
                    destination: .existing(restoreProfile.id)
                ),
            ])
            let preparedBase = try BackupService.prepareJSONImport(
                data,
                existingRecordSnapshots: [FlightRecordBackupDTO(record: keep)],
                mappingPlan: mapping,
                mode: .fullRestore
            )
            let prepared = PreparedFlightImport(
                records: preparedBase.records,
                report: preparedBase.report,
                mode: .fullRestore,
                mappingPlan: mapping,
                sourceSchemaVersion: 2,
                sourceScope: .fullArchive,
                sourceProfiles: preparedBase.sourceProfiles,
                existingDatasetFingerprint: FlightDatasetFingerprint(
                    profiles: [
                        UserProfileBackupDTO(profile: localA),
                        UserProfileBackupDTO(profile: localB),
                    ],
                    recordSnapshots: [FlightRecordBackupDTO(record: keep)]
                )
            )
            let state = try ImportConfirmationState.preparedJSON(
                sourceData: data,
                mode: .fullRestore,
                preparation: prepared,
                existingRecordCount: 1
            )

            switch mutation {
            case .addRecord:
                context.insert(
                    record(id: uuid(62), owner: profileB, number: "ADDED")
                )
            case .renameProfile:
                localA.displayName = "并发改名"
            case .changeOwner:
                keep.ownerProfileID = profileB
            case .changeNotes:
                keep.notes = "并发备注"
            }
            try context.save()

            XCTAssertEqual(
                try state.confirm(in: context),
                .requiresReconfirmation,
                "\(mutation)"
            )
            XCTAssertEqual(state.preparation.mappingPlan, mapping)
            XCTAssertTrue(
                try context.fetch(FetchDescriptor<UserProfile>())
                    .contains { $0.id == profileA }
            )
            XCTAssertTrue(
                try context.fetch(FetchDescriptor<FlightRecord>())
                    .contains { $0.flightNumber == "KEEP" }
            )
        }
    }

    @MainActor
    func testFullRestoreRequiresAtLeastOneProfileAndRollsBack() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insert(profile(profileA, "保留", order: 0, color: "blue"), into: context)
        context.insert(record(id: uuid(1), owner: profileA, number: "KEEP1"))
        try context.save()
        let invalid = PreparedFlightImport(
            records: [],
            report: FlightImportReport(format: .json),
            mode: .fullRestore,
            mappingPlan: ProfileImportMappingPlan(entries: []),
            sourceSchemaVersion: 2,
            sourceScope: .fullArchive,
            sourceProfiles: []
        )

        XCTAssertThrowsError(try BackupService.apply(invalid, to: context)) { error in
            XCTAssertEqual(error as? BackupServiceError, .fullRestoreRequiresProfile)
        }
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<UserProfile>()).map(\.displayName),
            ["保留"]
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<FlightRecord>()).map(\.flightNumber),
            ["KEEP1"]
        )
    }

    func testSettingsExposeThreeImportActionsAndDangerousFullRestoreCopy() {
        let archiveActions = SettingsPresentation.section(.dataArchive).actions
        XCTAssertTrue(archiveActions.contains(.exportCurrentProfile))
        XCTAssertTrue(archiveActions.contains(.exportAllProfiles))
        XCTAssertTrue(archiveActions.contains(.mergeArchive))
        XCTAssertTrue(archiveActions.contains(.replaceTargetArchive))
        XCTAssertTrue(archiveActions.contains(.fullRestoreArchive))
        XCTAssertEqual(SettingsAction.fullRestoreArchive.risk, .destructive)
        XCTAssertTrue(SettingsPresentation.fullRestoreConfirmation.warning.contains("所有用户"))
        XCTAssertTrue(SettingsPresentation.fullRestoreConfirmation.warning.contains("无法撤销"))
    }

    private func profile(
        _ id: UUID,
        _ name: String,
        order: Int,
        color: String
    ) -> UserProfile {
        UserProfile(
            id: id,
            displayName: name,
            createdAt: Date(timeIntervalSince1970: Double(order + 1)),
            sortOrder: order,
            comparisonColorRawValue: color
        )
    }

    private func record(id: UUID, owner: UUID, number: String) -> FlightRecord {
        let departure = Airport(
            iata: "PEK",
            icao: "ZBAA",
            name: "Beijing",
            city: "Beijing",
            country: "China",
            countryCode: "CN",
            latitude: 40,
            longitude: 116,
            timeZoneID: "Asia/Shanghai"
        )
        let arrival = Airport(
            iata: "YUL",
            icao: "CYUL",
            name: "Montreal",
            city: "Montreal",
            country: "Canada",
            countryCode: "CA",
            latitude: 45,
            longitude: -73,
            timeZoneID: "America/Toronto"
        )
        return FlightRecord(
            id: id,
            flightNumber: number,
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: Date(timeIntervalSince1970: 1_787_011_200),
            departureAirport: departure,
            arrivalAirport: arrival,
            departureDate: Date(timeIntervalSince1970: 1_787_040_000),
            arrivalDate: Date(timeIntervalSince1970: 1_787_076_000),
            ownerProfileID: owner,
            createdAt: Date(timeIntervalSince1970: 1_787_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_787_000_000)
        )
    }

    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: FlightLogSchemaV2.self),
            migrationPlan: FlightLogMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    private func insert(_ profile: UserProfile, into context: ModelContext) {
        context.insert(profile)
    }
}
