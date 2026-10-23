import AppKit
import Foundation
import SwiftData
import SwiftUI
import XCTest
@testable import FlightLog

@MainActor
final class ProfileSessionTests: XCTestCase {
    func testSessionPersistsActivationInInjectedDefaults() {
        let defaults = makeDefaults()
        let profileID = uuid(2)
        let session = UserSession(defaults: defaults)

        session.activate(profileID)

        XCTAssertEqual(UserSession(defaults: defaults).activeProfileID, profileID)
    }

    func testResolveReplacesInvalidIDWithDeterministicDefaultAndPersistsIt() {
        let defaults = makeDefaults()
        defaults.set(uuid(99).uuidString, forKey: UserSession.activeProfileDefaultsKey)
        let other = makeProfile(id: uuid(2), name: "工作", sortOrder: -1)
        let defaultProfile = makeProfile(
            id: UserProfileDefaults.id,
            name: UserProfileDefaults.displayName,
            sortOrder: 20
        )
        let session = UserSession(defaults: defaults)

        let resolved = session.resolve(profiles: [defaultProfile, other])

        XCTAssertEqual(resolved?.id, UserProfileDefaults.id)
        XCTAssertEqual(session.activeProfileID, UserProfileDefaults.id)
        XCTAssertEqual(
            defaults.string(forKey: UserSession.activeProfileDefaultsKey),
            UserProfileDefaults.id.uuidString
        )
    }

    func testResolveWithoutDefaultUsesStableSortOrderFallback() {
        let session = UserSession(defaults: makeDefaults())

        let resolved = session.resolve(
            profiles: [
                makeProfile(id: uuid(3), name: "三", sortOrder: 5),
                makeProfile(id: uuid(2), name: "二", sortOrder: 1),
            ]
        )

        XCTAssertEqual(resolved?.id, uuid(2))
        XCTAssertEqual(session.activeProfileID, uuid(2))
    }

    func testCreateReturnsValueSnapshotAndKeepsStableSortOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(makeProfile(id: uuid(1), name: "Alice", sortOrder: 4))
        context.insert(makeProfile(id: uuid(2), name: "Bob", sortOrder: 9))
        try context.save()
        let service = ProfileManagementService(container: container)

        let created = try service.create(
            displayName: "  Carol \n Zhang ",
            comparisonColorRawValue: "not-a-color"
        )

        XCTAssertEqual(created.displayName, "Carol Zhang")
        XCTAssertEqual(created.sortOrder, 10)
        XCTAssertEqual(
            created.comparisonColorRawValue,
            ProfileComparisonColor.fallback.rawValue
        )
        XCTAssertThrowsError(
            try service.create(
                displayName: "ｃＡＲＯＬ　ＺＨＡＮＧ",
                comparisonColorRawValue: "blue"
            )
        ) { error in
            XCTAssertEqual(error as? UserProfileNameValidationError, .duplicate)
        }
    }

    func testRenameRefetchesByIDAndExcludesSelf() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = makeProfile(id: uuid(1), name: "Alice", sortOrder: 0)
        let other = makeProfile(id: uuid(2), name: "Bob", sortOrder: 1)
        context.insert(first)
        context.insert(other)
        try context.save()
        let service = ProfileManagementService(container: container)

        let result = try service.rename(
            profileID: first.id,
            displayName: "  ALICE "
        )

        XCTAssertEqual(result.profileID, first.id)
        XCTAssertEqual(result.displayName, "ALICE")
        XCTAssertThrowsError(
            try service.rename(profileID: first.id, displayName: "bob")
        ) { error in
            XCTAssertEqual(error as? UserProfileNameValidationError, .duplicate)
        }
    }

    func testColorUpdateUsesFallbackForUnknownRawValue() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profile = makeProfile(id: uuid(1), name: "Alice", sortOrder: 0)
        context.insert(profile)
        try context.save()
        let service = ProfileManagementService(container: container)

        let result = try service.setColor(
            profileID: profile.id,
            comparisonColorRawValue: "unknown"
        )

        XCTAssertEqual(
            result.comparisonColorRawValue,
            ProfileComparisonColor.fallback.rawValue
        )
        XCTAssertTrue((4...6).contains(ProfileComparisonColor.allCases.count))
    }

    func testDeleteRejectsOnlyRemainingProfile() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profile = makeProfile(id: uuid(1), name: "Alice", sortOrder: 0)
        context.insert(profile)
        try context.save()

        XCTAssertThrowsError(
            try ProfileManagementService(container: container).delete(
                profileID: profile.id,
                strategy: .deleteFlights
            )
        ) { error in
            XCTAssertEqual(error as? ProfileManagementError, .cannotDeleteOnlyProfile)
        }
    }

    func testDeleteFlightsCascadesAllOwnedFlights() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let source = makeProfile(id: uuid(1), name: "Alice", sortOrder: 0)
        let survivor = makeProfile(id: uuid(2), name: "Bob", sortOrder: 1)
        context.insert(source)
        context.insert(survivor)
        context.insert(makeRecord(id: uuid(10), ownerProfileID: source.id))
        context.insert(makeRecord(id: uuid(11), ownerProfileID: survivor.id))
        try context.save()

        let result = try ProfileManagementService(container: container).delete(
            profileID: source.id,
            strategy: .deleteFlights
        )

        let verification = ModelContext(container)
        XCTAssertEqual(
            try verification.fetch(FetchDescriptor<FlightRecord>()).map(\.id),
            [uuid(11)]
        )
        XCTAssertEqual(result.deletedProfileID, source.id)
        XCTAssertEqual(result.fallbackProfileID, survivor.id)
    }

    func testDeleteTransfersFlightsAndRejectsSelfOrMissingTarget() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let source = makeProfile(id: uuid(1), name: "Alice", sortOrder: 0)
        let target = makeProfile(id: uuid(2), name: "Bob", sortOrder: 1)
        context.insert(source)
        context.insert(target)
        context.insert(makeRecord(id: uuid(10), ownerProfileID: source.id))
        try context.save()
        let service = ProfileManagementService(container: container)

        XCTAssertThrowsError(
            try service.delete(
                profileID: source.id,
                strategy: .transferFlights(targetProfileID: source.id)
            )
        )
        XCTAssertThrowsError(
            try service.delete(
                profileID: source.id,
                strategy: .transferFlights(targetProfileID: uuid(99))
            )
        )

        try service.delete(
            profileID: source.id,
            strategy: .transferFlights(targetProfileID: target.id)
        )

        let records = try ModelContext(container).fetch(
            FetchDescriptor<FlightRecord>()
        )
        XCTAssertEqual(records.map(\.ownerProfileID), [target.id])
    }

    func testFailedTransferPreservesMainContextUnsavedWorkAndStore() throws {
        let container = try makeContainer()
        let mainContext = ModelContext(container)
        let source = makeProfile(id: uuid(1), name: "Alice", sortOrder: 0)
        let target = makeProfile(id: uuid(2), name: "Bob", sortOrder: 1)
        mainContext.insert(source)
        mainContext.insert(target)
        mainContext.insert(makeRecord(id: uuid(10), ownerProfileID: source.id))
        try mainContext.save()
        let unsaved = makeProfile(id: uuid(3), name: "未保存", sortOrder: 2)
        mainContext.insert(unsaved)
        let service = ProfileManagementService(
            container: container,
            save: { _ in throw TestSaveError.failed }
        )

        XCTAssertThrowsError(
            try service.delete(
                profileID: source.id,
                strategy: .transferFlights(targetProfileID: target.id)
            )
        )

        XCTAssertTrue(mainContext.hasChanges)
        XCTAssertTrue(
            try mainContext.fetch(FetchDescriptor<UserProfile>())
                .contains { $0.id == unsaved.id }
        )
        let verification = ModelContext(container)
        XCTAssertEqual(
            Set(try verification.fetch(FetchDescriptor<UserProfile>()).map(\.id)),
            [source.id, target.id]
        )
        XCTAssertEqual(
            try verification.fetch(FetchDescriptor<FlightRecord>())
                .map(\.ownerProfileID),
            [source.id]
        )
    }

    func testFailedCascadeLeavesSourceStoreUnchanged() throws {
        let container = try makeContainer()
        let setup = ModelContext(container)
        let source = makeProfile(id: uuid(1), name: "Alice", sortOrder: 0)
        let target = makeProfile(id: uuid(2), name: "Bob", sortOrder: 1)
        setup.insert(source)
        setup.insert(target)
        setup.insert(makeRecord(id: uuid(10), ownerProfileID: source.id))
        try setup.save()
        let service = ProfileManagementService(
            container: container,
            save: { _ in throw TestSaveError.failed }
        )

        XCTAssertThrowsError(
            try service.delete(
                profileID: source.id,
                strategy: .deleteFlights
            )
        )

        let verification = ModelContext(container)
        XCTAssertEqual(
            Set(try verification.fetch(FetchDescriptor<UserProfile>()).map(\.id)),
            [source.id, target.id]
        )
        XCTAssertEqual(
            try verification.fetch(FetchDescriptor<FlightRecord>()).map(\.id),
            [uuid(10)]
        )
    }

    func testIndependentContextSaveRefreshesProductionQueryAndRefetch() async throws {
        let container = try makeContainer()
        let mainContext = ModelContext(container)
        _ = try mainContext.fetch(FetchDescriptor<UserProfile>())
        let observation = ProfileQueryObservation()
        let host = NSHostingView(
            rootView: ProfileQueryProbe(observation: observation)
                .modelContainer(container)
        )
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        host.layoutSubtreeIfNeeded()
        host.display()
        let service = ProfileManagementService(container: container)

        let created = try service.create(
            displayName: "生产刷新",
            comparisonColorRawValue: "green"
        )

        let appeared = try await waitUntil(attempts: 500) {
            host.layoutSubtreeIfNeeded()
            let refetched = try mainContext.fetch(
                FetchDescriptor<UserProfile>()
            )
            return observation.profileIDs.contains(created.profileID)
                && refetched.contains { $0.id == created.profileID }
        }
        XCTAssertTrue(appeared)
        withExtendedLifetime(host) {}
    }

    func testMutationGateIgnoresRapidSecondSubmissionAndReportsOneError() async {
        let gate = ProfileMutationGate()
        var executionCount = 0
        var errorCount = 0

        let firstAccepted = gate.submit {
            executionCount += 1
            await Task.yield()
            throw TestSaveError.failed
        } onError: { _ in
            errorCount += 1
        }
        let secondAccepted = gate.submit {
            executionCount += 1
            throw TestSaveError.failed
        } onError: { _ in
            errorCount += 1
        }

        XCTAssertTrue(firstAccepted)
        XCTAssertFalse(secondAccepted)
        XCTAssertTrue(gate.isSubmitting)
        while gate.isSubmitting {
            await Task.yield()
        }
        XCTAssertEqual(executionCount, 1)
        XCTAssertEqual(errorCount, 1)
    }

    func testProfileManagementAccessibilitySemanticsAreExplicit() {
        XCTAssertEqual(
            ProfileManagementAccessibility.createHint,
            "创建后切换到新用户"
        )
        XCTAssertEqual(
            ProfileManagementAccessibility.colorLabel(profileName: "工作"),
            "工作，显示颜色"
        )
        XCTAssertEqual(
            ProfileManagementAccessibility.currentProfileLabel(profileName: "工作"),
            "工作，当前用户"
        )
        XCTAssertEqual(
            ProfileManagementAccessibility.deleteHint(canDelete: true),
            "选择删除航班或迁移航班，并再次确认"
        )
        XCTAssertEqual(
            ProfileManagementAccessibility.deletionStrategyValues,
            ["连同航班删除", "迁移到其他用户"]
        )
        XCTAssertEqual(
            ProfileComparisonColor.allCases.map(\.localizedName),
            ["蓝色", "橙色", "绿色", "紫色", "粉色"]
        )
    }

    private enum TestSaveError: Error {
        case failed
    }

    private func waitUntil(
        attempts: Int = 100,
        condition: @escaping @MainActor () throws -> Bool
    ) async throws -> Bool {
        for _ in 0..<attempts {
            if try condition() {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ProfileSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: FlightLogSchemaV2.self)
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                "ProfileSessionTests.\(UUID().uuidString)",
                schema: schema,
                isStoredInMemoryOnly: true
            )
        )
    }

    private func makeProfile(
        id: UUID,
        name: String,
        sortOrder: Int
    ) -> UserProfile {
        UserProfile(
            id: id,
            displayName: name,
            createdAt: Date(timeIntervalSince1970: TimeInterval(sortOrder + 100)),
            sortOrder: sortOrder,
            comparisonColorRawValue: "blue"
        )
    }

    private func makeRecord(id: UUID, ownerProfileID: UUID) -> FlightRecord {
        FlightRecord(
            id: id,
            flightNumber: "TEST1",
            airlineCode: "TS",
            airlineName: "测试航空",
            flightDate: Date(timeIntervalSince1970: 1_700_000_000),
            departureAirport: Airport(
                iata: "PVG",
                icao: "ZSPD",
                name: "上海浦东国际机场",
                city: "上海",
                country: "中国",
                countryCode: "CN",
                latitude: 31.1443,
                longitude: 121.8083,
                timeZoneID: "Asia/Shanghai"
            ),
            arrivalAirport: Airport(
                iata: "PEK",
                icao: "ZBAA",
                name: "北京首都国际机场",
                city: "北京",
                country: "中国",
                countryCode: "CN",
                latitude: 40.0799,
                longitude: 116.6031,
                timeZoneID: "Asia/Shanghai"
            ),
            departureDate: Date(timeIntervalSince1970: 1_700_003_600),
            arrivalDate: Date(timeIntervalSince1970: 1_700_007_200),
            ownerProfileID: ownerProfileID
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

@MainActor
private final class ProfileQueryObservation: ObservableObject {
    @Published var profileIDs: [UUID] = []
}

private struct ProfileQueryProbe: View {
    @Query(sort: \UserProfile.sortOrder)
    private var profiles: [UserProfile]
    @ObservedObject var observation: ProfileQueryObservation

    var body: some View {
        Color.clear
            .onAppear {
                observation.profileIDs = profiles.map(\.id)
            }
            .onChange(of: profiles.map(\.id)) {
                observation.profileIDs = profiles.map(\.id)
            }
    }
}
