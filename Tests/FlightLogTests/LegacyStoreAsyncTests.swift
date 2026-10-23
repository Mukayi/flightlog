import Foundation
import XCTest
@testable import FlightLog

private final class CountingLegacyFileAccess:
    LegacyStoreFileAccess, @unchecked Sendable
{
    private let base = SystemLegacyStoreFileAccess()
    private let lock = NSLock()
    private(set) var fingerprintCallCount = 0
    var fingerprintDelay: TimeInterval = 0

    func metadata(for storeURL: URL) throws -> LegacyStoreMetadata {
        try base.metadata(for: storeURL)
    }

    func contentFingerprint(for storeURL: URL) throws -> String {
        lock.withLock {
            fingerprintCallCount += 1
        }
        if fingerprintDelay > 0 {
            Thread.sleep(forTimeInterval: fingerprintDelay)
        }
        return try base.contentFingerprint(for: storeURL)
    }
}

@MainActor
final class LegacyStoreAsyncTests: XCTestCase {
    func testMetadataHitNeverReadsStoreContentsAgain() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let access = CountingLegacyFileAccess()
        let coordinator = LegacyStoreInspectionCoordinator(fileAccess: access)

        _ = try await coordinator.inspect(fixture.configuration)
        XCTAssertEqual(access.fingerprintCallCount, 1)
        XCTAssertEqual(
            try LegacyStoreMigrationService.currentState(
                fixture.configuration
            )?.sourceFingerprint.count,
            64
        )

        _ = try await coordinator.inspect(fixture.configuration)
        XCTAssertEqual(access.fingerprintCallCount, 1)
    }

    func testSlowFingerprintDoesNotBlockMainActorHeartbeat() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let access = CountingLegacyFileAccess()
        access.fingerprintDelay = 0.4
        let coordinator = LegacyStoreInspectionCoordinator(fileAccess: access)
        let heartbeat = expectation(description: "MainActor remains responsive")

        let inspection = Task {
            try await coordinator.inspect(
                fixture.configuration,
                forceRetry: true
            )
        }
        Task { @MainActor in heartbeat.fulfill() }

        await fulfillment(of: [heartbeat], timeout: 0.1)
        _ = try await inspection.value
    }
}

@MainActor
private struct Fixture {
    let directory: URL
    let configuration: LegacyStoreMigrationConfiguration

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let source = directory.appendingPathComponent("default.store")
        _ = try PersistenceController(storeURL: source)
        configuration = LegacyStoreMigrationConfiguration(
            sourceStoreURL: source,
            backupDirectoryURL: directory.appendingPathComponent("backups"),
            markerURL: directory.appendingPathComponent("state.json")
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
