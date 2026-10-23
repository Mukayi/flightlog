import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case flights
    case map
    case statistics
    case settings
    case comparison

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "概览"
        case .flights: "航班"
        case .map: "地图"
        case .statistics: "统计"
        case .settings: "设置"
        case .comparison: "对比"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .flights: "airplane"
        case .map: "map"
        case .statistics: "chart.bar"
        case .settings: "gearshape"
        case .comparison: "person.2.wave.2"
        }
    }

    var keyboardShortcutCharacter: Character {
        switch self {
        case .overview: "1"
        case .flights: "2"
        case .map: "3"
        case .statistics: "4"
        case .settings: "5"
        case .comparison: "6"
        }
    }

    var eyebrow: String {
        switch self {
        case .overview: "CHAPTER 01"
        case .flights: "CHAPTER 02"
        case .map: "CHAPTER 03"
        case .statistics: "CHAPTER 04"
        case .settings: "CHAPTER 05"
        case .comparison: "CHAPTER 06"
        }
    }

    var narrative: String {
        switch self {
        case .overview:
            "从累计里程、年度变化与近期航班，重读你的飞行轨迹。"
        case .flights:
            "整理每一次起降，让航班细节成为可检索的旅程档案。"
        case .map:
            "沿大圆航线回望跨越的城市、机场与远方。"
        case .statistics:
            "用时间、距离与目的地，读懂飞行生活的轮廓。"
        case .settings:
            "管理资料来源、备份与导入，让档案长久而可靠。"
        case .comparison:
            "把同行者的航迹并排展开，寻找共同抵达的航班、航线与远方。"
        }
    }

    var accessibilitySummary: String {
        "\(title)，\(narrative)"
    }
}

enum AppSectionHeaderOwnership {
    static let shellOwnedSections = AppSection.allCases
    static let statisticsContentOwnsHeader = false
    static let settingsContentOwnsHeader = false
    static let editorSheetOwnsHeader = true

    static func pageHeaderCount(for section: AppSection) -> Int {
        shellOwnedSections.contains(section) ? 1 : 0
    }
}
