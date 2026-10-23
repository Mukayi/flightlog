import Foundation

enum SettingsSectionID: String, CaseIterable, Equatable, Sendable {
    case onlineFlightData
    case displayPreferences
    case dataArchive
    case dangerZone
}

enum SettingsRiskLevel: Equatable, Sendable {
    case standard
    case destructive
}

enum SettingsAction: String, CaseIterable, Equatable, Hashable, Sendable {
    case saveAPIKey
    case deleteAPIKey
    case distanceUnit
    case generateSample
    case inspectLegacy
    case exportCSV
    case exportJSON
    case exportCurrentProfile
    case exportAllProfiles
    case importCSV
    case mergeJSON
    case replaceJSON
    case mergeArchive
    case replaceTargetArchive
    case fullRestoreArchive
    case copyImportReport
    case clearAllData

    var risk: SettingsRiskLevel {
        switch self {
        case .deleteAPIKey, .replaceJSON, .replaceTargetArchive,
             .fullRestoreArchive, .clearAllData:
            .destructive
        default:
            .standard
        }
    }
}

struct SettingsSectionPresentation: Identifiable, Equatable, Sendable {
    let id: SettingsSectionID
    let title: String
    let subtitle: String
    let systemImage: String
    let actions: [SettingsAction]
}

struct SettingsConfirmationPresentation: Equatable, Sendable {
    let title: String
    let message: String
    let warning: String
    let confirmButtonTitle: String
}

struct APIKeyStatusPresentation: Equatable, Sendable {
    let visibleText: String
    let accessibilityLabel: String
    let systemImage: String
}

struct ImportConfirmationSubmissionGate: Equatable, Sendable {
    private(set) var isWorking = false

    mutating func begin() -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        return true
    }

    mutating func finish() {
        isWorking = false
    }
}

struct ImportConfirmationControlsPresentation: Equatable, Sendable {
    let disablesCancel: Bool
    let disablesConfirm: Bool
    let showsProgress: Bool
    let statusText: String?

    init(isWorking: Bool) {
        disablesCancel = isWorking
        disablesConfirm = isWorking
        showsProgress = isWorking
        statusText = isWorking ? "正在应用备份…" : nil
    }
}

enum SettingsPresentation {
    static let apiKeyFieldAccessibilityLabel =
        "RapidAPI API key，安全输入，内容不会回显"

    static let sections: [SettingsSectionPresentation] = [
        SettingsSectionPresentation(
            id: .onlineFlightData,
            title: "联网航班资料",
            subtitle: "管理航班查询凭据与联网数据使用说明。",
            systemImage: "network",
            actions: [.saveAPIKey, .deleteAPIKey]
        ),
        SettingsSectionPresentation(
            id: .displayPreferences,
            title: "显示偏好",
            subtitle: "选择概览与统计中使用的距离单位。",
            systemImage: "textformat.size",
            actions: [.distanceUnit]
        ),
        SettingsSectionPresentation(
            id: .dataArchive,
            title: "数据档案",
            subtitle: "生成样例、迁移旧数据，并导入、导出或恢复飞行档案。",
            systemImage: "archivebox",
            actions: [
                .generateSample,
                .inspectLegacy,
                .exportCSV,
                .exportJSON,
                .exportCurrentProfile,
                .exportAllProfiles,
                .importCSV,
                .mergeJSON,
                .replaceJSON,
                .mergeArchive,
                .replaceTargetArchive,
                .fullRestoreArchive,
                .copyImportReport,
            ]
        ),
        SettingsSectionPresentation(
            id: .dangerZone,
            title: "危险区域",
            subtitle: "永久删除操作集中于此，并始终要求原生确认。",
            systemImage: "exclamationmark.triangle",
            actions: [.clearAllData]
        ),
    ]

    static let replaceConfirmation = SettingsConfirmationPresentation(
        title: "恢复 JSON（替换）",
        message: "完整验证备份后，将以备份内容替换当前航班记录。",
        warning: "将删除当前数据并恢复备份；操作无法撤销。",
        confirmButtonTitle: "确认替换"
    )

    static let fullRestoreConfirmation = SettingsConfirmationPresentation(
        title: "完整恢复所有档案？",
        message: "仅接受已完整验证的 schema v2 全部用户备份，并在同一事务中替换全部用户和航班。",
        warning: "将删除并替换所有用户档案与航班；此高风险操作无法撤销。",
        confirmButtonTitle: "确认完整恢复所有档案"
    )

    static func section(for action: SettingsAction) -> SettingsSectionID? {
        sections.first { $0.actions.contains(action) }?.id
    }

    static func section(
        _ id: SettingsSectionID
    ) -> SettingsSectionPresentation {
        sections.first { $0.id == id }!
    }

    static func apiKeyStatus(
        hasSavedKey: Bool
    ) -> APIKeyStatusPresentation {
        if hasSavedKey {
            APIKeyStatusPresentation(
                visibleText: "已安全保存 API key（不会回显）",
                accessibilityLabel: "API key 状态：已安全保存，不会回显",
                systemImage: "key.fill"
            )
        } else {
            APIKeyStatusPresentation(
                visibleText: "尚未保存 API key",
                accessibilityLabel: "API key 状态：尚未保存",
                systemImage: "key"
            )
        }
    }

    static func clearConfirmation(
        recordCount: Int
    ) -> SettingsConfirmationPresentation {
        SettingsConfirmationPresentation(
            title: "清空全部航班数据？",
            message: "将永久删除当前 \(recordCount) 条航班记录。请先导出 JSON 完整备份；此操作无法撤销。",
            warning: "永久删除全部航班记录，且无法撤销。",
            confirmButtonTitle: "永久清空"
        )
    }
}
