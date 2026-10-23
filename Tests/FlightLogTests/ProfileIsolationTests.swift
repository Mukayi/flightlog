import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import FlightLog

@MainActor
final class ProfileIsolationTests: XCTestCase {
    private let ownerA = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    private let ownerB = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!

    func testWriterAndPageConstructionCarryExplicitProfile() throws {
        let record = try FlightRecordWriter.makeRecord(
            from: draft(),
            repository: repository,
            ownerProfileID: ownerA
        )

        XCTAssertEqual(record.ownerProfileID, ownerA)
        _ = OverviewView(
            profileID: ownerA,
            onAddFlight: {},
            onOpenFlight: { _ in }
        )
        _ = FlightBrowserView(
            profileID: ownerA,
            repository: repository,
            commandState: AppCommandState()
        )
        _ = RouteMapView(profileID: ownerA)
        _ = StatisticsView(profileID: ownerA)
        _ = SettingsView(profileID: ownerA, repository: repository)
        _ = FlightEditorView(
            ownerProfileID: ownerA,
            repository: repository,
            record: nil
        )
    }

    func testDynamicPageQueriesOnlyExposeRequestedOwnerAndHideNilOwner() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(makeRecord(number: "A1", owner: ownerA))
        context.insert(makeRecord(number: "B1", owner: ownerB))
        context.insert(makeRecord(number: "NIL1", owner: nil))
        try context.save()

        XCTAssertEqual(
            try ProfileFlightQuery.records(profileID: ownerA, in: context)
                .map(\.flightNumber),
            ["A1"]
        )
        XCTAssertEqual(
            try ProfileFlightQuery.records(profileID: ownerB, in: context)
                .map(\.flightNumber),
            ["B1"]
        )
    }

    func testEditorRejectsCrossProfileEditWithoutSaving() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let existing = makeRecord(number: "A1", owner: ownerA)
        context.insert(existing)
        try context.save()
        var edited = FlightDraft(record: existing, repository: repository)
        edited.notes = "越权修改"

        XCTAssertThrowsError(
            try FlightEditorSaveService.save(
                draft: edited,
                editingID: existing.id,
                openedUpdatedAt: existing.updatedAt,
                ownerProfileID: ownerB,
                repository: repository,
                in: context,
                allowDuplicate: false
            )
        ) {
            XCTAssertEqual($0 as? FlightEditorSaveError, .ownerMismatch)
        }
        let persisted = try XCTUnwrap(
            context.fetch(FetchDescriptor<FlightRecord>()).first
        )
        XCTAssertNotEqual(persisted.notes, "越权修改")
        XCTAssertEqual(persisted.ownerProfileID, ownerA)
    }

    func testDuplicateIsScopedToOwnerButStillDetectedWithinOwner() {
        let existing = makeRecord(number: "CA123", owner: ownerA)

        XCTAssertEqual(
            FlightDuplicateDetector.matches(
                draft(),
                in: [existing],
                ownerProfileID: ownerA
            ).count,
            1
        )
        XCTAssertTrue(
            FlightDuplicateDetector.matches(
                draft(),
                in: [existing],
                ownerProfileID: ownerB
            ).isEmpty
        )
    }

    func testSampleGenerationIsIndependentPerOwner() throws {
        let first = try SampleDataGenerator.generate(
            count: 2,
            repository: try AirportRepository(),
            existingRecords: [],
            ownerProfileID: ownerA,
            occupiedRecordIDs: []
        )
        let secondOwner = try SampleDataGenerator.generate(
            count: 2,
            repository: try AirportRepository(),
            existingRecords: first.records,
            ownerProfileID: ownerB,
            occupiedRecordIDs: Set(first.records.map(\.id))
        )
        let repeated = try SampleDataGenerator.generate(
            count: 2,
            repository: try AirportRepository(),
            existingRecords: first.records + secondOwner.records,
            ownerProfileID: ownerA,
            occupiedRecordIDs: Set(
                (first.records + secondOwner.records).map(\.id)
            )
        )

        XCTAssertEqual(first.records.count, 2)
        XCTAssertEqual(secondOwner.records.count, 2)
        XCTAssertTrue(first.records.allSatisfy { $0.ownerProfileID == ownerA })
        XCTAssertTrue(secondOwner.records.allSatisfy { $0.ownerProfileID == ownerB })
        XCTAssertTrue(Set(first.records.map(\.id)).isDisjoint(with: secondOwner.records.map(\.id)))
        XCTAssertTrue(repeated.records.isEmpty)
    }

    func testSampleIDsStableRemapAroundOccupiedTemplateID() throws {
        let repository = try AirportRepository()
        let baseline = try SampleDataGenerator.generate(
            repository: repository,
            existingRecords: [],
            ownerProfileID: ownerA,
            occupiedRecordIDs: []
        )
        let occupiedTemplateID = try XCTUnwrap(baseline.records.first?.id)

        let first = try SampleDataGenerator.generate(
            repository: repository,
            existingRecords: [],
            ownerProfileID: ownerA,
            occupiedRecordIDs: [occupiedTemplateID]
        )
        let second = try SampleDataGenerator.generate(
            repository: repository,
            existingRecords: [],
            ownerProfileID: ownerA,
            occupiedRecordIDs: [occupiedTemplateID]
        )

        XCTAssertEqual(first.records.count, SampleDataGenerator.defaultCount)
        XCTAssertEqual(first.records.map(\.id), second.records.map(\.id))
        XCTAssertFalse(first.records.map(\.id).contains(occupiedTemplateID))
        XCTAssertEqual(Set(first.records.map(\.id)).count, first.records.count)
    }

    func testTwoProfilesGenerateFullSamplesAndRemainIdempotent() throws {
        let repository = try AirportRepository()
        let first = try SampleDataGenerator.generate(
            repository: repository,
            existingRecords: [],
            ownerProfileID: ownerA,
            occupiedRecordIDs: []
        )
        let second = try SampleDataGenerator.generate(
            repository: repository,
            existingRecords: first.records,
            ownerProfileID: ownerB,
            occupiedRecordIDs: Set(first.records.map(\.id))
        )
        let all = first.records + second.records
        let repeated = try SampleDataGenerator.generate(
            repository: repository,
            existingRecords: all,
            ownerProfileID: ownerB,
            occupiedRecordIDs: Set(all.map(\.id))
        )

        XCTAssertEqual(first.records.count, 24)
        XCTAssertEqual(second.records.count, 24)
        XCTAssertEqual(Set(all.map(\.id)).count, 48)
        XCTAssertTrue(repeated.records.isEmpty)
    }

    func testSamplePreparationServiceFetchesAllOccupiedIDs() throws {
        let container = try makeContainer()
        let repository = try AirportRepository()
        let baseline = try SampleDataGenerator.generate(
            count: 1,
            repository: repository,
            existingRecords: [],
            ownerProfileID: ownerA,
            occupiedRecordIDs: []
        )
        let occupied = try XCTUnwrap(baseline.records.first)
        occupied.ownerProfileID = ownerB
        container.mainContext.insert(occupied)
        try container.mainContext.save()

        let result = try SampleDataGenerationService(
            container: container
        ).prepare(
            count: 1,
            repository: repository,
            ownerProfileID: ownerA
        )

        XCTAssertEqual(result.records.count, 1)
        XCTAssertNotEqual(result.records[0].id, occupied.id)
        XCTAssertEqual(result.records[0].ownerProfileID, ownerA)
    }

    func testBackupApplyTargetsCurrentOwnerAndReplaceLeavesOthers() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertProfile(ownerA, name: "甲", in: context)
        insertProfile(ownerB, name: "乙", in: context)
        let oldA = makeRecord(number: "OLDA", owner: ownerA)
        let oldB = makeRecord(number: "OLDB", owner: ownerB)
        context.insert(oldA)
        context.insert(oldB)
        try context.save()

        let imported = FlightRecordBackupDTO(record: makeRecord(number: "NEWA", owner: nil))
        let preparation = PreparedFlightImport(
            records: [imported],
            report: FlightImportReport(format: .json, successCount: 1),
            mode: .replace,
            targetProfileID: ownerA,
            existingDatasetFingerprint: FlightDatasetFingerprint(records: [oldA])
        )
        try BackupService.apply(
            preparation,
            to: context,
            targetProfileID: ownerA
        )

        let records = try context.fetch(FetchDescriptor<FlightRecord>())
        XCTAssertEqual(records.filter { $0.ownerProfileID == ownerA }.map(\.flightNumber), ["NEWA"])
        XCTAssertEqual(records.filter { $0.ownerProfileID == ownerB }.map(\.flightNumber), ["OLDB"])
    }

    func testClearCurrentLeavesOtherOwnerAndClearAllPreservesProfiles() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(UserProfile(
            id: ownerA,
            displayName: "甲",
            sortOrder: 0,
            comparisonColorRawValue: "blue"
        ))
        context.insert(UserProfile(
            id: ownerB,
            displayName: "乙",
            sortOrder: 1,
            comparisonColorRawValue: "orange"
        ))
        context.insert(makeRecord(number: "A1", owner: ownerA))
        context.insert(makeRecord(number: "B1", owner: ownerB))
        try context.save()

        let service = FlightDataClearService(container: container)
        let currentPlan = try service.prepareCurrent(profileID: ownerA)
        XCTAssertEqual(currentPlan.recordCount, 1)
        try service.clearCurrent(currentPlan)
        XCTAssertEqual(try ProfileFlightQuery.records(profileID: ownerB, in: context).count, 1)

        let allPlan = try service.prepareAll()
        try service.clearAll(allPlan)
        XCTAssertTrue(try context.fetch(FetchDescriptor<FlightRecord>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserProfile>()).count, 2)
    }

    func testClearPlanRejectsConcurrentDatasetChange() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(makeRecord(number: "A1", owner: ownerA))
        try context.save()
        let service = FlightDataClearService(container: container)
        let stalePlan = try service.prepareCurrent(profileID: ownerA)

        let concurrent = ModelContext(container)
        concurrent.insert(makeRecord(number: "A2", owner: ownerA))
        try concurrent.save()

        XCTAssertThrowsError(try service.clearCurrent(stalePlan)) {
            XCTAssertEqual($0 as? FlightDataClearError, .staleConfirmation)
        }
        XCTAssertEqual(try ProfileFlightQuery.records(profileID: ownerA, in: context).count, 2)
    }

    func testLegacyImportAssignsTargetOwner() throws {
        let container = try makeContainer()
        insertProfile(ownerB, name: "乙", in: container.mainContext)
        try container.mainContext.save()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let candidate = LegacyFlightImportCandidate(
            sourceStoreURL: directory.appendingPathComponent("default.store"),
            backupStoreURL: directory.appendingPathComponent("backup.store"),
            sourceFingerprint: "fixture",
            records: [
                FlightRecordBackupDTO(
                    record: makeRecord(number: "LEGACY1", owner: nil)
                ),
            ],
            normalizedFlightDateCount: 0,
            sourceMetadata: LegacyStoreMetadata(files: [])
        )
        let configuration = LegacyStoreMigrationConfiguration(
            sourceStoreURL: candidate.sourceStoreURL,
            backupDirectoryURL: directory,
            markerURL: directory.appendingPathComponent("marker.json")
        )

        _ = try LegacyStoreMigrationService.importCandidate(
            candidate,
            to: container.mainContext,
            targetProfileID: ownerB,
            configuration: configuration
        )

        let imported = try XCTUnwrap(
            ProfileFlightQuery.records(
                profileID: ownerB,
                in: container.mainContext
            ).first
        )
        XCTAssertEqual(imported.flightNumber, "LEGACY1")
        XCTAssertEqual(imported.ownerProfileID, ownerB)
    }

    func testImportReconfirmationRetainsTargetProfile() throws {
        let container = try makeContainer()
        let context = container.mainContext
        insertProfile(ownerB, name: "乙", in: context)
        let existing = makeRecord(number: "EXISTING-B", owner: ownerB)
        context.insert(existing)
        try context.save()
        let source = try BackupService.exportJSON(
            recordSnapshots: [
                FlightRecordBackupDTO(
                    record: makeRecord(number: "CA999", owner: ownerA)
                ),
            ]
        )
        let state = try ImportConfirmationState.prepareJSON(
            sourceData: source,
            mode: .merge,
            existingRecords: [existing],
            targetProfileID: ownerB
        )
        context.insert(makeRecord(number: "CONCURRENT-B", owner: ownerB))
        try context.save()

        XCTAssertEqual(
            try state.confirm(in: context),
            .requiresReconfirmation
        )
        XCTAssertEqual(state.targetProfileID, ownerB)
        guard case .applied = try state.confirm(in: context) else {
            XCTFail("second confirmation should apply")
            return
        }
        let verificationContext = ModelContext(container)
        let ownerBRecords = try ProfileFlightQuery.records(
            profileID: ownerB,
            in: verificationContext
        )
        XCTAssertTrue(ownerBRecords.contains { $0.flightNumber == "CA999" })
        XCTAssertTrue(ownerBRecords.allSatisfy { $0.ownerProfileID == ownerB })
    }

    func testPreparedJSONAndCSVPersistTargetProfile() throws {
        let record = makeRecord(number: "CA777", owner: ownerA)
        let json = try BackupService.exportJSON(records: [record])
        let csv = try BackupService.exportCSV(records: [record])

        let jsonPlan = try BackupService.prepareJSONImport(
            json,
            existingRecords: [],
            targetProfileID: ownerA,
            mode: .merge
        )
        let csvPlan = try BackupService.prepareCSVImport(
            csv,
            repository: repository,
            existingRecords: [],
            targetProfileID: ownerA
        )

        XCTAssertEqual(jsonPlan.targetProfileID, ownerA)
        XCTAssertEqual(csvPlan.targetProfileID, ownerA)
        XCTAssertEqual(jsonPlan, jsonPlan)
    }

    func testApplyRejectsTargetDifferentFromPreparedPlan() throws {
        let container = try makeContainer()
        insertProfile(ownerA, name: "甲", in: container.mainContext)
        insertProfile(ownerB, name: "乙", in: container.mainContext)
        try container.mainContext.save()
        let plan = try importPlan(targetProfileID: ownerA)

        XCTAssertThrowsError(
            try BackupService.apply(
                plan,
                to: container.mainContext,
                targetProfileID: ownerB
            )
        ) {
            XCTAssertEqual(
                $0 as? BackupServiceError,
                .targetProfileMismatch(expected: ownerA, actual: ownerB)
            )
        }
        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<FlightRecord>())
                .isEmpty
        )
    }

    func testConfirmationRejectsPlanForDifferentTarget() throws {
        let plan = try importPlan(targetProfileID: ownerA)

        XCTAssertThrowsError(
            try ImportConfirmationState.preparedJSON(
                sourceData: Data(),
                mode: .merge,
                preparation: plan,
                existingRecordCount: 0,
                targetProfileID: ownerB
            )
        ) {
            XCTAssertEqual(
                $0 as? BackupServiceError,
                .targetProfileMismatch(expected: ownerA, actual: ownerB)
            )
        }
    }

    func testCSVApplyAfterTargetDeletionWritesNothing() throws {
        let container = try makeContainer()
        insertProfile(ownerA, name: "甲", in: container.mainContext)
        try container.mainContext.save()
        let source = try BackupService.exportCSV(
            records: [makeRecord(number: "CA778", owner: ownerA)]
        )
        let plan = try BackupService.prepareCSVImport(
            source,
            repository: repository,
            existingRecords: [],
            targetProfileID: ownerA
        )
        let profile = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<UserProfile>()).first
        )
        container.mainContext.delete(profile)
        try container.mainContext.save()

        XCTAssertThrowsError(
            try BackupService.apply(
                plan,
                to: container.mainContext,
                targetProfileID: ownerA
            )
        ) {
            XCTAssertEqual(
                $0 as? BackupServiceError,
                .targetProfileMissing(ownerA)
            )
        }
        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<FlightRecord>())
                .isEmpty
        )
    }

    func testJSONConfirmationAfterTargetDeletionWritesNothing() async throws {
        let container = try makeContainer()
        insertProfile(ownerA, name: "甲", in: container.mainContext)
        try container.mainContext.save()
        let source = try BackupService.exportJSON(
            records: [makeRecord(number: "CA779", owner: ownerA)]
        )
        let state = try ImportConfirmationState.prepareJSON(
            sourceData: source,
            mode: .merge,
            existingRecords: [],
            targetProfileID: ownerA
        )
        let profile = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<UserProfile>()).first
        )
        container.mainContext.delete(profile)
        try container.mainContext.save()

        do {
            _ = try await state.confirmAsync(in: container.mainContext)
            XCTFail("deleted target profile must reject confirmation")
        } catch {
            XCTAssertEqual(
                error as? BackupServiceError,
                .targetProfileMissing(ownerA)
            )
        }
        XCTAssertTrue(
            try container.mainContext.fetch(FetchDescriptor<FlightRecord>())
                .isEmpty
        )
    }

    func testLateImportResultRejectsProfileSwitchAndDeletion() throws {
        let container = try makeContainer()
        insertProfile(ownerA, name: "甲", in: container.mainContext)
        insertProfile(ownerB, name: "乙", in: container.mainContext)
        try container.mainContext.save()

        XCTAssertFalse(
            try ImportTargetGuard.isAcceptable(
                capturedTarget: ownerA,
                activeProfileID: ownerB,
                in: container
            )
        )
        let profileA = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<UserProfile>())
                .first { $0.id == ownerA }
        )
        container.mainContext.delete(profileA)
        try container.mainContext.save()
        XCTAssertFalse(
            try ImportTargetGuard.isAcceptable(
                capturedTarget: ownerA,
                activeProfileID: ownerA,
                in: container
            )
        )
    }

    func testVisualMatrixRendersFivePagesForTwoProfiles() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(makeRecord(number: "ONLY-A", owner: ownerA))
        context.insert(makeRecord(number: "ONLY-B-1", owner: ownerB))
        context.insert(makeRecord(number: "ONLY-B-2", owner: ownerB))
        try context.save()

        var differingPageCount = 0
        for makeView in pageFactories() {
            let first = try render(
                makeView(ownerA).modelContainer(container)
            )
            let second = try render(
                makeView(ownerB).modelContainer(container)
            )
            XCTAssertGreaterThan(first.count, 5_000)
            XCTAssertGreaterThan(second.count, 5_000)
            if first != second {
                differingPageCount += 1
            }
        }
        XCTAssertGreaterThanOrEqual(differingPageCount, 3)
    }

    func testMountedContentSwitchesSessionQueryAndResetIdentity() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(UserProfile(
            id: ownerA,
            displayName: "甲用户",
            sortOrder: 0,
            comparisonColorRawValue: "blue"
        ))
        context.insert(UserProfile(
            id: ownerB,
            displayName: "乙用户",
            sortOrder: 1,
            comparisonColorRawValue: "orange"
        ))
        context.insert(makeRecord(number: "ONLY-A", owner: ownerA))
        context.insert(makeRecord(number: "ONLY-B-1", owner: ownerB))
        context.insert(makeRecord(number: "ONLY-B-2", owner: ownerB))
        try context.save()

        let defaults = UserDefaults(
            suiteName: "ProfileIsolationMount-\(UUID().uuidString)"
        )!
        let session = UserSession(defaults: defaults)
        session.activate(ownerA)
        let commands = AppCommandState()
        var snapshots: [ProfileScopeMountSnapshot] = []
        ProfileScopeMountProbe.observer = { snapshots.append($0) }
        defer { ProfileScopeMountProbe.observer = nil }
        let hosting = NSHostingView(
            rootView: AnyView(
                ContentView(
                    repository: repository,
                    commandState: commands
                )
                .modelContainer(container)
                .environmentObject(session)
            )
        )
        hosting.frame = NSRect(x: 0, y: 0, width: 1_080, height: 720)
        settle(hosting)

        let firstOverview = try XCTUnwrap(
            snapshots.last {
                $0.section == .overview && $0.profileID == ownerA
            }
        )
        XCTAssertEqual(firstOverview.recordCount, 1)
        XCTAssertEqual(firstOverview.holderDisplayName, "甲用户")

        session.activate(ownerB)
        settle(hosting)
        let secondOverview = try XCTUnwrap(
            snapshots.last {
                $0.section == .overview && $0.profileID == ownerB
            }
        )
        XCTAssertEqual(secondOverview.recordCount, 2)
        XCTAssertEqual(secondOverview.holderDisplayName, "乙用户")
        XCTAssertNotEqual(firstOverview.mountID, secondOverview.mountID)

        for section in AppSection.allCases where section != .comparison {
            commands.navigate(to: section)
            session.activate(ownerA)
            settle(hosting)
            let first = try XCTUnwrap(
                snapshots.last {
                    $0.section == section && $0.profileID == ownerA
                }
            )
            XCTAssertEqual(first.recordCount, 1)

            session.activate(ownerB)
            settle(hosting)
            let second = try XCTUnwrap(
                snapshots.last {
                    $0.section == section && $0.profileID == ownerB
                }
            )
            XCTAssertEqual(second.recordCount, 2)
            XCTAssertNotEqual(
                first.mountID,
                second.mountID,
                "\(section) did not remount"
            )
        }

        XCTAssertEqual(
            ProfileSwitchResetPolicy.flightBrowserState,
            [.selection, .search, .filter, .editor]
        )
        XCTAssertEqual(
            ProfileSwitchResetPolicy.routeMapState,
            [.selection, .filter, .hover]
        )
    }

    func testProfilePredicateFetchesOneThousandRecordsWithoutCrossOwnerLeak() throws {
        let container = try makeContainer()
        let context = container.mainContext
        for index in 0..<1_000 {
            context.insert(
                makeRecord(
                    number: "P\(index)",
                    owner: index.isMultiple(of: 2) ? ownerA : ownerB
                )
            )
        }
        try context.save()

        measure {
            do {
                let records = try ProfileFlightQuery.records(
                    profileID: ownerA,
                    in: context
                )
                XCTAssertEqual(records.count, 500)
                XCTAssertTrue(records.allSatisfy { $0.ownerProfileID == ownerA })
            } catch {
                XCTFail("profile fetch failed: \(error)")
            }
        }
    }

    func testFinalMultiUserProductionServiceWorkflowPersistsAcrossReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FlightLog-multi-user-e2e-\(UUID())")
        let storeURL = directory.appendingPathComponent("FlightLog.store")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let controller = try PersistenceController(storeURL: storeURL)
        let service = ProfileManagementService(container: controller.container)
        let profileA = UserProfileDefaults.id
        _ = try service.rename(profileID: profileA, displayName: "甲用户")
        let profileB = try service.create(
            displayName: "乙用户",
            comparisonColorRawValue: "orange"
        ).profileID
        let profileC = try service.create(
            displayName: "新导入档案",
            comparisonColorRawValue: "green"
        ).profileID
        let longName = String(repeating: "长", count: 30)
        let profileD = try service.create(
            displayName: longName,
            comparisonColorRawValue: "purple"
        ).profileID

        let suiteName = "FlightLog.multi-user-e2e.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = UserSession(defaults: defaults)
        session.activate(profileA)
        XCTAssertEqual(session.activeProfileID, profileA)
        session.activate(profileB)
        XCTAssertEqual(session.activeProfileID, profileB)

        let writeContext = ModelContext(controller.container)
        writeContext.insert(makeRecord(number: "SHARED1", owner: profileA))
        writeContext.insert(makeRecord(number: "REVERSE-A", owner: profileA))
        writeContext.insert(makeRecord(number: "SHARED1", owner: profileB))
        writeContext.insert(makeReverseRecord(number: "REVERSE-B", owner: profileB))
        try writeContext.save()

        let exportContext = ModelContext(controller.container)
        let profiles = try exportContext.fetch(FetchDescriptor<UserProfile>())
        let allRecords = try exportContext.fetch(FetchDescriptor<FlightRecord>())
        let a = try XCTUnwrap(profiles.first { $0.id == profileA })
        let aRecords = allRecords.filter { $0.ownerProfileID == profileA }
        let currentData = try BackupService.exportCurrent(
            profile: a,
            records: aRecords
        )
        let fullData = try BackupService.exportAll(
            profiles: profiles,
            records: allRecords
        )
        let currentEnvelope = try BackupService.decodeJSON(currentData)
        let fullEnvelope = try BackupService.decodeJSON(fullData)
        XCTAssertEqual(currentEnvelope.scope, .singleProfile)
        XCTAssertEqual(currentEnvelope.records.count, 2)
        XCTAssertEqual(fullEnvelope.scope, .fullArchive)
        XCTAssertEqual(fullEnvelope.profiles.count, 4)
        XCTAssertEqual(fullEnvelope.records.count, 4)

        let clearService = FlightDataClearService(container: controller.container)
        let clearPlan = try clearService.prepareCurrent(profileID: profileA)
        XCTAssertEqual(clearPlan.recordCount, 2)
        try clearService.clearCurrent(clearPlan)
        XCTAssertTrue(
            try ProfileFlightQuery.records(
                profileID: profileA,
                in: ModelContext(controller.container)
            ).isEmpty
        )

        let importPlan = try BackupService.prepareJSONImport(
            currentData,
            existingRecordSnapshots: [],
            targetProfileID: profileC,
            mode: .merge
        )
        let importReport = try BackupService.apply(
            importPlan,
            to: ModelContext(controller.container),
            targetProfileID: profileC
        )
        XCTAssertEqual(importReport.successCount, 2)

        let comparisonContext = ModelContext(controller.container)
        let bRecords = try ProfileFlightQuery.records(
            profileID: profileB,
            in: comparisonContext
        )
        let cRecords = try ProfileFlightQuery.records(
            profileID: profileC,
            in: comparisonContext
        )
        let two = try ComparisonService().compare([
            ProfileDataset(
                profileID: profileB,
                name: "乙用户",
                color: .orange,
                records: bRecords
            ),
            ProfileDataset(
                profileID: profileC,
                name: "新导入档案",
                color: .green,
                records: cRecords
            ),
        ])
        XCTAssertEqual(two.sharedFlights.count, 1)
        XCTAssertEqual(two.sharedRoutes.count, 1)

        let four = try ComparisonService().compare([
            ProfileDataset(
                profileID: profileA,
                name: "甲用户",
                color: .blue,
                records: []
            ),
            ProfileDataset(
                profileID: profileB,
                name: "乙用户",
                color: .orange,
                records: bRecords
            ),
            ProfileDataset(
                profileID: profileC,
                name: "新导入档案",
                color: .green,
                records: cRecords
            ),
            ProfileDataset(
                profileID: profileD,
                name: longName,
                color: .purple,
                records: []
            ),
        ])
        XCTAssertEqual(four.profiles.count, 4)
        XCTAssertTrue(four.sharedFlights.isEmpty)
        XCTAssertTrue(four.sharedRoutes.isEmpty)

        let deletion = try service.delete(
            profileID: profileB,
            strategy: .transferFlights(targetProfileID: profileC)
        )
        XCTAssertEqual(deletion.deletedProfileID, profileB)
        XCTAssertEqual(deletion.fallbackProfileID, profileA)

        let reopened = try PersistenceController(storeURL: storeURL)
        let verifyContext = ModelContext(reopened.container)
        let persistedProfiles = try verifyContext.fetch(
            FetchDescriptor<UserProfile>()
        )
        let persistedRecords = try verifyContext.fetch(
            FetchDescriptor<FlightRecord>()
        )
        XCTAssertEqual(persistedProfiles.count, 3)
        XCTAssertFalse(persistedProfiles.contains { $0.id == profileB })
        XCTAssertTrue(persistedProfiles.contains { $0.displayName == longName })
        XCTAssertEqual(persistedRecords.count, 4)
        XCTAssertTrue(
            persistedRecords.allSatisfy { $0.ownerProfileID == profileC }
        )
        XCTAssertTrue(
            try ProfileFlightQuery.records(
                profileID: profileD,
                in: verifyContext
            ).isEmpty
        )
        print(
            "MULTI_USER_E2E currentProfiles=4 currentRecords=4 "
                + "singleExport=2 fullExportProfiles=4 fullExportRecords=4 "
                + "comparison2SharedFlights=\(two.sharedFlights.count) "
                + "comparison2SharedRoutes=\(two.sharedRoutes.count) "
                + "comparison4SharedFlights=\(four.sharedFlights.count) "
                + "comparison4SharedRoutes=\(four.sharedRoutes.count) "
                + "reopenProfiles=\(persistedProfiles.count) "
                + "reopenRecords=\(persistedRecords.count)"
        )
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: FlightLogSchemaV2.self),
            migrationPlan: FlightLogMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func insertProfile(
        _ id: UUID,
        name: String,
        in context: ModelContext
    ) {
        context.insert(
            UserProfile(
                id: id,
                displayName: name,
                sortOrder: 0,
                comparisonColorRawValue: "blue"
            )
        )
    }

    private func importPlan(targetProfileID: UUID) throws
        -> PreparedFlightImport
    {
        let source = try BackupService.exportJSON(
            records: [makeRecord(number: "CA780", owner: targetProfileID)]
        )
        return try BackupService.prepareJSONImport(
            source,
            existingRecords: [],
            targetProfileID: targetProfileID,
            mode: .merge
        )
    }

    private func pageFactories() -> [(UUID) -> AnyView] {
        [
            { id in AnyView(OverviewView(
                profileID: id,
                onAddFlight: {},
                onOpenFlight: { _ in }
            )) },
            { [repository] id in AnyView(FlightBrowserView(
                profileID: id,
                repository: repository,
                commandState: AppCommandState()
            )) },
            { id in AnyView(RouteMapView(profileID: id)) },
            { id in AnyView(StatisticsView(profileID: id)) },
            { [repository, ownerA] id in AnyView(SettingsView(
                profileID: id,
                profileDisplayName: id == ownerA ? "甲" : "乙",
                repository: repository
            )) },
        ]
    }

    private func render<V: View>(_ view: V) throws -> Data {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 720, height: 520)
        hosting.layoutSubtreeIfNeeded()
        guard
            let bitmap = hosting.bitmapImageRepForCachingDisplay(
                in: hosting.bounds
            )
        else {
            throw CocoaError(.coderInvalidValue)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func settle(_ hosting: NSHostingView<AnyView>) {
        for _ in 0..<4 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            hosting.layoutSubtreeIfNeeded()
        }
    }


    private var repository: AirportRepository {
        AirportRepository(airports: [departure, arrival])
    }

    private var departure: Airport {
        Airport(
            iata: "PEK",
            icao: "ZBAA",
            name: "北京",
            city: "北京",
            country: "中国",
            countryCode: "CN",
            latitude: 40,
            longitude: 116,
            timeZoneID: "Asia/Shanghai"
        )
    }

    private var arrival: Airport {
        Airport(
            iata: "YUL",
            icao: "CYUL",
            name: "蒙特利尔",
            city: "蒙特利尔",
            country: "加拿大",
            countryCode: "CA",
            latitude: 45,
            longitude: -73,
            timeZoneID: "America/Toronto"
        )
    }

    private func draft() -> FlightDraft {
        FlightDraft(
            flightDate: date(2026, 8, 18, 0),
            flightNumber: "CA123",
            airlineCode: "CA",
            airlineName: "Air China",
            departureAirport: departure,
            arrivalAirport: arrival,
            departureLocalDate: date(2026, 8, 18, 10),
            arrivalLocalDate: date(2026, 8, 18, 8)
        )
    }

    private func makeRecord(number: String, owner: UUID?) -> FlightRecord {
        let record = FlightRecord(
            flightNumber: number,
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: date(2026, 8, 18, 0),
            departureAirport: departure,
            arrivalAirport: arrival,
            departureDate: date(2026, 8, 18, 2),
            arrivalDate: date(2026, 8, 18, 12),
            ownerProfileID: owner ?? UserProfileDefaults.id
        )
        if owner == nil {
            record.ownerProfileID = nil
        }
        return record
    }

    private func makeReverseRecord(number: String, owner: UUID) -> FlightRecord {
        FlightRecord(
            flightNumber: number,
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: date(2026, 8, 18, 0),
            departureAirport: arrival,
            arrivalAirport: departure,
            departureDate: date(2026, 8, 18, 2),
            arrivalDate: date(2026, 8, 18, 12),
            ownerProfileID: owner
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour)
        )!
    }
}
