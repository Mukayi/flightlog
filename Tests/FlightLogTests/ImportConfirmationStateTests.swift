import Foundation
import SwiftData
import XCTest
@testable import FlightLog

@MainActor
final class ImportConfirmationStateTests: XCTestCase {
    func testMergeStaleRefreshesProductionPlanAndRequiresSecondConfirmation() throws {
        let container = try makeContainer()
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
        let validJSON = try BackupService.exportJSON(
            records: [incoming],
            exportedAt: Date(timeIntervalSince1970: 1_787_100_000)
        )
        let state = try ImportConfirmationState.prepareJSON(
            sourceData: validJSON,
            mode: .merge,
            existingRecords: [existing],
            targetProfileID: UserProfileDefaults.id
        )
        let concurrent = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            flightNumber: "ADDED1"
        )
        context.insert(concurrent)
        try context.save()

        let firstOutcome = try state.confirm(in: context)

        XCTAssertEqual(firstOutcome, .requiresReconfirmation)
        XCTAssertEqual(state.confirmationRevision, 1)
        XCTAssertEqual(state.notice, "数据已变化，请再次确认。")
        XCTAssertTrue(state.message.contains("2"))
        XCTAssertEqual(
            Set(try fetchedFlightNumbers(context)),
            Set(["KEEP1", "ADDED1"])
        )

        let secondOutcome = try state.confirm(in: context)

        guard case .applied(let report) = secondOutcome else {
            XCTFail("第二次明确确认后应执行更新后的 merge 计划")
            return
        }
        XCTAssertEqual(report.successCount, 1)
        XCTAssertEqual(
            Set(try fetchedFlightNumbers(context)),
            Set(["KEEP1", "ADDED1", "NEW1"])
        )
    }

    func testReplaceStaleKeepsConcurrentRecordUntilSecondConfirmation() throws {
        let container = try makeContainer()
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
        let validJSON = try BackupService.exportJSON(
            records: [replacement],
            exportedAt: Date(timeIntervalSince1970: 1_787_100_000)
        )
        let state = try ImportConfirmationState.prepareJSON(
            sourceData: validJSON,
            mode: .replace,
            existingRecords: [existing],
            targetProfileID: UserProfileDefaults.id
        )
        let concurrent = makeRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            flightNumber: "ADDED1"
        )
        context.insert(concurrent)
        try context.save()

        let firstOutcome = try state.confirm(in: context)

        XCTAssertEqual(firstOutcome, .requiresReconfirmation)
        XCTAssertEqual(state.confirmationRevision, 1)
        XCTAssertEqual(state.notice, "数据已变化，请再次确认。")
        XCTAssertTrue(state.message.contains("2"))
        XCTAssertTrue(state.message.contains("1"))
        XCTAssertEqual(
            Set(try fetchedFlightNumbers(context)),
            Set(["KEEP1", "ADDED1"])
        )

        let secondOutcome = try state.confirm(in: context)

        guard case .applied(let report) = secondOutcome else {
            XCTFail("第二次明确确认后应执行更新后的 replace 计划")
            return
        }
        XCTAssertEqual(report.successCount, 1)
        XCTAssertEqual(try fetchedFlightNumbers(context), ["RESTORE1"])
    }

    func testCancellingMergeOrReplaceClosesStateWithoutWritingOrDeleting() throws {
        for mode in [BackupRestoreMode.merge, .replace] {
            let container = try makeContainer()
            let context = container.mainContext
            let existing = makeRecord(
                id: UUID(
                    uuidString: "00000000-0000-0000-0000-000000000001"
                )!,
                flightNumber: "KEEP1"
            )
            context.insert(existing)
            try context.save()
            let incoming = makeRecord(
                id: UUID(
                    uuidString: "00000000-0000-0000-0000-000000000002"
                )!,
                flightNumber: "NEW1"
            )
            let validJSON = try BackupService.exportJSON(
                records: [incoming],
                exportedAt: Date(timeIntervalSince1970: 1_787_100_000)
            )
            var presentedState: ImportConfirmationState? =
                try ImportConfirmationState.prepareJSON(
                    sourceData: validJSON,
                    mode: mode,
                    existingRecords: [existing],
                    targetProfileID: UserProfileDefaults.id
                )

            XCTAssertNotNil(presentedState)
            XCTAssertFalse(context.hasChanges)

            presentedState = nil

            XCTAssertNil(presentedState)
            XCTAssertFalse(context.hasChanges)
            XCTAssertEqual(try fetchedFlightNumbers(context), ["KEEP1"])
        }
    }

    private func makeContainer() throws -> ModelContainer {
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

    private func fetchedFlightNumbers(
        _ context: ModelContext
    ) throws -> [String] {
        try context.fetch(
            FetchDescriptor<FlightRecord>(
                sortBy: [SortDescriptor(\.flightNumber)]
            )
        )
        .map(\.flightNumber)
    }

    private func makeRecord(
        id: UUID,
        flightNumber: String
    ) -> FlightRecord {
        let departure = Airport(
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
        let arrival = Airport(
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
        return FlightRecord(
            id: id,
            flightNumber: flightNumber,
            airlineCode: "TS",
            airlineName: "Test Airline",
            flightDate: Date(timeIntervalSince1970: 1_787_011_200),
            departureAirport: departure,
            arrivalAirport: arrival,
            departureDate: Date(timeIntervalSince1970: 1_787_040_000),
            arrivalDate: Date(timeIntervalSince1970: 1_787_076_000),
            ownerProfileID: UserProfileDefaults.id,
            createdAt: Date(timeIntervalSince1970: 1_787_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_787_000_000)
        )
    }
}
