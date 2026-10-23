import SwiftData
import SwiftUI

@main
struct FlightLogApp: App {
    @StateObject private var commandState = AppCommandState()
    @StateObject private var userSession = UserSession()
    private let persistenceResult: Result<PersistenceController, Error>

    init() {
        persistenceResult = Result {
            try PersistenceController()
        }
    }

    var body: some Scene {
        Window("航班日志", id: "main") {
            switch persistenceResult {
            case .success(let persistence):
                FlightLogRootView(
                    persistence: persistence,
                    commandState: commandState
                )
                .modelContainer(persistence.container)
                .environmentObject(userSession)
            case .failure(let error):
                PersistenceRecoveryView(
                    content: PersistenceRecoveryContent(error: error),
                    storeURL: PersistenceController.defaultStoreURL
                )
            }
        }
        .defaultSize(width: 1_080, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新增航班") {
                    commandState.requestNewFlight()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("前往") {
                ForEach(AppSection.allCases) { section in
                    Button(section.title) {
                        commandState.navigate(to: section)
                    }
                    .keyboardShortcut(
                        KeyEquivalent(section.keyboardShortcutCharacter),
                        modifiers: .command
                    )
                }
            }

            CommandMenu("查找") {
                Button("搜索航班") {
                    commandState.requestFlightSearch()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}

private struct FlightLogRootView: View {
    @EnvironmentObject private var userSession: UserSession
    let persistence: PersistenceController
    @ObservedObject var commandState: AppCommandState

    @State private var didInspectLegacyStore = false
    @State private var legacyCandidate: LegacyFlightImportCandidate?
    @State private var migrationNotice: String?
    @State private var migrationError: String?

    var body: some View {
        ContentView(commandState: commandState)
            .onAppear {
                inspectLegacyStoreIfNeeded()
            }
            .alert(
                LegacyImportPresentation(
                    recordCount: legacyCandidate?.records.count ?? 0
                ).title,
                isPresented: Binding(
                    get: { legacyCandidate != nil },
                    set: { isPresented in
                        if !isPresented {
                            legacyCandidate = nil
                        }
                    }
                )
            ) {
                Button("暂不导入", role: .cancel) {
                    legacyCandidate = nil
                }
                Button("导入旧数据") {
                    importLegacyStore()
                }
            } message: {
                Text(
                    LegacyImportPresentation(
                        recordCount: legacyCandidate?.records.count ?? 0
                    ).message
                )
            }
            .alert(
                "旧数据迁移",
                isPresented: Binding(
                    get: { migrationNotice != nil },
                    set: { isPresented in
                        if !isPresented {
                            migrationNotice = nil
                        }
                    }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(migrationNotice ?? "")
            }
            .alert(
                "旧数据导入失败",
                isPresented: Binding(
                    get: { migrationError != nil },
                    set: { isPresented in
                        if !isPresented {
                            migrationError = nil
                        }
                    }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(migrationError ?? "")
            }
    }

    private func inspectLegacyStoreIfNeeded() {
        guard !didInspectLegacyStore else { return }
        didInspectLegacyStore = true
        Task {
            do {
                legacyCandidate = try await LegacyStoreInspectionCoordinator()
                    .inspect(
                        PersistenceController
                            .defaultLegacyMigrationConfiguration
                    )
                if
                    legacyCandidate == nil,
                    let state = try? LegacyStoreMigrationService.currentState(
                        PersistenceController
                            .defaultLegacyMigrationConfiguration
                    ),
                    state.status == .incompatible || state.status == .failed
                {
                    migrationError = state.message
                        ?? "旧数据库无法自动迁移，请在设置中重试或使用旧版 JSON 导入。"
                }
            } catch {
                legacyCandidate = nil
                migrationError = "旧数据库检查失败：\(error.localizedDescription)"
            }
        }
    }

    private func importLegacyStore() {
        guard let legacyCandidate else { return }
        let normalizedCount = legacyCandidate.normalizedFlightDateCount
        do {
            let report = try LegacyStoreMigrationService.importCandidate(
                legacyCandidate,
                to: persistence.container.mainContext,
                targetProfileID: userSession.activeProfileID
                    ?? UserProfileDefaults.id,
                configuration:
                    PersistenceController.defaultLegacyMigrationConfiguration
            )
            self.legacyCandidate = nil
            let normalization = normalizedCount > 0
                ? "；已按出发当地日期规范化 \(normalizedCount) 条 flightDate"
                : ""
            migrationNotice = "旧数据导入完成：\(report.summary)\(normalization)。原数据库和备份均已保留。"
        } catch {
            self.legacyCandidate = nil
            migrationError = error.localizedDescription
        }
    }
}

private struct PersistenceRecoveryView: View {
    let content: PersistenceRecoveryContent
    let storeURL: URL

    var body: some View {
        ContentUnavailableView {
            Label(
                content.title,
                systemImage: "externaldrive.badge.exclamationmark"
            )
        } description: {
            VStack(spacing: 10) {
                Text(content.message)
                Text(content.recoverySuggestion)
                Text(storeURL.path)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 620)
        }
        .padding(32)
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }
}
