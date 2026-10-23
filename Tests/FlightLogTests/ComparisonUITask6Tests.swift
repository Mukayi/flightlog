import AppKit
import Foundation
import SwiftData
import SwiftUI
import XCTest
@testable import FlightLog

final class ComparisonUITask6Tests: XCTestCase {
    private let alice = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let bob = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let carol = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    private let dave = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!

    func testSelectionDefaultsToActiveAndNextProfileAndReconcilesTwoToFour() {
        let ordered = [alice, bob, carol, dave]
        XCTAssertEqual(
            ComparisonSelection.reconciled(
                saved: [],
                available: ordered,
                active: bob
            ),
            [bob, carol]
        )
        XCTAssertEqual(
            ComparisonSelection.reconciled(
                saved: [dave, alice, bob, carol, UUID()],
                available: ordered,
                active: bob
            ),
            [dave, alice, bob, carol]
        )
        XCTAssertEqual(
            ComparisonSelection.reconciled(
                saved: [dave],
                available: [alice, bob, carol],
                active: alice
            ),
            [alice, bob]
        )
    }

    func testSelectionPreservesSurvivorsThenFillsWithoutResettingOrder() {
        let deleted = UUID()
        XCTAssertEqual(
            ComparisonSelection.reconciled(
                saved: [alice, deleted, carol],
                available: [alice, bob, carol, dave],
                active: bob
            ),
            [alice, carol]
        )
        XCTAssertEqual(
            ComparisonSelection.reconciled(
                saved: [carol],
                available: [alice, bob, carol, dave],
                active: bob
            ),
            [carol, bob]
        )
        XCTAssertEqual(
            ComparisonSelection.reconciled(
                saved: [carol],
                available: [alice, carol, dave],
                active: bob
            ),
            [carol, alice]
        )
        XCTAssertEqual(
            ComparisonSelection.reconciled(
                saved: [
                    UUID(), dave, alice, bob, carol, dave, UUID(), UUID(),
                ],
                available: [alice, bob, carol, dave],
                active: carol
            ),
            [dave, alice, bob, carol]
        )
    }

    func testSelectionAllowsSingleProfileOnlyWhenFewerThanTwoExist() {
        XCTAssertEqual(
            ComparisonSelection.reconciled(
                saved: [alice],
                available: [alice],
                active: alice
            ),
            [alice]
        )
        XCTAssertTrue(
            ComparisonSelection.reconciled(
                saved: [],
                available: [],
                active: nil
            ).isEmpty
        )
    }

    func testPresentationUsesStableNamesMetricsAndMissingValues() {
        XCTAssertEqual(
            ComparisonUIPresentation.displayName(
                String(repeating: "同行者", count: 12),
                maximumCharacters: 12
            ),
            "同行者同行者同行者同行…"
        )
        XCTAssertEqual(
            ComparisonUIPresentation.metricValue(
                metric: .flightCount,
                flightCount: 3,
                distanceKilometers: nil,
                durationMinutes: nil,
                distanceUnit: .kilometers
            ),
            3
        )
        XCTAssertNil(
            ComparisonUIPresentation.metricValue(
                metric: .distance,
                flightCount: 3,
                distanceKilometers: nil,
                durationMinutes: nil,
                distanceUnit: .kilometers
            )
        )
        XCTAssertEqual(
            ComparisonUIPresentation.tooltip(
                year: 2026,
                profileName: "Alice",
                metric: .duration,
                value: 2.5,
                distanceUnit: .kilometers
            ),
            "2026 年 · Alice · 2.5 小时"
        )
        XCTAssertFalse(ComparisonUIPresentation.emptyIntersectionCopy.contains("评分"))
    }

    func testMapPolicyPutsSharedRoutesAboveOwnerRoutesAndKeepsLegendOrder() {
        let unique = ComparisonMapRoutePresentation(
            id: "HND-PEK",
            participantIDs: [alice],
            selectedProfileCount: 2
        )
        let shared = ComparisonMapRoutePresentation(
            id: "PEK-YUL",
            participantIDs: [alice, bob],
            selectedProfileCount: 2
        )
        XCTAssertEqual(
            ComparisonMapPolicy.ordered([shared, unique]).map(\.id),
            ["HND-PEK", "PEK-YUL"]
        )
        XCTAssertEqual(
            ComparisonMapPolicy.role(for: unique),
            .exclusive(profileID: alice)
        )
        XCTAssertEqual(
            ComparisonMapPolicy.role(for: shared),
            .sharedByAll(selectedProfileCount: 2)
        )
        XCTAssertEqual(
            ComparisonMapPolicy.legend(
                profiles: [
                    .init(profileID: bob, profileName: "Bob", color: .orange),
                    .init(profileID: alice, profileName: "Alice", color: .blue),
                ]
            ).map(\.profileID),
            [bob, alice]
        )
    }

    func testRouteParticipationDistinguishesExclusivePartialAndAll() {
        XCTAssertEqual(
            ComparisonRouteParticipation.classify(
                participantIDs: [alice],
                selectedProfileCount: 4
            ),
            .exclusive(profileID: alice)
        )
        XCTAssertEqual(
            ComparisonRouteParticipation.classify(
                participantIDs: [alice, carol],
                selectedProfileCount: 4
            ),
            .sharedBySome(participantCount: 2, selectedProfileCount: 4)
        )
        XCTAssertEqual(
            ComparisonRouteParticipation.classify(
                participantIDs: [alice, bob, carol, dave],
                selectedProfileCount: 4
            ),
            .sharedByAll(selectedProfileCount: 4)
        )
        XCTAssertEqual(
            ComparisonRouteParticipation.sharedBySome(
                participantCount: 3,
                selectedProfileCount: 4
            ).label,
            "部分同行航线 3/4"
        )
        XCTAssertEqual(
            ComparisonRouteParticipation.sharedBySome(
                participantCount: 2,
                selectedProfileCount: 4
            ).zOrder,
            50
        )
    }

    func testComparisonMapSplitsPacificRoutesAtExactAntimeridian() throws {
        let routes = [
            (
                id: "PEK-SFO",
                start: FlightCoordinate(latitude: 40.0801, longitude: 116.5846),
                end: FlightCoordinate(latitude: 37.6213, longitude: -122.379),
                expectedCount: 2
            ),
            (
                id: "HND-LAX",
                start: FlightCoordinate(latitude: 35.5494, longitude: 139.7798),
                end: FlightCoordinate(latitude: 33.9416, longitude: -118.4085),
                expectedCount: 2
            ),
            (
                id: "PEK-HND",
                start: FlightCoordinate(latitude: 40.0801, longitude: 116.5846),
                end: FlightCoordinate(latitude: 35.5494, longitude: 139.7798),
                expectedCount: 1
            ),
        ]

        for route in routes {
            let segments = ComparisonMapGeometry.segments(
                routeID: route.id,
                from: route.start,
                to: route.end,
                segmentCount: 96
            )
            XCTAssertEqual(segments.count, route.expectedCount, route.id)
            XCTAssertEqual(Set(segments.map(\.id)).count, segments.count)
            XCTAssertTrue(segments.allSatisfy {
                zip($0.coordinates, $0.coordinates.dropFirst()).allSatisfy {
                    abs($0.longitude - $1.longitude) <= 180
                }
            })
            if route.expectedCount == 2 {
                let firstEnd = try XCTUnwrap(segments[0].coordinates.last)
                let secondStart = try XCTUnwrap(segments[1].coordinates.first)
                XCTAssertEqual(abs(firstEnd.longitude), 180, accuracy: 0.000_001)
                XCTAssertEqual(abs(secondStart.longitude), 180, accuracy: 0.000_001)
                XCTAssertEqual(firstEnd.latitude, secondStart.latitude, accuracy: 0.000_001)
                XCTAssertEqual(firstEnd.longitude, -secondStart.longitude)
            }
        }
    }

    func testComparisonMapViewportUsesMinimumLongitudeArcAndSafeSpan() {
        let pek = FlightCoordinate(latitude: 40.0801, longitude: 116.5846)
        let sfo = FlightCoordinate(latitude: 37.6213, longitude: -122.379)
        let hnd = FlightCoordinate(latitude: 35.5494, longitude: 139.7798)
        let lax = FlightCoordinate(latitude: 33.9416, longitude: -118.4085)

        for coordinates in [[pek, sfo], [hnd, lax]] {
            let viewport = ComparisonMapGeometry.viewport(
                fitting: coordinates
            )
            XCTAssertGreaterThan(abs(viewport.center.longitude), 150)
            XCTAssertLessThan(viewport.longitudeDelta, 330)
            XCTAssertGreaterThan(viewport.longitudeDelta, 0)
            XCTAssertLessThan(viewport.latitudeDelta, 180)
        }

        let local = ComparisonMapGeometry.viewport(fitting: [pek, hnd])
        XCTAssertLessThan(abs(local.center.longitude), 180)
        XCTAssertLessThan(local.longitudeDelta, 60)
        XCTAssertLessThan(local.longitudeDelta, 330)

        let fallback = ComparisonMapGeometry.viewport(fitting: [])
        XCTAssertLessThan(fallback.longitudeDelta, 360)
        XCTAssertLessThanOrEqual(fallback.longitudeDelta, 330)
    }

    func testComparisonMap1080LayoutKeepsHeaderAndContentInside720Height() {
        let frames = ComparisonMapLayout.frames(
            for: CGSize(width: 1_080, height: 720)
        )
        XCTAssertGreaterThanOrEqual(frames.header.minY, 8)
        XCTAssertGreaterThan(frames.header.height, 0)
        XCTAssertGreaterThanOrEqual(frames.legend.minY, frames.header.maxY)
        XCTAssertGreaterThanOrEqual(frames.routeList.minY, frames.legend.maxY)
        XCTAssertGreaterThanOrEqual(frames.map.minY, frames.routeList.maxY)
        XCTAssertLessThanOrEqual(frames.map.maxY, 712)
        XCTAssertLessThanOrEqual(frames.detail.maxY, 712)
        XCTAssertGreaterThan(frames.map.height, 400)
        XCTAssertGreaterThan(frames.detail.width, 300)
    }

    func testCompactToolbarFramesKeepEveryControlInside720Points() {
        XCTAssertEqual(
            ComparisonToolbarLayout.mode(forWidth: 720),
            .compact
        )
        let frames = ComparisonToolbarLayout.controlFrames(forWidth: 720)
        XCTAssertEqual(
            frames.map(\.control),
            [.profiles, .year, .metric, .distanceUnit, .limit]
        )
        XCTAssertTrue(frames.allSatisfy {
            $0.frame.minX >= 0
                && $0.frame.maxX <= 720
                && $0.frame.minY >= 0
                && $0.frame.maxY <= ComparisonToolbarLayout.compactHeight
        })
    }

    func testSnapshotAndComparisonResultAreSendable() throws {
        let snapshot = ComparisonRecordSnapshot(
            id: UUID(),
            ownerProfileID: alice,
            flightNumber: "CA123",
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: Date(timeIntervalSince1970: 1_700_000_000),
            departure: .init(
                iata: "PEK", name: "Capital", city: "Beijing",
                country: "China", countryCode: "CN",
                latitude: 40, longitude: 116, timeZoneID: "Asia/Shanghai"
            ),
            arrival: .init(
                iata: "YUL", name: "Trudeau", city: "Montreal",
                country: "Canada", countryCode: "CA",
                latitude: 45, longitude: -73, timeZoneID: "America/Toronto"
            ),
            departureDate: Date(timeIntervalSince1970: 1_700_003_600),
            arrivalDate: Date(timeIntervalSince1970: 1_700_010_800),
            departureLocalDateTime: "2023-11-15T07:13:20",
            arrivalLocalDateTime: "2023-11-14T21:13:20"
        )
        assertSendable(snapshot)
        let result = try ComparisonService().compareSnapshots([
            .init(profileID: alice, name: "Alice", color: .blue, records: [snapshot]),
            .init(profileID: bob, name: "Bob", color: .orange, records: []),
        ])
        assertSendable(result)
        XCTAssertEqual(result.profiles.map(\.profileID), [alice, bob])
        XCTAssertEqual(result.profiles.map(\.statistics.totalFlightCount), [1, 0])
    }

    func testInvalidationFingerprintCoversProfileAndEveryBackedUpRecordField() {
        let fixedUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let firstProfile = UserProfile(
            id: alice,
            displayName: "Alice",
            createdAt: Date(timeIntervalSince1970: 100),
            sortOrder: 0,
            comparisonColorRawValue: "blue"
        )
        let renamedProfile = UserProfile(
            id: alice,
            displayName: "Alice Restored",
            createdAt: firstProfile.createdAt,
            sortOrder: 0,
            comparisonColorRawValue: "blue"
        )
        let first = fingerprintRecord(
            id: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!,
            owner: alice,
            arrivalIATA: "YUL",
            arrivalName: "Montreal",
            updatedAt: fixedUpdatedAt
        )
        let restored = fingerprintRecord(
            id: first.id,
            owner: alice,
            arrivalIATA: "SFO",
            arrivalName: "San Francisco",
            updatedAt: fixedUpdatedAt
        )
        restored.notes = "full restore changed notes without changing updatedAt"

        let baseline = ComparisonInvalidation.fingerprint(
            profiles: [firstProfile],
            records: [first]
        )
        let routeChanged = ComparisonInvalidation.fingerprint(
            profiles: [firstProfile],
            records: [restored]
        )
        let nameChanged = ComparisonInvalidation.fingerprint(
            profiles: [renamedProfile],
            records: [first]
        )

        XCTAssertNotEqual(baseline, routeChanged)
        XCTAssertNotEqual(baseline, nameChanged)
        XCTAssertEqual(
            baseline,
            ComparisonInvalidation.fingerprint(
                profiles: [firstProfile],
                records: [first]
            )
        )
    }

    @MainActor
    func testMountedComparisonRecomputesWhenRestoreKeepsIdentityButChangesFields()
        throws
    {
        let container = try ModelContainer(
            for: Schema(versionedSchema: FlightLogSchemaV2.self),
            migrationPlan: FlightLogMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let aliceProfile = UserProfile(
            id: alice,
            displayName: "Alice",
            sortOrder: 0,
            comparisonColorRawValue: "blue"
        )
        let bobProfile = UserProfile(
            id: bob,
            displayName: "Bob",
            sortOrder: 1,
            comparisonColorRawValue: "orange"
        )
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let aliceRecord = fingerprintRecord(
            id: UUID(uuidString: "91000000-0000-0000-0000-000000000001")!,
            owner: alice,
            arrivalIATA: "YUL",
            arrivalName: "Montreal",
            updatedAt: updatedAt
        )
        let bobRecord = fingerprintRecord(
            id: UUID(uuidString: "92000000-0000-0000-0000-000000000002")!,
            owner: bob,
            arrivalIATA: "YUL",
            arrivalName: "Montreal",
            updatedAt: updatedAt
        )
        for model in [aliceProfile, bobProfile] {
            container.mainContext.insert(model)
        }
        for record in [aliceRecord, bobRecord] {
            container.mainContext.insert(record)
        }
        try container.mainContext.save()
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let view = ComparisonView(
            userSession: UserSession(defaults: defaults),
            commandState: AppCommandState(),
            initialSelection: [alice, bob]
        ).modelContainer(container)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 1_080, height: 720)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        settle(host)
        XCTAssertTrue(accessibilityText(host).contains("YUL"))

        aliceProfile.displayName = "Alice Restored"
        for record in [aliceRecord, bobRecord] {
            record.arrivalAirportIATA = "SFO"
            record.arrivalAirportName = "San Francisco"
            record.arrivalCity = "San Francisco"
            record.arrivalCountry = "United States"
            record.arrivalCountryCode = "US"
            record.arrivalLatitude = 37.6213
            record.arrivalLongitude = -122.379
            record.arrivalTimeZoneID = "America/Los_Angeles"
            record.notes = "restored without updatedAt change"
            record.updatedAt = updatedAt
        }
        try container.mainContext.save()
        settle(host)

        let updatedText = accessibilityText(host)
        XCTAssertTrue(updatedText.contains("Alice Restored"), updatedText)
        XCTAssertTrue(updatedText.contains("SFO"), updatedText)
        XCTAssertFalse(updatedText.contains("YUL"), updatedText)
    }

    @MainActor
    func testOpeningForeignFlightActivatesOwnerBeforeRequestingFlight() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let session = UserSession(defaults: defaults)
        let commands = AppCommandState()

        ComparisonFlightOpening.open(
            recordID: UUID(uuidString: "90000000-0000-0000-0000-000000000009")!,
            ownerProfileID: bob,
            userSession: session,
            commandState: commands
        )

        XCTAssertEqual(session.activeProfileID, bob)
        XCTAssertEqual(
            commands.openFlightRequest?.id,
            UUID(uuidString: "90000000-0000-0000-0000-000000000009")!
        )
        XCTAssertEqual(commands.selection, .flights)
    }

    func testComparisonColorsMeetGraphicContrastOnPaperAndMapSurfaces() {
        for appearance in FlightTheme.Appearance.allCases {
            for contrast in [FlightTheme.Contrast.standard, .increased] {
                let palette = FlightTheme.palette(for: appearance, contrast: contrast)
                for color in ProfileComparisonColor.allCases {
                    let token = ComparisonColorPalette.token(
                        color,
                        appearance: appearance,
                        contrast: contrast
                    )
                    XCTAssertGreaterThanOrEqual(
                        token.contrastRatio(with: palette.paper),
                        FlightTheme.ContrastThreshold.largeText
                    )
                    XCTAssertGreaterThanOrEqual(
                        token.contrastRatio(with: palette.archiveCard),
                        FlightTheme.ContrastThreshold.largeText
                    )
                }
                let partial = ComparisonColorPalette.partialRouteToken(
                    appearance: appearance,
                    contrast: contrast
                )
                XCTAssertGreaterThanOrEqual(
                    partial.contrastRatio(with: palette.paper),
                    FlightTheme.ContrastThreshold.largeText
                )
                XCTAssertGreaterThanOrEqual(
                    partial.contrastRatio(with: palette.archiveCard),
                    FlightTheme.ContrastThreshold.largeText
                )
            }
        }
    }

    func testSnapshotServicePropagatesCancellationError() async {
        let alice = self.alice
        let bob = self.bob
        let task = Task {
            try ComparisonService().compareSnapshots([
                .init(profileID: alice, name: "Alice", color: .blue, records: []),
                .init(profileID: bob, name: "Bob", color: .orange, records: []),
            ])
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancelled comparison unexpectedly completed")
        } catch is CancellationError {
            // Expected: cancellation is not translated to a presentation error.
        } catch {
            XCTFail("Expected CancellationError, received \(error)")
        }
    }

    @MainActor
    func testGenerationGateRejectsCancelledAndLateResults() {
        let gate = ComparisonGenerationGate()
        let first = gate.begin()
        let second = gate.begin()

        XCTAssertFalse(gate.accept(first))
        XCTAssertTrue(gate.accept(second))
        gate.cancel()
        XCTAssertFalse(gate.accept(second))
    }

    func testRapidReplacementKeepsAtMostOneDetachedWorkerActive() async {
        let probe = ComparisonWorkerProbe()
        let lane = ComparisonWorkerLane<Int>(probe: probe)
        var requests: [Task<Int, Error>] = []

        for value in 0..<10 {
            requests.append(Task {
                try await lane.run {
                    for _ in 0..<20 {
                        try Task.checkCancellation()
                        try await Task.sleep(for: .milliseconds(5))
                    }
                    return value
                }
            })
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }

        var completed: [Int] = []
        for request in requests {
            if let value = try? await request.value {
                completed.append(value)
            }
        }
        let snapshot = await probe.snapshot()
        XCTAssertEqual(snapshot.maximumActiveCount, 1)
        XCTAssertEqual(snapshot.activeCount, 0)
        XCTAssertEqual(completed, [9])
    }

    private func fingerprintRecord(
        id: UUID,
        owner: UUID,
        arrivalIATA: String,
        arrivalName: String,
        updatedAt: Date
    ) -> FlightRecord {
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
            iata: arrivalIATA,
            icao: "",
            name: arrivalName,
            city: arrivalName,
            country: "United States",
            countryCode: "US",
            latitude: arrivalIATA == "SFO" ? 37 : 45,
            longitude: arrivalIATA == "SFO" ? -122 : -73,
            timeZoneID: "America/Los_Angeles"
        )
        return FlightRecord(
            id: id,
            flightNumber: "CA123",
            airlineCode: "CA",
            airlineName: "Air China",
            flightDate: Date(timeIntervalSince1970: 1_690_000_000),
            departureAirport: departure,
            arrivalAirport: arrival,
            departureDate: Date(timeIntervalSince1970: 1_690_003_600),
            arrivalDate: Date(timeIntervalSince1970: 1_690_010_800),
            aircraftType: "A350",
            cabinClass: "Business",
            seat: "3A",
            notes: "baseline",
            ownerProfileID: owner,
            createdAt: Date(timeIntervalSince1970: 1_680_000_000),
            updatedAt: updatedAt
        )
    }

    @MainActor
    private func settle<V: View>(_ host: NSHostingView<V>) {
        for _ in 0..<20 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            host.layoutSubtreeIfNeeded()
        }
    }

    @MainActor
    private func accessibilityText(_ root: Any) -> String {
        var values: [String] = []
        var visited = Set<ObjectIdentifier>()
        func visit(_ value: Any) {
            if let object = value as AnyObject? {
                let identifier = ObjectIdentifier(object)
                guard visited.insert(identifier).inserted else { return }
            }
            if let element = value as? NSAccessibilityProtocol {
                for text in [
                    element.accessibilityLabel(),
                    element.accessibilityValue().map(String.init(describing:)),
                    element.accessibilityHelp(),
                ].compactMap({ $0 }) where !text.isEmpty {
                    values.append(text)
                }
                element.accessibilityChildren()?.forEach(visit)
                element.accessibilityContents()?.forEach(visit)
            }
            if let view = value as? NSView {
                view.subviews.forEach(visit)
            }
        }
        visit(root)
        return values.joined(separator: "\n")
    }

    private func assertSendable<T: Sendable>(_: T) {}
}
