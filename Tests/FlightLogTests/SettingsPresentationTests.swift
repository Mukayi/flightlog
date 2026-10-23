import XCTest
@testable import FlightLog

final class SettingsPresentationTests: XCTestCase {
    func testSectionsKeepStableOrderAndContainEverySettingsAction() {
        let sections = SettingsPresentation.sections

        XCTAssertEqual(
            sections.map(\.id),
            [.onlineFlightData, .displayPreferences, .dataArchive, .dangerZone]
        )
        XCTAssertEqual(
            sections.map(\.title),
            ["联网航班资料", "显示偏好", "数据档案", "危险区域"]
        )
        XCTAssertEqual(
            Set(sections.flatMap(\.actions)),
            Set(SettingsAction.allCases)
        )
    }

    func testActionsBelongToExpectedSectionsAndHaveStableRiskLevels() {
        XCTAssertEqual(
            SettingsPresentation.section(for: .saveAPIKey),
            .onlineFlightData
        )
        XCTAssertEqual(
            SettingsPresentation.section(for: .distanceUnit),
            .displayPreferences
        )
        for action in [
            SettingsAction.exportCSV,
            .exportJSON,
            .importCSV,
            .mergeJSON,
            .replaceJSON,
            .generateSample,
            .inspectLegacy,
            .copyImportReport,
        ] {
            XCTAssertEqual(
                SettingsPresentation.section(for: action),
                .dataArchive
            )
        }
        XCTAssertEqual(
            SettingsPresentation.section(for: .clearAllData),
            .dangerZone
        )

        XCTAssertEqual(SettingsAction.deleteAPIKey.risk, .destructive)
        XCTAssertEqual(SettingsAction.replaceJSON.risk, .destructive)
        XCTAssertEqual(SettingsAction.clearAllData.risk, .destructive)
        XCTAssertEqual(SettingsAction.mergeJSON.risk, .standard)
        XCTAssertEqual(SettingsAction.generateSample.risk, .standard)
    }

    func testDestructiveConfirmationCopyIsExplicitAndStable() {
        XCTAssertEqual(
            SettingsPresentation.replaceConfirmation.warning,
            "将删除当前数据并恢复备份；操作无法撤销。"
        )
        XCTAssertEqual(
            SettingsPresentation.replaceConfirmation.confirmButtonTitle,
            "确认替换"
        )
        XCTAssertEqual(
            SettingsPresentation.clearConfirmation(recordCount: 12).message,
            "将永久删除当前 12 条航班记录。请先导出 JSON 完整备份；此操作无法撤销。"
        )
        XCTAssertEqual(
            SettingsPresentation.clearConfirmation(recordCount: 12)
                .confirmButtonTitle,
            "永久清空"
        )
    }

    func testAPIKeyLabelsCommunicatePrivacyWithoutExposingSecret() {
        let secret = "super-secret-api-key"
        let saved = SettingsPresentation.apiKeyStatus(hasSavedKey: true)
        let missing = SettingsPresentation.apiKeyStatus(hasSavedKey: false)

        XCTAssertEqual(saved.accessibilityLabel, "API key 状态：已安全保存，不会回显")
        XCTAssertEqual(missing.accessibilityLabel, "API key 状态：尚未保存")
        XCTAssertFalse(saved.visibleText.contains(secret))
        XCTAssertFalse(saved.accessibilityLabel.contains(secret))
        XCTAssertFalse(SettingsPresentation.apiKeyFieldAccessibilityLabel.contains(secret))
    }

    func testImportExportLegacySampleAndClearRemainReachable() {
        let reachable = Set(SettingsPresentation.sections.flatMap(\.actions))

        XCTAssertTrue(reachable.isSuperset(of: [
            .exportCSV,
            .exportJSON,
            .importCSV,
            .mergeJSON,
            .replaceJSON,
            .inspectLegacy,
            .generateSample,
            .copyImportReport,
            .clearAllData,
        ]))
    }

    func testImportConfirmationGateRejectsRapidDuplicateSubmission() {
        var gate = ImportConfirmationSubmissionGate()
        var launchedOperations = 0

        if gate.begin() {
            launchedOperations += 1
        }
        if gate.begin() {
            launchedOperations += 1
        }

        XCTAssertEqual(launchedOperations, 1)
        XCTAssertTrue(gate.isWorking)

        gate.finish()
        XCTAssertFalse(gate.isWorking)
        XCTAssertTrue(gate.begin())
    }

    func testImportConfirmationControlsDisableBothActionsWhileWorking() {
        let idle = ImportConfirmationControlsPresentation(isWorking: false)
        XCTAssertFalse(idle.disablesCancel)
        XCTAssertFalse(idle.disablesConfirm)
        XCTAssertFalse(idle.showsProgress)

        let working = ImportConfirmationControlsPresentation(isWorking: true)
        XCTAssertTrue(working.disablesCancel)
        XCTAssertTrue(working.disablesConfirm)
        XCTAssertTrue(working.showsProgress)
        XCTAssertEqual(working.statusText, "正在应用备份…")
    }
}
