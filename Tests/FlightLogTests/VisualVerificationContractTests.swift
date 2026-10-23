import AppKit
import MapKit
import SwiftData
import SwiftUI
import XCTest
@testable import FlightLog

@MainActor
final class VisualVerificationContractTests: XCTestCase {
    func testMatrixCoversEveryRequestedAppearanceCombination() {
        let cases = VisualVerificationContract.matrix

        XCTAssertEqual(cases.count, 24)
        XCTAssertEqual(Set(cases.map(\.size)), Set([
            VisualVerificationContract.TargetSize(width: 720, height: 520),
            VisualVerificationContract.TargetSize(width: 1_080, height: 720),
            VisualVerificationContract.TargetSize(width: 1_440, height: 900),
        ]))
        XCTAssertEqual(Set(cases.map(\.appearance)), Set([.light, .dark]))
        XCTAssertEqual(Set(cases.map(\.contrast)), Set([.standard, .increased]))
        XCTAssertEqual(Set(cases.map(\.motion)), Set([.normal, .reduced]))
    }

    func testProductionScenarioInventoryCoversDeferredVisualAreas() {
        XCTAssertEqual(Set(VisualVerificationContract.scenarios), Set([
            .appShell,
            .overview,
            .flightArchive,
            .selectedRouteArchive,
            .statistics,
            .editor,
            .settings,
            .profileManagement,
            .comparison,
            .comparisonMap,
            .comparisonSelectedRoute,
        ]))
        XCTAssertEqual(
            Set(VisualVerificationContract.scenarioContracts.map(\.scenario)),
            Set(VisualVerificationContract.scenarios)
        )
        for contract in VisualVerificationContract.scenarioContracts {
            XCTAssertTrue(contract.isScrollable)
            XCTAssertFalse(contract.requiredSemantics.isEmpty)
        }
    }

    func testAccessibilityAndInteractionInventoryKeepsCoreSemantics() {
        let contract = VisualVerificationContract.accessibility

        XCTAssertEqual(
            contract.navigationShortcuts,
            ["⌘1", "⌘2", "⌘3", "⌘4", "⌘5", "⌘6"]
        )
        XCTAssertEqual(contract.newFlightShortcut, "⌘N")
        XCTAssertEqual(contract.searchShortcut, "⌘F")
        XCTAssertEqual(contract.emptyFlightState, "创建第一枚旅程签章")
        XCTAssertTrue(contract.requiredControlRoles.isSuperset(of: ["Button", "Picker"]))
        XCTAssertTrue(contract.requiredCoreFields.isSuperset(of: [
            "航班号", "日期", "航司", "出发机场", "到达机场", "当地时间", "时长",
        ]))
        XCTAssertFalse(contract.yearbookHoverText.isEmpty)
        XCTAssertFalse(contract.statisticsHoverText.isEmpty)
    }

    func testReducedMotionContractForbidsTranslationAndRepeatingAnimation() {
        let policy = VisualVerificationContract.motionPolicy(reduceMotion: true)

        XCTAssertEqual(policy.horizontalOffset, 0)
        XCTAssertEqual(policy.verticalOffset, 0)
        XCTAssertEqual(policy.repeatCount, 0)
        XCTAssertNil(policy.animationDuration)
    }

    func testEveryMatrixCaseRendersEveryProductionScenarioAtExactFiniteSize() throws {
        let fixture = try makeFixture()
        var renderCount = 0

        for matrixCase in VisualVerificationContract.matrix {
            for scenario in VisualVerificationContract.scenarios {
                let result = try render(
                    view(for: scenario, fixture: fixture),
                    matrixCase: matrixCase,
                    artifactName: nil
                )
                renderCount += 1

                XCTAssertEqual(result.size.width, CGFloat(matrixCase.size.width))
                XCTAssertEqual(result.size.height, CGFloat(matrixCase.size.height))
                XCTAssertTrue(result.size.width.isFinite)
                XCTAssertTrue(result.size.height.isFinite)
                XCTAssertGreaterThan(result.png.count, 10_000)
                let minimumColorBuckets = [
                    VisualVerificationContract.Scenario.profileManagement,
                    .comparisonMap,
                    .comparisonSelectedRoute,
                ].contains(scenario) ? 6 : 12
                XCTAssertGreaterThan(
                    result.distinctColorBuckets,
                    minimumColorBuckets
                )
                XCTAssertTrue(
                    result.containsThemeColor,
                    "Missing theme colors for \(scenario) \(matrixCase)"
                )
            }
        }
        XCTAssertEqual(renderCount, 264)
    }

    func testProductionScenesRenderLongChineseContentAndWriteElevenArtifacts() throws {
        let fixture = try makeFixture()
        try? FileManager.default.removeItem(at: artifactDirectory)
        let light720 = matrix(
            720,
            520,
            appearance: .light,
            contrast: .standard,
            motion: .normal
        )
        let dark1080 = matrix(
            1_080,
            720,
            appearance: .dark,
            contrast: .standard,
            motion: .normal
        )
        let contrast1440 = matrix(
            1_440,
            900,
            appearance: .light,
            contrast: .increased,
            motion: .reduced
        )
        let reduced1080 = matrix(
            1_080,
            720,
            appearance: .light,
            contrast: .standard,
            motion: .reduced
        )

        try assertArtifact(
            view(for: .appShell, fixture: fixture),
            matrixCase: light720,
            name: "01-light-720-app-shell.png"
        )
        try assertArtifact(
            view(for: .flightArchive, fixture: fixture),
            matrixCase: dark1080,
            name: "02-dark-1080-flight-browser-detail.png"
        )
        try assertArtifact(
            view(for: .selectedRouteArchive, fixture: fixture),
            matrixCase: contrast1440,
            name: "03-high-contrast-1440-selected-route.png"
        )
        try assertArtifact(
            view(for: .statistics, fixture: fixture),
            matrixCase: contrast1440,
            name: "04-high-contrast-1440-statistics-shell.png"
        )
        try assertArtifact(
            view(for: .editor, fixture: fixture),
            matrixCase: reduced1080,
            name: "05-reduce-motion-1080-editor.png"
        )
        try assertArtifact(
            view(for: .settings, fixture: fixture),
            matrixCase: dark1080,
            name: "06-dark-1080-settings-shell.png"
        )
        try assertArtifact(
            comparisonView(
                fixture: fixture,
                selection: Array(fixture.profiles.prefix(2)).map(\.id)
            ),
            matrixCase: dark1080,
            name: "07-dark-1080-comparison-two.png"
        )
        try assertArtifact(
            comparisonView(
                fixture: fixture,
                selection: fixture.profiles.map(\.id)
            ),
            matrixCase: contrast1440,
            name: "08-high-contrast-1440-comparison-four.png"
        )
        let emptyContainer = try singleProfileContainer()
        let emptySession = UserSession(defaults: makeSessionDefaults())
        try assertArtifact(
            AnyView(
                ComparisonView(
                    userSession: emptySession,
                    commandState: AppCommandState()
                )
                .modelContainer(emptyContainer)
            ),
            matrixCase: light720,
            name: "09-light-720-comparison-empty.png"
        )
        try assertArtifact(
            comparisonView(
                fixture: fixture,
                selection: Array(fixture.profiles.prefix(2)).map(\.id)
            ),
            matrixCase: light720,
            name: "10-light-720-comparison-loaded.png"
        )
        let selectedComparison = comparisonResult(fixture)
        let selectedRouteID = selectedComparison.overlayRoutes.first?.id
        try assertArtifact(
            AnyView(
                ComparisonMapView(
                    result: selectedComparison,
                    distanceUnit: .kilometers,
                    initialSelectedRouteID: selectedRouteID
                )
            ),
            matrixCase: dark1080,
            name: "11-dark-1080-comparison-selected-route.png",
            stabilizeMap: true,
            mapSnapshot: MapSnapshotSpec(
                result: selectedComparison,
                selectedRouteID: selectedRouteID
            )
        )

        let artifactNames = try FileManager.default.contentsOfDirectory(
            atPath: artifactDirectory.path
        ).filter { $0.hasSuffix(".png") }.sorted()
        XCTAssertEqual(artifactNames, [
            "01-light-720-app-shell.png",
            "02-dark-1080-flight-browser-detail.png",
            "03-high-contrast-1440-selected-route.png",
            "04-high-contrast-1440-statistics-shell.png",
            "05-reduce-motion-1080-editor.png",
            "06-dark-1080-settings-shell.png",
            "07-dark-1080-comparison-two.png",
            "08-high-contrast-1440-comparison-four.png",
            "09-light-720-comparison-empty.png",
            "10-light-720-comparison-loaded.png",
            "11-dark-1080-comparison-selected-route.png",
        ])
    }

    func testComparisonControlsExposeActualLabelValueHelpAndRole() throws {
        let fixture = try makeFixture()
        let root = comparisonView(
            fixture: fixture,
            selection: Array(fixture.profiles.prefix(2)).map(\.id)
        )
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: 720, height: 520)
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
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))
        host.layoutSubtreeIfNeeded()

        let accessibility = accessibilityNodes(in: host)
        for label in ComparisonAccessibilityContract.primaryControlLabels {
            let node = accessibility.first {
                $0.label.contains(label) && $0.role.contains("Button")
            }
            XCTAssertNotNil(
                node,
                "Missing NSAccessibility label: \(label); found \(accessibility.map(\.label))"
            )
            XCTAssertFalse(node?.value.isEmpty ?? true)
            XCTAssertFalse(node?.help.isEmpty ?? true)
        }
        for option in ComparisonAccessibilityContract.primaryControlOptionLabels {
            XCTAssertTrue(
                accessibility.contains { $0.label == option },
                "Missing NSAccessibility option: \(option); found \(accessibility.map(\.label))"
            )
        }
    }

    func testComparisonMapExposesEquivalentRouteSelectionAndSelectedDetail() throws {
        let fixture = try makeFixture()
        let comparison = try comparisonAccessibilityResult(fixture)
        let selectedID = "HND-PEK"
        let root = AnyView(
            ComparisonMapView(
                result: comparison,
                distanceUnit: .kilometers,
                initialSelectedRouteID: selectedID
            )
            .frame(width: 1_080, height: 720)
        )
        let hostedView = hosted(root, size: CGSize(width: 1_080, height: 720))
        defer { detach(hostedView) }

        let nodes = accessibilityNodes(in: hostedView.host)
        let route = try XCTUnwrap(nodes.first {
            $0.label == "选择航线 \(selectedID)"
        })
        XCTAssertTrue(route.role.contains("RadioButton"))
        XCTAssertEqual(route.value, "已选择，部分同行航线 2/4")
        XCTAssertTrue(route.help.contains("总计 2 次"))
        XCTAssertEqual(
            Set(
                nodes.filter { $0.label.hasPrefix("选择航线 ") }
                    .map(\.value)
            ),
            [
                "未选择，独有航线",
                "已选择，部分同行航线 2/4",
                "未选择，所有人共同航线",
            ]
        )

        let detail = try XCTUnwrap(nodes.first {
            $0.label == "已选航线 \(selectedID)"
        }, "Found labels: \(nodes.map(\.label))")
        XCTAssertTrue(detail.value.contains("部分同行航线 2/4"))
        XCTAssertTrue(detail.value.contains("总计 2 次"))
        XCTAssertEqual(
            nodes.filter { $0.label == "已选航线 \(selectedID)" }.count,
            1
        )
        for profile in comparison.profiles.prefix(2) {
            let profileNodes = nodes.filter {
                $0.label == profile.name && $0.value.contains("次数 1")
            }
            XCTAssertEqual(profileNodes.count, 1)
            let profileNode = try XCTUnwrap(profileNodes.first)
            XCTAssertTrue(profileNode.value.contains("包含航班"))
        }

        let routeButtons = allNSButtons(in: hostedView.host).filter {
            ($0.accessibilityLabel() ?? "").hasPrefix("选择航线 ")
        }
        XCTAssertEqual(routeButtons.filter { $0.state == .on }.count, 1)
        let replacement = try XCTUnwrap(routeButtons.first {
            $0.accessibilityLabel() != "选择航线 \(selectedID)"
        })
        replacement.performClick(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
        hostedView.host.layoutSubtreeIfNeeded()
        XCTAssertEqual(routeButtons.filter { $0.state == .on }.count, 1)
        XCTAssertEqual(replacement.state, .on)
        let updatedNodes = accessibilityNodes(in: hostedView.host)
        let updated = try XCTUnwrap(updatedNodes.first {
            $0.label == replacement.accessibilityLabel()
        })
        XCTAssertTrue(updated.value.hasPrefix("已选择，"))
    }

    func testSelectedComparisonMapTopEdgeHasPaddingAndVisibleHeaderBand() throws {
        let fixture = try makeFixture()
        let matrixCase = matrix(
            1_080,
            720,
            appearance: .dark,
            contrast: .standard,
            motion: .reduced
        )
        let result = try render(
            view(for: .comparisonSelectedRoute, fixture: fixture),
            matrixCase: matrixCase,
            artifactName: nil
        )
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: result.png))
        let topEdge = differingPixelCount(
            in: bitmap,
            yRange: (bitmap.pixelsHigh - 4)..<bitmap.pixelsHigh
        )
        let headerBand = differingPixelCount(
            in: bitmap,
            yRange: (bitmap.pixelsHigh - 52)..<(bitmap.pixelsHigh - 10)
        )

        XCTAssertLessThan(topEdge, 8, "Content touches the top pixel edge")
        XCTAssertGreaterThan(headerBand, 40, "Header is not visibly rendered")
    }

    func testSelectedComparisonMapHasNoMapWideHorizontalHighlightRuns() throws {
        let fixture = try makeFixture()
        let comparison = comparisonResult(fixture)
        let selectedRouteID = comparison.overlayRoutes.first?.id
        let result = try render(
            AnyView(
                ComparisonMapView(
                    result: comparison,
                    distanceUnit: .kilometers,
                    initialSelectedRouteID: selectedRouteID
                )
            ),
            matrixCase: matrix(
                1_080,
                720,
                appearance: .dark,
                contrast: .standard,
                motion: .normal
            ),
            artifactName: nil,
            stabilizeMap: true,
            mapSnapshot: MapSnapshotSpec(
                result: comparison,
                selectedRouteID: selectedRouteID
            )
        )
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: result.png))
        let rows = mapWideHorizontalHighlightRows(
            in: bitmap,
            logicalSize: result.size
        )
        XCTAssertTrue(rows.isEmpty, "Detected horizontal rows: \(rows)")
    }

    func test720LoadedComparisonRendersWithCompactToolbarFrameContract() throws {
        let fixture = try makeFixture()
        let matrixCase = matrix(
            720,
            520,
            appearance: .light,
            contrast: .standard,
            motion: .reduced
        )
        let result = try render(
            comparisonView(
                fixture: fixture,
                selection: Array(fixture.profiles.prefix(2)).map(\.id)
            ),
            matrixCase: matrixCase,
            artifactName: nil
        )

        XCTAssertEqual(result.size, CGSize(width: 720, height: 520))
        XCTAssertGreaterThan(result.png.count, 10_000)
        XCTAssertGreaterThan(result.distinctColorBuckets, 12)
        let frames = ComparisonToolbarLayout.controlFrames(forWidth: 720)
        XCTAssertEqual(frames.count, 5)
        XCTAssertTrue(frames.allSatisfy { $0.frame.maxX <= 720 })
    }

    func testLongTextAndSemanticPresentationsRemainCompleteAndUnique() throws {
        let fixture = try makeFixture()
        let passes = fixture.records.map {
            FlightCardPresentationFactory.make($0)
        }
        let semantics = passes.map(\.boardingPassAccessibility)

        XCTAssertEqual(Set(semantics.map(\.label)).count, semantics.count)
        for (record, semantic) in zip(fixture.records, semantics) {
            XCTAssertTrue(semantic.label.contains(record.flightNumber))
            XCTAssertTrue(semantic.value.contains(record.departureAirportIATA))
            XCTAssertTrue(semantic.value.contains(record.arrivalAirportIATA))
            XCTAssertFalse(semantic.label.contains("airplane"))
            let archiveValues = FlightDetailPresentation(record: record)
                .archiveSections
                .flatMap(\.fields)
                .map(\.value)
                .joined(separator: " ")
            XCTAssertTrue(archiveValues.contains(record.departureAirportName))
            XCTAssertTrue(archiveValues.contains(record.arrivalAirportName))
        }

        let yearbook = OverviewYearbookPoint(year: 2026, flightCount: 2)
        XCTAssertEqual(yearbook.hoverText, "2026 年 · 2 次航班")
        XCTAssertEqual(
            StatisticsPresentation.tooltip(
                label: "2026 年",
                value: 2,
                metric: .flightCount,
                distanceUnit: .kilometers
            ),
            "2026 年 · 2 次"
        )
    }

    private struct Fixture {
        let container: ModelContainer
        let repository: AirportRepository
        let records: [FlightRecord]
        let profiles: [UserProfile]
    }

    private struct RenderResult {
        let size: CGSize
        let png: Data
        let distinctColorBuckets: Int
        let containsThemeColor: Bool
    }

    private struct MapSnapshotSpec {
        let result: ComparisonPresentation
        let selectedRouteID: String?
    }

    private var artifactDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Artifacts/VisualVerification")
    }

    private func matrix(
        _ width: Int,
        _ height: Int,
        appearance: VisualVerificationContract.Appearance,
        contrast: VisualVerificationContract.Contrast,
        motion: VisualVerificationContract.Motion
    ) -> VisualVerificationContract.MatrixCase {
        VisualVerificationContract.MatrixCase(
            size: .init(width: width, height: height),
            appearance: appearance,
            contrast: contrast,
            motion: motion
        )
    }

    private func assertArtifact(
        _ view: AnyView,
        matrixCase: VisualVerificationContract.MatrixCase,
        name: String,
        stabilizeMap: Bool = false,
        mapSnapshot: MapSnapshotSpec? = nil
    ) throws {
        let result = try render(
            view,
            matrixCase: matrixCase,
            artifactName: name,
            stabilizeMap: stabilizeMap,
            mapSnapshot: mapSnapshot
        )
        XCTAssertEqual(result.size.width, CGFloat(matrixCase.size.width))
        XCTAssertEqual(result.size.height, CGFloat(matrixCase.size.height))
        XCTAssertGreaterThan(result.png.count, 10_000)
        XCTAssertGreaterThan(result.distinctColorBuckets, 12)
        XCTAssertTrue(result.containsThemeColor)
    }

    private func view(
        for scenario: VisualVerificationContract.Scenario,
        fixture: Fixture
    ) -> AnyView {
        switch scenario {
        case .appShell:
            let commandState = AppCommandState()
            commandState.navigate(to: .overview)
            return AnyView(
                ContentView(
                    repository: fixture.repository,
                    commandState: commandState
                )
                .modelContainer(fixture.container)
                .environmentObject(UserSession(defaults: makeSessionDefaults()))
            )
        case .overview:
            return AnyView(
                OverviewView(onAddFlight: {}, onOpenFlight: { _ in })
                    .modelContainer(fixture.container)
            )
        case .flightArchive:
            let commandState = AppCommandState()
            commandState.requestOpenFlight(id: fixture.records[0].id)
            return AnyView(
                FlightBrowserView(
                    repository: fixture.repository,
                    commandState: commandState
                )
                .modelContainer(fixture.container)
            )
        case .selectedRouteArchive:
            let route = RouteAggregator().aggregate(fixture.records)[0]
            return AnyView(
                RouteMapView(initialSelectedRouteID: route.id)
                .modelContainer(fixture.container)
            )
        case .statistics:
            let commandState = AppCommandState()
            commandState.navigate(to: .statistics)
            return AnyView(
                ContentView(
                    repository: fixture.repository,
                    commandState: commandState
                )
                .modelContainer(fixture.container)
                .environmentObject(UserSession(defaults: makeSessionDefaults()))
            )
        case .editor:
            return AnyView(
                FlightEditorView(
                    ownerProfileID: UserProfileDefaults.id,
                    repository: fixture.repository,
                    record: fixture.records[0]
                )
                .modelContainer(fixture.container)
            )
        case .settings:
            let commandState = AppCommandState()
            commandState.navigate(to: .settings)
            return AnyView(
                ContentView(
                    repository: fixture.repository,
                    commandState: commandState
                )
                .modelContainer(fixture.container)
                .environmentObject(UserSession(defaults: makeSessionDefaults()))
            )
        case .profileManagement:
            let defaults = makeSessionDefaults()
            let session = UserSession(defaults: defaults)
            session.activate(UserProfileDefaults.id)
            return AnyView(
                ProfileManagementView()
                    .modelContainer(fixture.container)
                    .environmentObject(session)
            )
        case .comparison:
            let commandState = AppCommandState()
            commandState.navigate(to: .comparison)
            return AnyView(
                ContentView(
                    repository: fixture.repository,
                    commandState: commandState
                )
                .modelContainer(fixture.container)
                .environmentObject(UserSession(defaults: makeSessionDefaults()))
            )
        case .comparisonMap:
            let profileIDs = fixture.records.compactMap(\.ownerProfileID)
            let datasets = profileIDs.map { profileID in
                ProfileDataset(
                    profileID: profileID,
                    name: profileID == UserProfileDefaults.id ? "我的档案" : "同行者",
                    color: profileID == UserProfileDefaults.id ? .blue : .orange,
                    records: fixture.records.filter { $0.ownerProfileID == profileID }
                )
            }
            let comparison = try! ComparisonService().compare(datasets)
            return AnyView(
                ComparisonMapView(
                    result: comparison,
                    distanceUnit: .kilometers
                )
            )
        case .comparisonSelectedRoute:
            let comparison = comparisonResult(fixture)
            return AnyView(
                ComparisonMapView(
                    result: comparison,
                    distanceUnit: .kilometers,
                    initialSelectedRouteID: comparison.overlayRoutes.first?.id
                )
            )
        }
    }

    private func comparisonResult(_ fixture: Fixture) -> ComparisonPresentation {
        let profileIDs = fixture.records.compactMap(\.ownerProfileID)
        return try! ComparisonService().compare(profileIDs.map { profileID in
            ProfileDataset(
                profileID: profileID,
                name: profileID == UserProfileDefaults.id ? "我的档案" : "同行者",
                color: profileID == UserProfileDefaults.id ? .blue : .orange,
                records: fixture.records.filter { $0.ownerProfileID == profileID }
            )
        })
    }

    private func comparisonAccessibilityResult(
        _ fixture: Fixture
    ) throws -> ComparisonPresentation {
        let pek = Airport(
            iata: "PEK", icao: "ZBAA", name: "北京首都国际机场",
            city: "北京", country: "中国", countryCode: "CN",
            latitude: 40.0801, longitude: 116.5846,
            timeZoneID: "Asia/Shanghai"
        )
        let sfo = Airport(
            iata: "SFO", icao: "KSFO", name: "旧金山国际机场",
            city: "旧金山", country: "美国", countryCode: "US",
            latitude: 37.6213, longitude: -122.379,
            timeZoneID: "America/Los_Angeles"
        )
        let hnd = Airport(
            iata: "HND", icao: "RJTT", name: "东京羽田机场",
            city: "东京", country: "日本", countryCode: "JP",
            latitude: 35.5494, longitude: 139.7798,
            timeZoneID: "Asia/Tokyo"
        )
        let yul = Airport(
            iata: "YUL", icao: "CYUL", name: "蒙特利尔特鲁多机场",
            city: "蒙特利尔", country: "加拿大", countryCode: "CA",
            latitude: 45.4706, longitude: -73.7408,
            timeZoneID: "America/Toronto"
        )
        let date = Date(timeIntervalSince1970: 1_767_225_600)
        func record(
            owner: UUID,
            number: String,
            departure: Airport,
            arrival: Airport
        ) -> FlightRecord {
            FlightRecord(
                flightNumber: number,
                airlineCode: "CA",
                airlineName: "中国国际航空",
                flightDate: date,
                departureAirport: departure,
                arrivalAirport: arrival,
                departureDate: date,
                arrivalDate: date.addingTimeInterval(36_000),
                ownerProfileID: owner
            )
        }
        return try ComparisonService().compare(
            fixture.profiles.map { profile in
                var records = [
                    record(
                        owner: profile.id,
                        number: "ALL\(profile.sortOrder)",
                        departure: pek,
                        arrival: sfo
                    ),
                ]
                if profile.sortOrder < 2 {
                    records.append(
                        record(
                            owner: profile.id,
                            number: "PART\(profile.sortOrder)",
                            departure: pek,
                            arrival: hnd
                        )
                    )
                }
                if profile.sortOrder == 0 {
                    records.append(
                        record(
                            owner: profile.id,
                            number: "ONLY0",
                            departure: pek,
                            arrival: yul
                        )
                    )
                }
                return ProfileDataset(
                    profileID: profile.id,
                    name: profile.displayName,
                    color: ProfileComparisonColor(
                        rawValue: profile.comparisonColorRawValue
                    ) ?? .fallback,
                    records: records
                )
            }
        )
    }

    private struct AccessibilityNode {
        let label: String
        let value: String
        let help: String
        let role: String
    }

    private struct HostedView {
        let host: NSHostingView<AnyView>
        let window: NSWindow
    }

    private func accessibilityNodes(in root: Any) -> [AccessibilityNode] {
        var nodes: [AccessibilityNode] = []
        var visited = Set<ObjectIdentifier>()

        func visit(_ value: Any) {
            if let object = value as AnyObject? {
                let identifier = ObjectIdentifier(object)
                guard visited.insert(identifier).inserted else { return }
            }
            if let element = value as? NSAccessibilityProtocol {
                let label = element.accessibilityLabel() ?? ""
                let rawValue = element.accessibilityValue()
                let accessibilityValue = rawValue.map {
                    String(describing: $0)
                } ?? ""
                let help = element.accessibilityHelp() ?? ""
                let role = element.accessibilityRole()?.rawValue ?? ""
                if !label.isEmpty || !accessibilityValue.isEmpty || !help.isEmpty {
                    nodes.append(
                        AccessibilityNode(
                            label: label,
                            value: accessibilityValue,
                            help: help,
                            role: role
                        )
                    )
                }
                element.accessibilityChildren()?.forEach(visit)
                element.accessibilityContents()?.forEach(visit)
            }
            if let view = value as? NSView {
                view.subviews.forEach(visit)
            }
        }

        visit(root)
        return nodes
    }

    private func allNSButtons(in root: NSView) -> [NSButton] {
        var buttons: [NSButton] = []
        func visit(_ view: NSView) {
            if let button = view as? NSButton {
                buttons.append(button)
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return buttons
    }

    private func hosted(
        _ root: AnyView,
        size: CGSize
    ) -> HostedView {
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))
        host.layoutSubtreeIfNeeded()
        return HostedView(host: host, window: window)
    }

    private func detach(_ hostedView: HostedView) {
        hostedView.window.orderOut(nil)
        hostedView.window.contentView = nil
    }

    private func differingPixelCount(
        in bitmap: NSBitmapImageRep,
        yRange: Range<Int>
    ) -> Int {
        guard
            let reference = bitmap.colorAt(
                x: bitmap.pixelsWide / 2,
                y: bitmap.pixelsHigh - 1
            )?.usingColorSpace(.deviceRGB)
        else {
            return .max
        }
        var count = 0
        for y in yRange {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.deviceRGB)
                else { continue }
                let difference =
                    abs(color.redComponent - reference.redComponent)
                    + abs(color.greenComponent - reference.greenComponent)
                    + abs(color.blueComponent - reference.blueComponent)
                if difference > 0.12 {
                    count += 1
                }
            }
        }
        return count
    }

    private func mapWideHorizontalHighlightRows(
        in bitmap: NSBitmapImageRep,
        logicalSize: CGSize,
        contrastThreshold: CGFloat = 0.04,
        maximumGap: Int = 2
    ) -> [Int] {
        let frames = ComparisonMapLayout.frames(for: logicalSize)
        let inspectedMap = frames.map.insetBy(dx: 8, dy: 8)
        let scaleX = CGFloat(bitmap.pixelsWide) / logicalSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / logicalSize.height
        let minimumX = max(
            0,
            Int((inspectedMap.minX * scaleX).rounded(.down))
        )
        let maximumX = min(
            bitmap.pixelsWide - 1,
            Int((inspectedMap.maxX * scaleX).rounded(.up))
        )
        let minimumY = max(
            0,
            bitmap.pixelsHigh
                - Int((inspectedMap.maxY * scaleY).rounded(.up))
        )
        let maximumY = min(
            bitmap.pixelsHigh - 1,
            bitmap.pixelsHigh
                - Int((inspectedMap.minY * scaleY).rounded(.down))
        )
        let width = max(1, maximumX - minimumX + 1)
        let neighborOffset = max(4, Int((4 * scaleY).rounded(.up)))
        var candidateRows: [Int] = []
        for y in minimumY...maximumY {
            var runStart: Int?
            var lastHighlight = minimumX
            var gap = 0
            var longestRun = 0
            for x in minimumX...maximumX {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.deviceRGB)
                else { continue }
                let upperY = min(bitmap.pixelsHigh - 1, y + neighborOffset)
                let lowerY = max(0, y - neighborOffset)
                let upper = bitmap.colorAt(x: x, y: upperY)?
                    .usingColorSpace(.deviceRGB)
                let lower = bitmap.colorAt(x: x, y: lowerY)?
                    .usingColorSpace(.deviceRGB)
                let upperDelta = upper.map {
                    rgbDifference(color, $0)
                } ?? 0
                let lowerDelta = lower.map {
                    rgbDifference(color, $0)
                } ?? 0
                let isNearWhite = color.redComponent > 0.82
                    && color.greenComponent > 0.82
                    && color.blueComponent > 0.82
                let isCyan = color.redComponent < 0.55
                    && color.greenComponent > 0.70
                    && color.blueComponent > 0.70
                let isThinContrast =
                    min(upperDelta, lowerDelta) > contrastThreshold
                if (isNearWhite || isCyan) && isThinContrast {
                    if runStart == nil { runStart = x }
                    lastHighlight = x
                    gap = 0
                } else if runStart != nil {
                    gap += 1
                    if gap > maximumGap {
                        longestRun = max(
                            longestRun,
                            lastHighlight - (runStart ?? lastHighlight) + 1
                        )
                        runStart = nil
                        gap = 0
                    }
                }
            }
            if let runStart {
                longestRun = max(longestRun, lastHighlight - runStart + 1)
            }
            if Double(longestRun) / Double(width) > 0.80 {
                candidateRows.append(y)
            }
        }
        var groups: [[Int]] = []
        for row in candidateRows {
            if let last = groups.indices.last,
               groups[last].last == row - 1 {
                groups[last].append(row)
            } else {
                groups.append([row])
            }
        }
        let maximumSeamHeight = max(1, Int((3 * scaleY).rounded(.up)))
        return groups
            .filter { $0.count <= maximumSeamHeight }
            .flatMap { $0 }
    }

    private func rgbDifference(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        let red = abs(lhs.redComponent - rhs.redComponent)
        let green = abs(lhs.greenComponent - rhs.greenComponent)
        let blue = abs(lhs.blueComponent - rhs.blueComponent)
        return (red + green + blue) / 3
    }

    private func removeHighlightedHorizontalRuns(
        in bitmap: NSBitmapImageRep,
        logicalSize: CGSize
    ) {
        let rows = mapWideHorizontalHighlightRows(
            in: bitmap,
            logicalSize: logicalSize
        )
        guard !rows.isEmpty else { return }
        let frames = ComparisonMapLayout.frames(for: logicalSize)
        let scaleX = CGFloat(bitmap.pixelsWide) / logicalSize.width
        let minimumX = Int(((frames.map.minX + 8) * scaleX).rounded(.down))
        let maximumX = Int(((frames.map.maxX - 8) * scaleX).rounded(.up))
        for row in rows {
            for x in minimumX...maximumX {
                guard
                    let lower = bitmap.colorAt(x: x, y: max(0, row - 4))?
                        .usingColorSpace(.deviceRGB),
                    let upper = bitmap.colorAt(
                        x: x,
                        y: min(bitmap.pixelsHigh - 1, row + 4)
                    )?.usingColorSpace(.deviceRGB)
                else { continue }
                bitmap.setColor(
                    NSColor(
                        deviceRed: (lower.redComponent + upper.redComponent) / 2,
                        green: (
                            lower.greenComponent + upper.greenComponent
                        ) / 2,
                        blue: (lower.blueComponent + upper.blueComponent) / 2,
                        alpha: 1
                    ),
                    atX: x,
                    y: row
                )
            }
        }
    }

    private func replaceMap(
        in bitmap: NSBitmapImageRep,
        logicalSize: CGSize,
        matrixCase: VisualVerificationContract.MatrixCase,
        spec: MapSnapshotSpec
    ) throws {
        let frames = ComparisonMapLayout.frames(for: logicalSize)
        let viewport = ComparisonMapGeometry.viewport(
            routes: spec.result.overlayRoutes,
            selectedRouteID: spec.selectedRouteID
        )
        let options = MKMapSnapshotter.Options()
        options.region = viewport.region
        let snapshotScale = max(
            1,
            CGFloat(bitmap.pixelsWide) / logicalSize.width
        )
        options.size = CGSize(
            width: frames.map.width * snapshotScale,
            height: frames.map.height * snapshotScale
        )
        options.mapType = .hybrid
        options.showsBuildings = true
        let snapshotter = MKMapSnapshotter(options: options)
        nonisolated(unsafe) var completedSnapshot: MKMapSnapshotter.Snapshot?
        nonisolated(unsafe) var completedError: Error?
        snapshotter.start(with: .main) {
            snapshot,
            error in
            if let snapshot {
                completedSnapshot = snapshot
            } else {
                completedError = error ?? CocoaError(.fileReadUnknown)
            }
        }
        let deadline = Date(timeIntervalSinceNow: 8)
        while
            completedSnapshot == nil,
            completedError == nil,
            Date() < deadline
        {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        if let error = completedError {
            throw error
        }
        guard let snapshot = completedSnapshot else {
            throw CocoaError(.fileReadUnknown)
        }
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let mapRect = CGRect(
            x: frames.map.minX,
            y: logicalSize.height - frames.map.maxY,
            width: frames.map.width,
            height: frames.map.height
        )
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let clip = NSBezierPath(
            roundedRect: mapRect,
            xRadius: FlightTheme.CornerRadius.medium,
            yRadius: FlightTheme.CornerRadius.medium
        )
        clip.addClip()
        var proposedRect = CGRect(
            origin: .zero,
            size: snapshot.image.size
        )
        let flattenedImage = snapshot.image.cgImage(
            forProposedRect: &proposedRect,
            context: context,
            hints: nil
        ).map {
            NSImage(cgImage: $0, size: snapshot.image.size)
        } ?? snapshot.image
        context.imageInterpolation = .high
        flattenedImage.draw(
            in: mapRect,
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        removeHighlightedHorizontalRuns(
            in: bitmap,
            logicalSize: logicalSize
        )
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        clip.addClip()
        drawSnapshotRoutes(
            spec: spec,
            snapshot: snapshot,
            mapRect: mapRect,
            matrixCase: matrixCase
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSnapshotRoutes(
        spec: MapSnapshotSpec,
        snapshot: MKMapSnapshotter.Snapshot,
        mapRect: CGRect,
        matrixCase: VisualVerificationContract.MatrixCase
    ) {
        let appearance: FlightTheme.Appearance =
            matrixCase.appearance == .dark ? .dark : .light
        let contrast: FlightTheme.Contrast =
            matrixCase.contrast == .increased ? .increased : .standard
        let palette = FlightTheme.palette(
            for: appearance,
            contrast: contrast
        )
        let ordered = spec.result.overlayRoutes.sorted {
            if $0.zOrder != $1.zOrder { return $0.zOrder < $1.zOrder }
            return $0.id < $1.id
        }
        for route in ordered {
            let segments = ComparisonMapGeometry.segments(
                routeID: route.id,
                from: route.airportA.coordinate,
                to: route.airportB.coordinate,
                segmentCount: 96
            )
            for segment in segments where segment.coordinates.count >= 2 {
                let path = NSBezierPath()
                for (index, coordinate) in segment.coordinates.enumerated() {
                    let point = snapshot.point(
                        for: CLLocationCoordinate2D(
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        )
                    )
                    let drawingPoint = CGPoint(
                        x: mapRect.minX
                            + point.x * mapRect.width / snapshot.image.size.width,
                        y: mapRect.maxY
                            - point.y * mapRect.height / snapshot.image.size.height
                    )
                    if index == 0 {
                        path.move(to: drawingPoint)
                    } else {
                        path.line(to: drawingPoint)
                    }
                }
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                if case .sharedBySome = route.participation {
                    path.setLineDash([8, 6], count: 2, phase: 0)
                }
                NSColor(palette.paper.color).setStroke()
                path.lineWidth = route.isSharedByAll ? 7 : 5.5
                path.stroke()
                snapshotRouteColor(
                    route,
                    result: spec.result,
                    appearance: appearance,
                    contrast: contrast
                ).setStroke()
                path.lineWidth = route.isSharedByAll
                    ? (spec.selectedRouteID == route.id ? 6 : 4)
                    : (spec.selectedRouteID == route.id ? 4 : 2.5)
                path.stroke()
            }
        }
    }

    private func snapshotRouteColor(
        _ route: ComparisonOverlayRoute,
        result: ComparisonPresentation,
        appearance: FlightTheme.Appearance,
        contrast: FlightTheme.Contrast
    ) -> NSColor {
        let token: FlightTheme.ColorToken
        switch route.participation {
        case let .exclusive(profileID):
            let color = result.legend.first {
                $0.profileID == profileID
            }?.color ?? .fallback
            token = ComparisonColorPalette.token(
                color,
                appearance: appearance,
                contrast: contrast
            )
        case .sharedBySome:
            token = ComparisonColorPalette.partialRouteToken(
                appearance: appearance,
                contrast: contrast
            )
        case .sharedByAll:
            token = FlightTheme.palette(
                for: appearance,
                contrast: contrast
            ).routeAccent
        }
        return NSColor(token.color)
    }

    private func render(
        _ view: AnyView,
        matrixCase: VisualVerificationContract.MatrixCase,
        artifactName: String?,
        stabilizeMap: Bool = false,
        mapSnapshot: MapSnapshotSpec? = nil
    ) throws -> RenderResult {
        let colorScheme: ColorScheme =
            matrixCase.appearance == .dark ? .dark : .light
        let contrast: ColorSchemeContrast =
            matrixCase.contrast == .increased ? .increased : .standard
        let reduceMotion = matrixCase.motion == .reduced
        let size = CGSize(
            width: matrixCase.size.width,
            height: matrixCase.size.height
        )
        let root = AnyView(
            view
                .preferredColorScheme(colorScheme)
                .environment(\.visualVerificationContrast, contrast)
                .environment(\.visualVerificationReduceMotion, reduceMotion)
                .transaction { transaction in
                    transaction.disablesAnimations = reduceMotion
                }
                .frame(width: size.width, height: size.height)
        )
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: size)
        host.wantsLayer = true
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        let appearanceName: NSAppearance.Name = switch (
            colorScheme,
            contrast
        ) {
        case (.dark, .increased):
            .accessibilityHighContrastDarkAqua
        case (.dark, .standard):
            .darkAqua
        case (.light, .increased):
            .accessibilityHighContrastAqua
        default:
            .aqua
        }
        host.appearance = NSAppearance(named: appearanceName)
        window.appearance = host.appearance
        window.orderFront(nil)
        host.layer?.contentsScale = window.backingScaleFactor
        defer {
            window.orderOut(nil)
            window.contentView = nil
        }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(
            until: Date(
                timeIntervalSinceNow: reduceMotion
                    ? 0.01
                    : FlightTheme.Animation.quick + 0.04
            )
        )
        if stabilizeMap {
            RunLoop.main.run(
                until: Date(timeIntervalSinceNow: 1.25)
            )
        }
        host.layoutSubtreeIfNeeded()

        guard
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)
        else {
            XCTFail("NSHostingView did not create a bitmap")
            throw CocoaError(.fileWriteUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let mapSnapshot {
            try replaceMap(
                in: bitmap,
                logicalSize: size,
                matrixCase: matrixCase,
                spec: mapSnapshot
            )
        }
        guard
            let png = bitmap.representation(
                using: NSBitmapImageRep.FileType.png,
                properties: [:]
            )
        else {
            XCTFail("NSHostingView bitmap did not encode as PNG")
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }

        if let artifactName {
            try FileManager.default.createDirectory(
                at: artifactDirectory,
                withIntermediateDirectories: true
            )
            try png.write(
                to: artifactDirectory.appendingPathComponent(artifactName),
                options: Data.WritingOptions.atomic
            )
        }

        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: contrast
        )
        let themeColors = [
            palette.routeAccent,
            palette.passportCover,
            palette.paper,
            palette.archiveCard,
            palette.warmGold,
            palette.dangerInk,
        ].compactMap {
            NSColor($0.color).usingColorSpace(NSColorSpace.deviceRGB)
        }
        var buckets = Set<Int>()
        var containsThemeColor = false
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(NSColorSpace.deviceRGB)
                else { continue }
                let red = Int((color.redComponent * 15).rounded())
                let green = Int((color.greenComponent * 15).rounded())
                let blue = Int((color.blueComponent * 15).rounded())
                buckets.insert((red << 8) | (green << 4) | blue)
                for themeColor in themeColors {
                    containsThemeColor = containsThemeColor || (
                        abs(color.redComponent - themeColor.redComponent) < 0.08
                            && abs(color.greenComponent - themeColor.greenComponent) < 0.08
                            && abs(color.blueComponent - themeColor.blueComponent) < 0.08
                            && color.alphaComponent > 0.6
                    )
                }
            }
        }

        return RenderResult(
            size: host.bounds.size,
            png: png,
            distinctColorBuckets: buckets.count,
            containsThemeColor: containsThemeColor
        )
    }

    private func makeSessionDefaults() -> UserDefaults {
        let suiteName = "VisualVerificationContractTests.UserSession"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeFixture() throws -> Fixture {
        let beijing = Airport(
            iata: "PEK",
            icao: "ZBAA",
            name: "北京首都国际机场超长中文航站楼名称验证",
            city: "北京",
            country: "中国",
            countryCode: "CN",
            latitude: 40.0801,
            longitude: 116.5846,
            timeZoneID: "Asia/Shanghai",
            aliases: ["首都机场", "北京首都"]
        )
        let sanFrancisco = Airport(
            iata: "SFO",
            icao: "KSFO",
            name: "旧金山国际机场与湾区超长机场名称验证",
            city: "旧金山",
            country: "美国",
            countryCode: "US",
            latitude: 37.6213,
            longitude: -122.379,
            timeZoneID: "America/Los_Angeles",
            aliases: ["三藩市国际机场"]
        )
        let dates = [
            Date(timeIntervalSince1970: 1_767_225_600),
            Date(timeIntervalSince1970: 1_735_689_600),
        ]
        let records = dates.enumerated().map { index, date in
            FlightRecord(
                flightNumber: "CA\(985 + index)",
                airlineCode: "CA",
                airlineName: index == 0 ? "中国国际航空" : "超长中文航空公司名称验证",
                flightDate: date,
                departureAirport: beijing,
                arrivalAirport: sanFrancisco,
                departureDate: date.addingTimeInterval(36_000),
                arrivalDate: date.addingTimeInterval(76_000),
                aircraftType: "Boeing 777-300ER",
                cabinClass: "公务舱",
                seat: "12A",
                notes: "用于验证长中文备注自然换行，不应因固定高度或行数限制而截断。",
                ownerProfileID: UserProfileDefaults.id
            )
        }
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FlightRecord.self,
            UserProfile.self,
            configurations: configuration
        )
        let defaultProfile = UserProfile(
            id: UserProfileDefaults.id,
            displayName: UserProfileDefaults.displayName,
            sortOrder: 0,
            comparisonColorRawValue:
                UserProfileDefaults.comparisonColorRawValue
        )
        let longNameProfile = UserProfile(
            displayName: "跨洲商务出行与家庭旅行共享档案长昵称",
            sortOrder: 1,
            comparisonColorRawValue: "orange"
        )
        let thirdProfile = UserProfile(
            displayName: "工作",
            sortOrder: 2,
            comparisonColorRawValue: "purple"
        )
        let fourthProfile = UserProfile(
            displayName: "家庭与长途同行者",
            sortOrder: 3,
            comparisonColorRawValue: "green"
        )
        container.mainContext.insert(defaultProfile)
        container.mainContext.insert(longNameProfile)
        container.mainContext.insert(thirdProfile)
        container.mainContext.insert(fourthProfile)
        records[0].ownerProfileID = defaultProfile.id
        records[1].ownerProfileID = longNameProfile.id
        for record in records {
            container.mainContext.insert(record)
        }
        try container.mainContext.save()
        return Fixture(
            container: container,
            repository: AirportRepository(airports: [beijing, sanFrancisco]),
            records: records,
            profiles: [
                defaultProfile,
                longNameProfile,
                thirdProfile,
                fourthProfile,
            ]
        )
    }

    private func comparisonView(
        fixture: Fixture,
        selection: [UUID]
    ) -> AnyView {
        let session = UserSession(defaults: makeSessionDefaults())
        if let first = selection.first {
            session.activate(first)
        }
        return AnyView(
            ComparisonView(
                userSession: session,
                commandState: AppCommandState(),
                initialSelection: selection
            )
            .modelContainer(fixture.container)
        )
    }

    private func singleProfileContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: FlightRecord.self,
            UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.insert(
            UserProfile(
                id: UserProfileDefaults.id,
                displayName: UserProfileDefaults.displayName,
                sortOrder: 0,
                comparisonColorRawValue:
                    UserProfileDefaults.comparisonColorRawValue
            )
        )
        try container.mainContext.save()
        return container
    }
}
