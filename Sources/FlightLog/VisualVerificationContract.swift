import Foundation
import SwiftUI

private struct VisualVerificationContrastKey: EnvironmentKey {
    static let defaultValue: ColorSchemeContrast? = nil
}

private struct VisualVerificationReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var visualVerificationContrast: ColorSchemeContrast? {
        get { self[VisualVerificationContrastKey.self] }
        set { self[VisualVerificationContrastKey.self] = newValue }
    }

    var visualVerificationReduceMotion: Bool? {
        get { self[VisualVerificationReduceMotionKey.self] }
        set { self[VisualVerificationReduceMotionKey.self] = newValue }
    }
}

@propertyWrapper
struct FlightLogAccessibilityContrast: DynamicProperty {
    @Environment(\.colorSchemeContrast) private var systemValue
    @Environment(\.visualVerificationContrast) private var overrideValue

    var wrappedValue: ColorSchemeContrast {
        overrideValue ?? systemValue
    }
}

@propertyWrapper
struct FlightLogReduceMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var systemValue
    @Environment(\.visualVerificationReduceMotion) private var overrideValue

    var wrappedValue: Bool {
        overrideValue ?? systemValue
    }
}

enum VisualVerificationContract {
    struct TargetSize: Hashable, Sendable {
        let width: Int
        let height: Int
    }

    enum Appearance: String, CaseIterable, Hashable, Sendable {
        case light
        case dark
    }

    enum Contrast: String, CaseIterable, Hashable, Sendable {
        case standard
        case increased
    }

    enum Motion: String, CaseIterable, Hashable, Sendable {
        case normal
        case reduced
    }

    struct MatrixCase: Hashable, Sendable {
        let size: TargetSize
        let appearance: Appearance
        let contrast: Contrast
        let motion: Motion
    }

    enum Scenario: String, CaseIterable, Hashable, Sendable {
        case appShell
        case overview
        case flightArchive
        case selectedRouteArchive
        case statistics
        case editor
        case settings
        case profileManagement
        case comparison
        case comparisonMap
        case comparisonSelectedRoute
    }

    struct ScenarioContract: Equatable, Sendable {
        let scenario: Scenario
        let isScrollable: Bool
        let requiredSemantics: [String]
    }

    struct AccessibilityContract: Equatable, Sendable {
        let navigationShortcuts: [String]
        let newFlightShortcut: String
        let searchShortcut: String
        let emptyFlightState: String
        let requiredControlRoles: Set<String>
        let requiredCoreFields: Set<String>
        let yearbookHoverText: String
        let statisticsHoverText: String
    }

    struct MotionContract: Equatable, Sendable {
        let horizontalOffset: Double
        let verticalOffset: Double
        let repeatCount: Int
        let animationDuration: Double?
    }

    static let targetSizes = [
        TargetSize(width: 720, height: 520),
        TargetSize(width: 1_080, height: 720),
        TargetSize(width: 1_440, height: 900),
    ]

    static let matrix: [MatrixCase] = targetSizes.flatMap { size in
        Appearance.allCases.flatMap { appearance in
            Contrast.allCases.flatMap { contrast in
                Motion.allCases.map { motion in
                    MatrixCase(
                        size: size,
                        appearance: appearance,
                        contrast: contrast,
                        motion: motion
                    )
                }
            }
        }
    }

    static let scenarios = Scenario.allCases

    static let scenarioContracts = [
        ScenarioContract(
            scenario: .appShell,
            isScrollable: true,
            requiredSemantics: ["FlightLog 飞行档案", "概览", "CHAPTER 01"]
        ),
        ScenarioContract(
            scenario: .overview,
            isScrollable: true,
            requiredSemantics: ["我的飞行护照", "飞行印章", "旅行年份册", "近期航班"]
        ),
        ScenarioContract(
            scenario: .flightArchive,
            isScrollable: true,
            requiredSemantics: ["航班档案", "旅程时间线", "航线档案"]
        ),
        ScenarioContract(
            scenario: .selectedRouteArchive,
            isScrollable: true,
            requiredSemantics: ["航线航图", "航线档案", "包含航班"]
        ),
        ScenarioContract(
            scenario: .statistics,
            isScrollable: true,
            requiredSemantics: ["统计", "年份", "趋势", "排行"]
        ),
        ScenarioContract(
            scenario: .editor,
            isScrollable: true,
            requiredSemantics: ["航班身份", "航线时间", "旅行备注"]
        ),
        ScenarioContract(
            scenario: .settings,
            isScrollable: true,
            requiredSemantics: ["联网航班资料", "数据档案", "危险区域"]
        ),
        ScenarioContract(
            scenario: .profileManagement,
            isScrollable: true,
            requiredSemantics: ["管理用户", "新建用户", "用户档案", "显示颜色"]
        ),
        ScenarioContract(
            scenario: .comparison,
            isScrollable: true,
            requiredSemantics: ["对比", "选择同行者", "我们共同去过", "年度同行趋势"]
        ),
        ScenarioContract(
            scenario: .comparisonMap,
            isScrollable: true,
            requiredSemantics: ["同行航线地图", "共同航线", "包含航班", "地图图例"]
        ),
        ScenarioContract(
            scenario: .comparisonSelectedRoute,
            isScrollable: true,
            requiredSemantics: ["同行航线地图", "总计", "次数", "里程", "包含航班"]
        ),
    ]

    static let accessibility = AccessibilityContract(
        navigationShortcuts: AppSection.allCases.map {
            "⌘\($0.keyboardShortcutCharacter)"
        },
        newFlightShortcut: "⌘N",
        searchShortcut: "⌘F",
        emptyFlightState: FlightBrowserPresentation.emptyRecordsTitle,
        requiredControlRoles: ["Button", "Picker"],
        requiredCoreFields: [
            "航班号", "日期", "航司", "出发机场", "到达机场", "当地时间", "时长",
        ],
        yearbookHoverText: "2026 年：2 次航班",
        statisticsHoverText: "2026 年：2 次航班"
    )

    static func motionPolicy(reduceMotion: Bool) -> MotionContract {
        let row = FlightRowSelectionLayoutPolicy.resolve(
            isSelected: true,
            reduceMotion: reduceMotion
        )
        let route = RouteMapVisualPolicy.motion(
            hasAppeared: false,
            isHovered: true,
            reduceMotion: reduceMotion
        )
        return MotionContract(
            horizontalOffset: row.horizontalOffset,
            verticalOffset: route.verticalOffset,
            repeatCount: route.repeatCount,
            animationDuration: reduceMotion
                ? nil
                : max(
                    row.animationDuration ?? 0,
                    route.animationDuration ?? 0
                )
        )
    }
}
