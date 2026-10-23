import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import FlightLog

final class AppShellContractTests: XCTestCase {
    func testNavigationExposesExactlySixStableDestinations() {
        XCTAssertEqual(AppSection.allCases.count, 6)
        XCTAssertEqual(
            AppSection.allCases.map(\.rawValue),
            ["overview", "flights", "map", "statistics", "settings", "comparison"]
        )
        XCTAssertEqual(
            AppSection.allCases.map(\.title),
            ["概览", "航班", "地图", "统计", "设置", "对比"]
        )
        XCTAssertEqual(
            AppSection.allCases.map(\.systemImage),
            [
                "rectangle.grid.2x2",
                "airplane",
                "map",
                "chart.bar",
                "gearshape",
                "person.2.wave.2",
            ]
        )
        XCTAssertEqual(
            AppSection.allCases.map(\.keyboardShortcutCharacter),
            ["1", "2", "3", "4", "5", "6"]
        )
    }

    func testEveryChapterProvidesNarrativeAndAccessibleSummary() {
        for section in AppSection.allCases {
            XCTAssertFalse(section.narrative.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertEqual(
                section.accessibilitySummary,
                "\(section.title)，\(section.narrative)"
            )
        }
    }

    func testShellExclusivelyOwnsEverySectionPageHeader() {
        XCTAssertEqual(
            Set(AppSectionHeaderOwnership.shellOwnedSections),
            Set(AppSection.allCases)
        )
        XCTAssertTrue(AppSectionHeaderOwnership.statisticsContentOwnsHeader == false)
        XCTAssertTrue(AppSectionHeaderOwnership.settingsContentOwnsHeader == false)
        XCTAssertEqual(AppSectionHeaderOwnership.pageHeaderCount(for: .statistics), 1)
        XCTAssertEqual(AppSectionHeaderOwnership.pageHeaderCount(for: .settings), 1)
        XCTAssertTrue(AppSectionHeaderOwnership.editorSheetOwnsHeader)
    }

    func testAppShellPreservesBrandAndMinimumWindowContract() {
        XCTAssertEqual(AppShellContract.brandText, "FlightLog 飞行档案")
        XCTAssertEqual(AppShellContract.minimumWidth, 720)
        XCTAssertEqual(AppShellContract.minimumHeight, 520)
        XCTAssertLessThan(AppShellContract.sidebarMinimumWidth, 240)
        XCTAssertGreaterThan(
            AppShellContract.minimumWidth - AppShellContract.sidebarMinimumWidth,
            440
        )
        XCTAssertEqual(
            AppShellContract.accessibilitySummary,
            "FlightLog 飞行档案，六个章节的飞行记录应用"
        )
    }

    func testSidebarProfileSwitcherContractKeepsNativeManagementEntry() {
        XCTAssertEqual(AppShellContract.profileSwitcherTitle, "当前用户")
        XCTAssertEqual(AppShellContract.manageProfilesTitle, "管理用户…")
        XCTAssertEqual(
            AppShellContract.profileSwitcherAccessibilityHint,
            "打开用户切换与管理菜单"
        )
        XCTAssertTrue(AppShellContract.usesNativeProfileMenu)
        XCTAssertFalse(AppShellContract.showsProfileFlightCount)
        XCTAssertTrue(AppShellContract.profileSwitcherUsesExplicitTint)
    }

    func testProfileSwitcherUsesCreamForegroundWithOrdinaryTextContrast() {
        for appearance in FlightTheme.Appearance.allCases {
            for contrast in [FlightTheme.Contrast.standard, .increased] {
                let palette = FlightTheme.palette(
                    for: appearance,
                    contrast: contrast
                )
                let style = ProfileSwitcherVisualStyle.resolve(palette: palette)

                XCTAssertEqual(style.foreground, palette.passportInk)
                XCTAssertGreaterThanOrEqual(
                    style.foreground.contrastRatio(with: style.background),
                    FlightTheme.ContrastThreshold.ordinaryText
                )
            }
        }
    }

    @MainActor
    func testProfileSwitcherRendersCreamForegroundAcrossAppearanceMatrix() throws {
        let windowSize = CGSize(
            width: AppShellContract.minimumWidth,
            height: AppShellContract.minimumHeight
        )
        let container = try makeProfileSwitcherRenderContainer()
        let defaults = UserDefaults(
            suiteName:
                "AppShellContractTests.ProfileSwitcherMatrix.\(UUID().uuidString)"
        )!
        let session = UserSession(defaults: defaults)
        session.activate(UserProfileDefaults.id)
        let commandState = AppCommandState()
        commandState.navigate(to: .overview)

        for appearance in FlightTheme.Appearance.allCases {
            for contrast in [FlightTheme.Contrast.standard, .increased] {
                let palette = FlightTheme.palette(
                    for: appearance,
                    contrast: contrast
                )
                let style = ProfileSwitcherVisualStyle.resolve(palette: palette)
                let cream = NSColor(style.foreground.color)
                    .usingColorSpace(.deviceRGB)!
                let background = NSColor(style.background.color)
                    .usingColorSpace(.deviceRGB)!
                let colorScheme: ColorScheme =
                    appearance == .dark ? .dark : .light
                let accessibilityContrast: ColorSchemeContrast =
                    contrast == .increased ? .increased : .standard

                let hosted = try hostProfileSwitcher(
                    container: container,
                    session: session,
                    commandState: commandState,
                    windowSize: windowSize,
                    colorScheme: colorScheme,
                    accessibilityContrast: accessibilityContrast
                )

                let bitmap = try XCTUnwrap(
                    hosted.host.bitmapImageRepForCachingDisplay(
                        in: hosted.host.bounds
                    )
                )
                hosted.host.cacheDisplay(in: hosted.host.bounds, to: bitmap)

                let ranges = ProfileSwitcherLayoutContract.bitmapSamplingRanges(
                    in: bitmap,
                    logicalWindowSize: windowSize
                )
                var creamMatches = 0
                var nearBlackForegroundPixels = 0
                for y in ranges.y {
                    for x in ranges.x {
                        guard
                            let color = bitmap.colorAt(x: x, y: y)?
                                .usingColorSpace(.deviceRGB),
                            color.alphaComponent > 0.5
                        else { continue }
                        if colorsAreSimilar(color, background, tolerance: 0.12) {
                            continue
                        }
                        if colorsAreSimilar(color, cream, tolerance: 0.12) {
                            creamMatches += 1
                            continue
                        }
                        if color.redComponent < 0.15
                            && color.greenComponent < 0.15
                            && color.blueComponent < 0.15
                        {
                            nearBlackForegroundPixels += 1
                        }
                    }
                }

                XCTAssertEqual(
                    nearBlackForegroundPixels,
                    0,
                    "\(appearance) \(contrast) profile switcher label "
                        + "should not render near-black text"
                )
                XCTAssertGreaterThan(
                    creamMatches,
                    8,
                    "\(appearance) \(contrast) profile switcher label "
                        + "should render cream passportInk foreground"
                )
                detachProfileSwitcherHost(hosted)
            }
        }
    }

    @MainActor
    func testProfileSwitcherUsesNativePopupControlWithoutForcingDarkAppearance()
        throws
    {
        let windowSize = CGSize(
            width: AppShellContract.minimumWidth,
            height: AppShellContract.minimumHeight
        )
        let container = try makeProfileSwitcherRenderContainer()
        let defaults = UserDefaults(
            suiteName:
                "AppShellContractTests.ProfileSwitcherNative.\(UUID().uuidString)"
        )!
        let session = UserSession(defaults: defaults)
        session.activate(UserProfileDefaults.id)
        let commandState = AppCommandState()
        commandState.navigate(to: .overview)

        let hosted = try hostProfileSwitcher(
            container: container,
            session: session,
            commandState: commandState,
            windowSize: windowSize,
            colorScheme: .light,
            accessibilityContrast: .standard
        )
        defer { detachProfileSwitcherHost(hosted) }

        let hostAppearance = hosted.host.effectiveAppearance.name
        XCTAssertTrue(
            hostAppearance == .aqua
                || hostAppearance == .accessibilityHighContrastAqua,
            "Profile switcher host should remain in the requested light "
                + "appearance family, got \(hostAppearance)"
        )
        XCTAssertFalse(
            hostAppearance == .darkAqua
                || hostAppearance == .accessibilityHighContrastDarkAqua,
            "Profile switcher host must not force dark mode"
        )

        let menuButton = try XCTUnwrap(
            findProfileSwitcherMenuButton(in: hosted.host),
            "Missing native profile switcher menu button"
        )
        XCTAssertNotNil(
            menuButton.menu,
            "Profile switcher should remain a native popup/menu control"
        )

        let switcherElements = profileSwitcherAccessibilityElements(
            in: hosted.host
        )
        XCTAssertEqual(
            switcherElements.count,
            1,
            "Profile switcher should expose one accessibility control, found "
                + "\(switcherElements.count)"
        )
        let switcher = try XCTUnwrap(
            switcherElements.first,
            "Missing profile switcher accessibility node; found "
                + "\(profileSwitcherAccessibilityLabels(in: hosted.host))"
        )
        let role = switcher.accessibilityRole()?.rawValue ?? ""
        XCTAssertTrue(
            role.contains("PopUpButton")
                || role.contains("MenuButton")
                || role.contains("Button"),
            "Profile switcher should expose a native popup/menu "
                + "control, got role \(role)"
        )
        XCTAssertEqual(
            switcher.accessibilityLabel(),
            UserProfileDefaults.displayName
        )

    }

    @MainActor
    private struct ProfileSwitcherHostedView {
        let host: NSHostingView<AnyView>
        let window: NSWindow
    }

    @MainActor
    private func hostProfileSwitcher(
        container: ModelContainer,
        session: UserSession,
        commandState: AppCommandState,
        windowSize: CGSize,
        colorScheme: ColorScheme,
        accessibilityContrast: ColorSchemeContrast
    ) throws -> ProfileSwitcherHostedView {
        let root = AnyView(
            ContentView(
                commandState: commandState
            )
            .modelContainer(container)
            .environmentObject(session)
            .preferredColorScheme(colorScheme)
            .environment(
                \.visualVerificationContrast,
                accessibilityContrast
            )
            .frame(width: windowSize.width, height: windowSize.height)
        )
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: windowSize)
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
            accessibilityContrast
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
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.35))
        host.layoutSubtreeIfNeeded()
        if #available(macOS 10.11, *) {
            NSAccessibility.post(
                element: host,
                notification: .layoutChanged
            )
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        return ProfileSwitcherHostedView(host: host, window: window)
    }

    @MainActor
    private func colorsAreSimilar(
        _ lhs: NSColor,
        _ rhs: NSColor,
        tolerance: CGFloat
    ) -> Bool {
        abs(lhs.redComponent - rhs.redComponent) < tolerance
            && abs(lhs.greenComponent - rhs.greenComponent) < tolerance
            && abs(lhs.blueComponent - rhs.blueComponent) < tolerance
    }

    @MainActor
    private func profileSwitcherAccessibilityLabels(in root: NSView) -> [String] {
        var labels: [String] = []
        visitAccessibilityElements(in: root) { element in
            if let label = element.accessibilityLabel(), !label.isEmpty {
                labels.append(label)
            }
        }
        return labels
    }

    @MainActor
    private func detachProfileSwitcherHost(_ hosted: ProfileSwitcherHostedView) {
        hosted.window.orderOut(nil)
        hosted.window.contentView = nil
    }

    @MainActor
    private func profileSwitcherAccessibilityElements(
        in root: NSView
    ) -> [NSAccessibilityProtocol] {
        var candidates: [NSAccessibilityProtocol] = []
        visitAccessibilityElements(in: root) { element in
            let label = element.accessibilityLabel() ?? ""
            let hint = element.accessibilityHelp() ?? ""
            let role = element.accessibilityRole()?.rawValue ?? ""
            if label.contains("当前用户")
                || hint == AppShellContract.profileSwitcherAccessibilityHint
                || (
                    label == UserProfileDefaults.displayName
                        && (
                            role.contains("PopUpButton")
                                || role.contains("MenuButton")
                                || role.contains("Button")
                        )
                )
            {
                candidates.append(element)
            }
        }
        return candidates
    }

    @MainActor
    private func findProfileSwitcherMenuButton(in root: NSView) -> NSButton? {
        let sidebarMaximumX = ProfileSwitcherLayoutContract.frame(
            in: root.bounds.size
        ).maxX
        var match: NSButton?
        func visit(_ view: NSView) {
            guard match == nil else { return }
            let frame = view.convert(view.bounds, to: root)
            guard frame.minX < sidebarMaximumX else { return }
            if let button = view as? NSButton, button.menu != nil {
                match = button
                return
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return match
    }

    @MainActor
    private func visitAccessibilityElements(
        in root: Any,
        visitor: (NSAccessibilityProtocol) -> Void
    ) {
        var visited = Set<ObjectIdentifier>()
        func visit(_ value: Any) {
            if let object = value as AnyObject? {
                let identifier = ObjectIdentifier(object)
                guard visited.insert(identifier).inserted else { return }
            }
            if let element = value as? NSAccessibilityProtocol {
                visitor(element)
                element.accessibilityChildren()?.forEach(visit)
                element.accessibilityContents()?.forEach(visit)
            }
            if let view = value as? NSView {
                if view.isAccessibilityElement() {
                    visit(view as NSAccessibilityProtocol)
                }
                view.subviews.forEach(visit)
            }
        }
        visit(root)
    }

    @MainActor
    private func makeProfileSwitcherRenderContainer() throws -> ModelContainer {
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

    func testChapterHeaderAllowsLongChineseTextToGrowVertically() {
        XCTAssertNil(ChapterHeaderLayoutContract.standard.fixedHeight)
        XCTAssertNil(ChapterHeaderLayoutContract.standard.titleLineLimit)
        XCTAssertNil(ChapterHeaderLayoutContract.standard.narrativeLineLimit)
        XCTAssertTrue(ChapterHeaderLayoutContract.standard.allowsVerticalGrowth)
    }

    func testSidebarSelectionSemanticColorsMeetContrastAcrossAppearanceMatrix() {
        for appearance in FlightTheme.Appearance.allCases {
            for contrast in [FlightTheme.Contrast.standard, .increased] {
                let selection = FlightTheme.palette(
                    for: appearance,
                    contrast: contrast
                ).sidebarSelection

                XCTAssertGreaterThanOrEqual(
                    selection.foreground.contrastRatio(with: selection.background),
                    FlightTheme.ContrastThreshold.ordinaryText,
                    "\(appearance) \(contrast) selected text"
                )
                XCTAssertGreaterThanOrEqual(
                    selection.icon.contrastRatio(with: selection.background),
                    FlightTheme.ContrastThreshold.largeText,
                    "\(appearance) \(contrast) selected icon"
                )
                XCTAssertGreaterThanOrEqual(
                    selection.indicator.contrastRatio(with: selection.background),
                    FlightTheme.ContrastThreshold.largeText,
                    "\(appearance) \(contrast) selected indicator"
                )
            }
        }
    }

    func testRouteMapCompactPolicyFitsWithinMinimumWindowHeightBudget() {
        let availableHeight = AppLayoutContract.routeMapContentHeight(
            windowHeight: 520
        )
        let policy = RouteMapLayout.verticalPolicy(
            availableHeight: availableHeight
        )

        XCTAssertEqual(policy.density, .compact)
        XCTAssertGreaterThanOrEqual(
            policy.mapMinimumHeight,
            RouteMapLayout.minimumUsableMapHeight
        )
        XCTAssertGreaterThanOrEqual(
            policy.listMinimumHeight,
            RouteMapLayout.minimumUsableListHeight
        )
        XCTAssertLessThanOrEqual(policy.requiredHeight, availableHeight)
        XCTAssertLessThanOrEqual(
            AppLayoutContract.routeMapReservedHeight + policy.requiredHeight,
            520
        )
    }

    func testRouteMapStandardPolicyIsRetainedForTallWindows() {
        let availableHeight = AppLayoutContract.routeMapContentHeight(
            windowHeight: 900
        )
        let policy = RouteMapLayout.verticalPolicy(
            availableHeight: availableHeight
        )

        XCTAssertEqual(policy.density, .standard)
        XCTAssertEqual(policy.mapMinimumHeight, 250)
        XCTAssertEqual(policy.listMinimumHeight, 240)
        XCTAssertLessThanOrEqual(policy.requiredHeight, availableHeight)
        XCTAssertLessThanOrEqual(
            AppLayoutContract.routeMapReservedHeight + policy.requiredHeight,
            900
        )
    }
}
