import Foundation
import SwiftData
import XCTest
@testable import FlightLog

private enum LegacyV0Fixture {
    @Model
    final class FlightRecord {
        @Attribute(.unique) var id: UUID
        var flightNumber: String
        var airlineCode: String
        var airlineName: String
        var flightDate: Date
        var departureAirportIATA: String
        var departureDate: Date
        var departureTimeZoneID: String
        var departureAirportName: String
        var departureCity: String
        var departureCountry: String
        var departureCountryCode: String
        var departureLatitude: Double
        var departureLongitude: Double
        var arrivalAirportIATA: String
        var arrivalDate: Date
        var arrivalTimeZoneID: String
        var arrivalAirportName: String
        var arrivalCity: String
        var arrivalCountry: String
        var arrivalCountryCode: String
        var arrivalLatitude: Double
        var arrivalLongitude: Double
        var aircraftType: String?
        var cabinClass: String?
        var seat: String?
        var notes: String?
        var createdAt: Date
        var updatedAt: Date

        init() {
            let departure = Date(timeIntervalSince1970: 1_793_516_400)
            id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
            flightNumber = "V0TEST1"
            airlineCode = "TS"
            airlineName = "Test Air"
            flightDate = Date(timeIntervalSince1970: 1_793_491_200)
            departureAirportIATA = "LAX"
            departureDate = departure
            departureTimeZoneID = "America/Los_Angeles"
            departureAirportName = "Los Angeles"
            departureCity = "Los Angeles"
            departureCountry = "United States"
            departureCountryCode = "US"
            departureLatitude = 33.9416
            departureLongitude = -118.4085
            arrivalAirportIATA = "YUL"
            arrivalDate = departure.addingTimeInterval(18_000)
            arrivalTimeZoneID = "America/Toronto"
            arrivalAirportName = "Montreal"
            arrivalCity = "Montreal"
            arrivalCountry = "Canada"
            arrivalCountryCode = "CA"
            arrivalLatitude = 45.4706
            arrivalLongitude = -73.7408
            createdAt = departure
            updatedAt = departure
        }
    }
}

@MainActor
final class LegacyV0MigrationTests: XCTestCase {
    func testProductionInspectionSafelyHandlesRealV0DiskSchema() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("default.store")
        let schema = Schema([LegacyV0Fixture.FlightRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                "LegacyV0",
                schema: schema,
                url: source
            )
        )
        container.mainContext.insert(LegacyV0Fixture.FlightRecord())
        try container.mainContext.save()
        let configuration = LegacyStoreMigrationConfiguration(
            sourceStoreURL: source,
            backupDirectoryURL: directory.appendingPathComponent("backups"),
            markerURL: directory.appendingPathComponent("state.json")
        )

        let candidate = try LegacyStoreMigrationService.inspect(configuration)
        let state = try XCTUnwrap(
            LegacyStoreMigrationService.currentState(configuration)
        )

        XCTAssertTrue(
            (candidate?.records.map(\.flightNumber) == ["V0TEST1"]
                && state.status == .deferred)
                || (candidate == nil && state.status == .incompatible)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: configuration.backupDirectoryURL,
                includingPropertiesForKeys: nil
            ).count,
            1
        )
        XCTAssertNil(try LegacyStoreMigrationService.inspect(configuration))
    }
}
