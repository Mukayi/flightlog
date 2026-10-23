import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast
    @Query
    private var records: [FlightRecord]
    @Query(sort: \UserProfile.sortOrder)
    private var profiles: [UserProfile]

    let profileID: UUID
    let profileDisplayName: String
    private let mountID = UUID()
    let repository: AirportRepository
    private let userSession: UserSession?

    @State private var showingImporter = false
    @State private var importAction = ImportAction.csv
    @State private var showingExporter = false
    @State private var exportDocument: FlightLogFileDocument?
    @State private var exportContentType = UTType.json
    @State private var exportFilename = "flightlog-backup"
    @State private var importConfirmation: ImportConfirmationState?
    @State private var currentClearPlan: FlightDataClearPlan?
    @State private var allClearPlan: FlightDataClearPlan?
    @State private var showingCurrentClearConfirmation = false
    @State private var showingAllClearConfirmation = false
    @State private var importReport: FlightImportReport?
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var importSubmissionGate = ImportConfirmationSubmissionGate()
    @State private var importCreatesProfile = false
    @State private var selectedImportTargetID: UUID?
    @State private var newImportProfileID = UUID()
    @State private var newImportProfileName = ""
    @State private var newImportProfileColor = "blue"
    @State private var importPreparationTask: Task<Void, Never>?
    @State private var importPreparationID: UUID?
    @State private var legacyCandidate: LegacyFlightImportCandidate?
    @State private var legacyStateMessage: String?
    @State private var rapidAPIKey = ""
    @State private var hasRapidAPIKey = false
    @State private var keyStatusMessage: String?
    @AppStorage("statistics.distanceUnit")
    private var distanceUnit: DistanceUnit = .kilometers
    private let apiKeyStore: any APIKeyStore = KeychainStore()

    init(
        profileID: UUID = UserProfileDefaults.id,
        profileDisplayName: String = UserProfileDefaults.displayName,
        repository: AirportRepository,
        userSession: UserSession? = nil
    ) {
        self.profileID = profileID
        self.profileDisplayName = profileDisplayName
        self.repository = repository
        self.userSession = userSession
        let ownerID: UUID? = profileID
        _records = Query(
            filter: #Predicate { $0.ownerProfileID == ownerID },
            sort: \.flightDate,
            order: .reverse
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                flightLookupSection
                displayPreferencesSection
                dataArchiveSection
                dangerSection
                if isWorking {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在后台处理文件…")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .accessibilityLabel("状态：\(statusMessage)")
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(28)
            .disabled(isWorking)
        }
        .onAppear {
            reportProfileScope()
            refreshAPIKeyStatus()
        }
        .onChange(of: records.map(\.id)) {
            reportProfileScope()
        }
        .onChange(of: profileID) {
            cancelImportPreparation()
        }
        .onDisappear {
            cancelImportPreparation()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: importAction.allowedContentTypes
        ) { result in
            handleImportResult(result)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            handleExportResult(result)
        }
        .sheet(item: $importConfirmation) { state in
            ImportConfirmationSheet(
                state: state,
                localProfiles: profiles.map(UserProfileBackupDTO.init),
                isWorking: isWorking,
                onCancel: {
                    importConfirmation = nil
                },
                onConfirm: { mappingPlan in
                    confirmImport(state, mappingPlan: mappingPlan)
                }
            )
        }
        .alert("清空“\(profileDisplayName)”的航班？", isPresented: $showingCurrentClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空当前用户航班", role: .destructive) {
                clearCurrentProfileRecords()
            }
        } message: {
            Text("将永久删除“\(profileDisplayName)”的 \(currentClearPlan?.recordCount ?? records.count) 条航班，不影响其他用户。")
        }
        .alert("清空所有用户的航班？", isPresented: $showingAllClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认清空所有用户航班", role: .destructive) {
                clearAllProfileRecords()
            }
        } message: {
            Text("将永久删除所有用户共 \(allClearPlan?.recordCount ?? 0) 条航班，但保留全部用户档案。此操作无法撤销。")
        }
        .alert(
            "发现旧版 FlightLog 数据",
            isPresented: Binding(
                get: { legacyCandidate != nil },
                set: { if !$0 { legacyCandidate = nil } }
            )
        ) {
            Button("暂不导入", role: .cancel) { legacyCandidate = nil }
            Button("导入旧数据") { importLegacyCandidate() }
        } message: {
            Text(
                LegacyImportPresentation(
                    recordCount: legacyCandidate?.records.count ?? 0
                ).message
            )
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        errorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "发生未知错误。")
        }
    }

    private var legacyMigrationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Button("重新检查旧数据库") {
                    retryLegacyInspection()
                }
                if let legacyStateMessage {
                    Text(legacyStateMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("旧数据迁移", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private func retryLegacyInspection() {
        isWorking = true
        legacyStateMessage = "正在后台检查旧数据库…"
        Task {
            defer { isWorking = false }
            do {
                legacyCandidate = try await LegacyStoreInspectionCoordinator()
                    .inspect(
                        PersistenceController
                            .defaultLegacyMigrationConfiguration,
                        forceRetry: true
                    )
                if legacyCandidate == nil {
                    legacyStateMessage =
                        try LegacyStoreMigrationService.currentState(
                            PersistenceController
                                .defaultLegacyMigrationConfiguration
                        )?.message ?? "未发现可导入的旧数据。"
                }
            } catch {
                errorMessage = "旧数据库检查失败：\(error.localizedDescription)"
            }
        }
    }

    private func importLegacyCandidate() {
        guard let candidate = legacyCandidate else { return }
        do {
            let report = try LegacyStoreMigrationService.importCandidate(
                candidate,
                to: modelContext,
                targetProfileID: profileID,
                configuration:
                    PersistenceController.defaultLegacyMigrationConfiguration
            )
            legacyCandidate = nil
            legacyStateMessage = "旧数据导入完成：\(report.summary)。"
        } catch {
            legacyCandidate = nil
            errorMessage = "旧数据导入失败：\(error.localizedDescription)"
        }
    }

    private var dataSummary: some View {
        GroupBox {
            LabeledContent("当前航班记录") {
                Text("\(records.count) 条")
                    .fontWeight(.semibold)
            }
            Text("JSON 是包含机场快照、记录 ID 和时间戳的完整备份；CSV 适合在表格软件中查看和编辑常用字段。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("数据", systemImage: "externaldrive")
        }
    }

    private var displayPreferencesSection: some View {
        PassportSurface(.paper) {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeading(.displayPreferences)
                Divider()
                Picker("距离单位", selection: $distanceUnit) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text("\(unit.title)（\(unit.rawValue)）").tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .accessibilityHint("更改概览与统计章节显示的距离单位")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private var dataArchiveSection: some View {
        PassportSurface(.paper) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeading(.dataArchive)
                Divider()
                dataSummary
                sampleDataSection
                legacyMigrationSection
                exportSection
                importSection
                if let importReport {
                    ImportReportView(
                        report: importReport,
                        onCopy: copyImportReport
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private var flightLookupSection: some View {
        let status = SettingsPresentation.apiKeyStatus(
            hasSavedKey: hasRapidAPIKey
        )
        return PassportSurface(.paper) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeading(.onlineFlightData)
                Divider()
                SecureField("RapidAPI API key", text: $rapidAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 520)
                    .accessibilityLabel(
                        SettingsPresentation.apiKeyFieldAccessibilityLabel
                    )

                ViewThatFits(in: .horizontal) {
                    HStack {
                        apiKeyActionControls
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        apiKeyActionControls
                    }
                }

                Label(
                    status.visibleText,
                    systemImage: status.systemImage
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel(status.accessibilityLabel)
                if let keyStatusMessage {
                    Text(keyStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(
                    "查询会把航班号和当地起飞日期发送给 AeroDataBox/RapidAPI。请求受所选 RapidAPI 套餐的配额、计费和数据保留政策约束；请在服务商页面确认当前条款。API key 仅存于本机钥匙串，不写入偏好设置、日志、FlightLog 备份或源码。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    @ViewBuilder
    private var apiKeyActionControls: some View {
        Button("保存 API key") {
            saveAPIKey()
        }
        .buttonStyle(.borderedProminent)
        .disabled(
            rapidAPIKey
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        )
        Button("删除 API key", role: .destructive) {
            deleteAPIKey()
        }
        .disabled(!hasRapidAPIKey)
        Link(
            "在 RapidAPI 注册 AeroDataBox",
            destination: URL(
                string: "https://rapidapi.com/aedbx-aedbx/api/aerodatabox"
            )!
        )
    }

    private func refreshAPIKeyStatus() {
        do {
            hasRapidAPIKey = try apiKeyStore.load()?.isEmpty == false
        } catch {
            hasRapidAPIKey = false
            keyStatusMessage = error.localizedDescription
        }
    }

    private func saveAPIKey() {
        do {
            try apiKeyStore.save(rapidAPIKey)
            rapidAPIKey = ""
            hasRapidAPIKey = true
            keyStatusMessage = "API key 已保存到当前用户的 macOS 钥匙串。"
        } catch {
            keyStatusMessage = error.localizedDescription
        }
    }

    private func deleteAPIKey() {
        do {
            try apiKeyStore.delete()
            rapidAPIKey = ""
            hasRapidAPIKey = false
            keyStatusMessage = "API key 已从钥匙串删除。"
        } catch {
            keyStatusMessage = error.localizedDescription
        }
    }

    private var sampleDataSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    generateSampleData()
                } label: {
                    Label("生成示例数据", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)

                Text("添加 24 条可重复样例，覆盖多个年份、国内与国际航线以及多个航司和机场；已存在相同业务键的航班会跳过。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("快速体验", systemImage: "sparkles")
        }
    }

    private var exportSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 180), alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    Button {
                        beginExport(.csv)
                    } label: {
                        Label("导出 CSV", systemImage: "tablecells")
                    }

                    Button {
                        beginExport(.currentJSON)
                    } label: {
                        Label(
                            "导出当前用户",
                            systemImage: "archivebox"
                        )
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        beginExport(.allJSON)
                    } label: {
                        Label(
                            "导出全部用户",
                            systemImage: "person.2.badge.gearshape"
                        )
                    }
                }
                Text("系统保存面板会让你选择文件名和保存位置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("导出", systemImage: "square.and.arrow.up")
        }
    }

    private var importSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker(
                    "导入目标",
                    selection: Binding(
                        get: { selectedImportTargetID ?? profileID },
                        set: { selectedImportTargetID = $0 }
                    )
                ) {
                    ForEach(profiles) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .disabled(importCreatesProfile)

                Toggle("新建用户作为导入目标", isOn: $importCreatesProfile)
                if importCreatesProfile {
                    TextField("新用户昵称", text: $newImportProfileName)
                        .textFieldStyle(.roundedBorder)
                    Picker("新用户颜色", selection: $newImportProfileColor) {
                        ForEach(
                            ["blue", "orange", "green", "purple", "pink"],
                            id: \.self
                        ) { color in
                            Text(color).tag(color)
                        }
                    }
                }
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 180), alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    Button {
                        beginImport(.csv)
                    } label: {
                        Label("导入 CSV", systemImage: "tablecells")
                    }

                    Button {
                        beginImport(.jsonMerge)
                    } label: {
                        Label("合并到档案", systemImage: "arrow.triangle.merge")
                    }

                    Button(role: .destructive) {
                        beginImport(.jsonReplace)
                    } label: {
                        Label(
                            "替换目标档案",
                            systemImage: "arrow.counterclockwise"
                        )
                    }

                    Button(role: .destructive) {
                        beginImport(.jsonFullRestore)
                    } label: {
                        Label(
                            "完整恢复所有档案",
                            systemImage: "exclamationmark.arrow.triangle.2.circlepath"
                        )
                    }
                }
                Text("普通导入默认使用“合并到档案”或“替换目标档案”；“完整恢复所有档案”仅用于自己的 schema v2 全量备份，并会再次危险确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("导入与恢复", systemImage: "square.and.arrow.down")
        }
    }

    private var dangerSection: some View {
        PassportSurface(.archiveCard) {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(.dangerZone)
                Divider()
                Button(
                    "清空当前用户航班（\(profileDisplayName) · \(records.count) 条）",
                    role: .destructive
                ) {
                    prepareCurrentClear()
                }
                .disabled(records.isEmpty)

                Button("清空所有用户的航班", role: .destructive) {
                    prepareAllClear()
                }

                Text("两种清空操作都会重新核对数据变化；“清空所有用户”保留用户档案。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private func sectionHeading(
        _ id: SettingsSectionID
    ) -> some View {
        let section = SettingsPresentation.section(id)
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: section.systemImage)
                .font(.title3)
                .foregroundStyle(
                    id == .dangerZone
                        ? palette.dangerInk.color
                        : Color.accentColor
                )
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(.headline)
                    .foregroundStyle(
                        id == .dangerZone
                            ? palette.dangerInk.color
                            : Color.primary
                    )
                Text(section.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func generateSampleData() {
        statusMessage = nil
        do {
            let result = try SampleDataGenerationService(
                container: modelContext.container
            ).prepare(
                repository: repository,
                ownerProfileID: profileID
            )
            guard !result.records.isEmpty else {
                statusMessage = "示例数据已存在，没有添加重复航班。"
                return
            }

            for record in result.records {
                modelContext.insert(record)
            }
            try modelContext.save()

            let skipped = result.skippedDuplicateCount > 0
                ? "，跳过 \(result.skippedDuplicateCount) 条重复记录"
                : ""
            statusMessage = "已生成 \(result.records.count) 条示例航班\(skipped)。"
        } catch {
            modelContext.rollback()
            errorMessage = "生成示例数据失败：\(error.localizedDescription)"
        }
    }

    private func beginExport(_ kind: ExportKind) {
        statusMessage = nil
        let snapshots = records.map(FlightRecordBackupDTO.init)
        let profileSnapshots = profiles.map(UserProfileBackupDTO.init)
        let currentProfile = profileSnapshots.first { $0.id == profileID }
        let container = modelContext.container
        let filenameDate = Self.filenameDate()
        isWorking = true
        Task {
            defer {
                isWorking = false
            }
            do {
                let data = try await BackupWorkScheduler.run {
                    switch kind {
                    case .csv:
                        return try BackupService.exportCSV(
                            recordSnapshots: snapshots
                        )
                    case .currentJSON:
                        return try BackupService.exportCurrent(
                            profileSnapshot: currentProfile
                                ?? UserProfileBackupDTO(
                                    id: profileID,
                                    displayName: profileDisplayName,
                                    createdAt: .now,
                                    sortOrder: 0,
                                    color: UserProfileDefaults
                                        .comparisonColorRawValue
                                ),
                            recordSnapshots: snapshots
                        )
                    case .allJSON:
                        let allRecords = try ModelContext(
                            container
                        ).fetch(FetchDescriptor<FlightRecord>())
                        return try BackupService.exportAll(
                            profileSnapshots: profileSnapshots,
                            recordSnapshots: allRecords.map(
                                FlightRecordBackupDTO.init
                            )
                        )
                    }
                }
                switch kind {
                case .csv:
                    exportContentType = .commaSeparatedText
                    exportFilename = "flightlog-\(filenameDate)"
                case .currentJSON:
                    exportContentType = .json
                    exportFilename = "flightlog-\(profileDisplayName)-\(filenameDate)"
                case .allJSON:
                    exportContentType = .json
                    exportFilename = "flightlog-all-profiles-\(filenameDate)"
                }
                exportDocument = FlightLogFileDocument(data: data)
                showingExporter = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func beginImport(_ action: ImportAction) {
        statusMessage = nil
        if importCreatesProfile {
            newImportProfileID = UUID()
        }
        importAction = action
        showingImporter = true
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            readAndPrepareImport(from: url)
        case .failure(let error):
            guard !Self.isCancellation(error) else {
                cancelImportPreparation()
                return
            }
            errorMessage = "无法打开所选文件：请检查文件访问权限。"
        }
    }

    private func readAndPrepareImport(from url: URL) {
        let action = importAction
        let repository = repository
        let targetProfileID = importCreatesProfile
            ? newImportProfileID
            : (selectedImportTargetID ?? profileID)
        let createsProfile = importCreatesProfile
        let importDestination: ProfileImportDestination = importCreatesProfile
            ? .create(
                localProfileID: newImportProfileID,
                displayName: newImportProfileName,
                color: newImportProfileColor
            )
            : .existing(targetProfileID)
        let container = modelContext.container
        let preparationID = UUID()
        cancelImportPreparation()
        importPreparationID = preparationID
        isWorking = true
        importPreparationTask = Task {
            defer {
                if importPreparationID == preparationID {
                    importPreparationTask = nil
                    importPreparationID = nil
                    isWorking = false
                }
            }
            do {
                let result = try await BackupWorkScheduler.run {
                    let data = try BackupFileIO
                        .readSecurityScopedOwnedData(from: url)
                    try Task.checkCancellation()
                    let dataset = try BackupDatasetSnapshot.capture(
                        from: container
                    )
                    let localProfileSnapshots = dataset.profiles
                    func prepareJSON(
                        mode: BackupRestoreMode
                    ) throws -> PreparedFlightImport {
                        let backup = try BackupService.decodeJSON(data)
                        try Task.checkCancellation()
                        let sourceIDs = backup.legacySingleProfile
                            ? [ProfileImportMappingPlan.legacySourceProfileID]
                            : backup.profiles.map(\.id)
                        var usedTargets = Set<UUID>()
                        var entries: [ProfileImportMappingPlan.Entry] = []
                        for (index, sourceID) in sourceIDs.enumerated() {
                            let destination: ProfileImportDestination
                            if index == 0 {
                                destination = importDestination
                            } else if localProfileSnapshots.contains(where: {
                                $0.id == sourceID
                            }), !usedTargets.contains(sourceID) {
                                destination = .existing(sourceID)
                            } else {
                                let source = backup.profiles.first {
                                    $0.id == sourceID
                                }
                                destination = .create(
                                    localProfileID: UUID(),
                                    displayName: "\(source?.displayName ?? "导入用户")（导入 \(index + 1)）",
                                    color: source?.color ?? "blue"
                                )
                            }
                            usedTargets.insert(destination.localProfileID)
                            entries.append(
                                .init(
                                    sourceProfileID: sourceID,
                                    destination: destination
                                )
                            )
                        }
                        let mapping = ProfileImportMappingPlan(entries: entries)
                        let existingTargets = Set(
                            entries.compactMap { entry -> UUID? in
                                guard case .existing(let id) = entry.destination else {
                                    return nil
                                }
                                return id
                            }
                        )
                        let targetSnapshots = dataset.records.filter {
                            guard let owner = $0.ownerProfileID else {
                                return false
                            }
                            return existingTargets.contains(owner)
                        }
                        let prepared = try BackupService.prepareJSONImport(
                            data,
                            existingRecordSnapshots: targetSnapshots,
                            mappingPlan: mapping,
                            mode: mode
                        )
                        return PreparedFlightImport(
                            records: prepared.records,
                            report: prepared.report,
                            mode: mode,
                            mappingPlan: mapping,
                            sourceSchemaVersion: prepared.sourceSchemaVersion,
                            sourceScope: prepared.sourceScope,
                            sourceProfiles: prepared.sourceProfiles,
                            existingDatasetFingerprint:
                                FlightDatasetFingerprint(
                                    profiles: localProfileSnapshots,
                                    recordSnapshots: targetSnapshots
                                ),
                            fingerprintScope: ImportFingerprintScope(
                                profileIDs: nil,
                                recordOwnerIDs: existingTargets
                            ),
                            occupiedRecordIDs: dataset.occupiedRecordIDs
                        )
                    }
                    switch action {
                    case .csv:
                        let prepared = try BackupService.prepareCSVImport(
                            data,
                            repository: repository,
                            existingRecordSnapshots: createsProfile
                                ? []
                                : dataset.records(
                                    forExistingProfileID: targetProfileID
                                ),
                            targetProfileID: targetProfileID
                        )
                        let targetSnapshots = createsProfile
                            ? []
                            : dataset.records(
                                forExistingProfileID: targetProfileID
                            )
                        return BackgroundImportPreparation.csv(
                            PreparedFlightImport(
                                records: prepared.records,
                                report: prepared.report,
                                mode: .merge,
                                mappingPlan: ProfileImportMappingPlan(entries: [
                                    .init(
                                        sourceProfileID:
                                            ProfileImportMappingPlan
                                            .legacySourceProfileID,
                                        destination: importDestination
                                    ),
                                ]),
                                sourceSchemaVersion: nil,
                                sourceScope: nil,
                                existingDatasetFingerprint:
                                    FlightDatasetFingerprint(
                                        profiles: localProfileSnapshots,
                                        recordSnapshots: targetSnapshots
                                    ),
                                fingerprintScope: ImportFingerprintScope(
                                    profileIDs: nil,
                                    recordOwnerIDs: createsProfile
                                        ? []
                                        : [targetProfileID]
                                ),
                                occupiedRecordIDs: dataset.occupiedRecordIDs
                            )
                        )
                    case .jsonMerge:
                        return BackgroundImportPreparation.json(
                            data: data,
                            mode: .merge,
                            preparation: try prepareJSON(mode: .merge)
                        )
                    case .jsonReplace:
                        return BackgroundImportPreparation.json(
                            data: data,
                            mode: .replace,
                            preparation: try prepareJSON(mode: .replace)
                        )
                    case .jsonFullRestore:
                        let backup = try BackupService.decodeJSON(data)
                        let mapping = ProfileImportMappingPlan(
                            entries: backup.profiles.map {
                                .init(
                                    sourceProfileID: $0.id,
                                    destination: .existing($0.id)
                                )
                            }
                        )
                        return BackgroundImportPreparation.json(
                            data: data,
                            mode: .fullRestore,
                            preparation: try {
                                let prepared = try BackupService.prepareJSONImport(
                                data,
                                existingRecordSnapshots: dataset.records,
                                mappingPlan: mapping,
                                mode: .fullRestore
                                )
                                return PreparedFlightImport(
                                    records: prepared.records,
                                    report: prepared.report,
                                    mode: .fullRestore,
                                    mappingPlan: mapping,
                                    sourceSchemaVersion: prepared.sourceSchemaVersion,
                                    sourceScope: prepared.sourceScope,
                                    sourceProfiles: prepared.sourceProfiles,
                                    existingDatasetFingerprint:
                                        FlightDatasetFingerprint(
                                            profiles: dataset.profiles,
                                            recordSnapshots: dataset.records
                                        ),
                                    fingerprintScope: .fullDataset,
                                    occupiedRecordIDs: dataset.occupiedRecordIDs
                                )
                            }()
                        )
                    }
                }
                try Task.checkCancellation()
                let activeProfileID = userSession?.activeProfileID ?? profileID
                let targetIsSafe = try ImportTargetGuard.isAcceptable(
                    capturedActiveProfileID: profileID,
                    currentActiveProfileID: activeProfileID,
                    importTargetProfileID: createsProfile
                        ? nil
                        : targetProfileID,
                    in: modelContext.container
                )
                guard targetIsSafe else {
                    errorMessage = "导入目标用户已变化或不存在，已忽略读取结果。"
                    return
                }
                switch result {
                case .csv(let preparation):
                    try apply(preparation)
                case let .json(data, mode, preparation):
                    importConfirmation = try ImportConfirmationState.preparedJSON(
                        sourceData: data,
                        mode: mode,
                        preparation: preparation,
                        existingRecordCount:
                            preparation.existingDatasetFingerprint.entries.count
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ preparation: PreparedFlightImport) throws {
        let report = try BackupService.apply(preparation, to: modelContext)
        importReport = report
        statusMessage = "\(report.format.rawValue) 导入完成：\(report.summary)。"
    }

    private func cancelImportPreparation() {
        let hadPreparation = importPreparationTask != nil
        importPreparationTask?.cancel()
        importPreparationTask = nil
        importPreparationID = nil
        if hadPreparation {
            isWorking = false
        }
    }

    private func confirmImport(
        _ state: ImportConfirmationState,
        mappingPlan: ProfileImportMappingPlan
    ) {
        guard !isWorking else { return }
        guard importSubmissionGate.begin() else { return }
        isWorking = true
        Task {
            defer {
                importSubmissionGate.finish()
                isWorking = false
            }
            do {
                try await state.updateMapping(mappingPlan, in: modelContext)
                switch try await state.confirmAsync(in: modelContext) {
                case .requiresReconfirmation:
                    statusMessage = nil
                case .applied(let report):
                    importReport = report
                    statusMessage = "\(report.format.rawValue) 导入完成：\(report.summary)。"
                    importConfirmation = nil
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func prepareCurrentClear() {
        do {
            currentClearPlan = try FlightDataClearService(
                container: modelContext.container
            ).prepareCurrent(profileID: profileID)
            showingCurrentClearConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareAllClear() {
        do {
            allClearPlan = try FlightDataClearService(
                container: modelContext.container
            ).prepareAll()
            showingAllClearConfirmation = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearCurrentProfileRecords() {
        guard let currentClearPlan else { return }
        do {
            try FlightDataClearService(
                container: modelContext.container
            ).clearCurrent(currentClearPlan)
            self.currentClearPlan = nil
            importReport = nil
            statusMessage = "已清空“\(profileDisplayName)”的航班。"
        } catch {
            self.currentClearPlan = nil
            errorMessage = error.localizedDescription
        }
    }

    private func clearAllProfileRecords() {
        guard let allClearPlan else { return }
        do {
            try FlightDataClearService(
                container: modelContext.container
            ).clearAll(allClearPlan)
            self.allClearPlan = nil
            importReport = nil
            statusMessage = "已清空所有用户的航班，用户档案已保留。"
        } catch {
            self.allClearPlan = nil
            errorMessage = error.localizedDescription
        }
    }

    private func copyImportReport() {
        guard let importReport else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            importReport.copyText,
            forType: .string
        )
        statusMessage = "导入结果已复制到剪贴板。"
    }

    private func reportProfileScope() {
        #if DEBUG
        ProfileScopeMountProbe.record(
            ProfileScopeMountSnapshot(
                section: .settings,
                profileID: profileID,
                recordCount: records.count,
                holderDisplayName: profileDisplayName,
                mountID: mountID
            )
        )
        #endif
    }

    private func handleExportResult(_ result: Result<URL, Error>) {
        defer {
            exportDocument = nil
        }
        switch result {
        case .success(let url):
            statusMessage = "已导出 \(url.lastPathComponent)。"
        case .failure(let error):
            guard !Self.isCancellation(error) else { return }
            errorMessage = "导出文件失败：请检查保存位置和写入权限。"
        }
    }

    private static func filenameDate() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && error.code == CocoaError.userCancelled.rawValue
    }
}

private enum BackgroundImportPreparation: Sendable {
    case csv(PreparedFlightImport)
    case json(
        data: Data,
        mode: BackupRestoreMode,
        preparation: PreparedFlightImport
    )
}

private enum ExportKind: Sendable {
    case csv
    case currentJSON
    case allJSON
}

private enum ImportAction: Sendable {
    case csv
    case jsonMerge
    case jsonReplace
    case jsonFullRestore

    var allowedContentTypes: [UTType] {
        switch self {
        case .csv:
            [.commaSeparatedText, .plainText]
        case .jsonMerge, .jsonReplace, .jsonFullRestore:
            [.json]
        }
    }
}

private struct ImportConfirmationSheet: View {
    @ObservedObject var state: ImportConfirmationState
    let localProfiles: [UserProfileBackupDTO]
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast
    let isWorking: Bool
    let onCancel: () -> Void
    let onConfirm: (ProfileImportMappingPlan) -> Void
    @State private var mappingPlan: ProfileImportMappingPlan

    init(
        state: ImportConfirmationState,
        localProfiles: [UserProfileBackupDTO],
        isWorking: Bool,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (ProfileImportMappingPlan) -> Void
    ) {
        self.state = state
        self.localProfiles = localProfiles
        self.isWorking = isWorking
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _mappingPlan = State(initialValue: state.preparation.mappingPlan)
    }

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        let controls = ImportConfirmationControlsPresentation(
            isWorking: isWorking
        )
        VStack(alignment: .leading, spacing: 18) {
            Label(state.title, systemImage: "archivebox")
                .font(.title2)
                .fontWeight(.semibold)

            if let notice = state.notice {
                Label(notice, systemImage: "arrow.clockwise.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
            } else {
                Label(
                    "备份已完整解析并验证。",
                    systemImage: "checkmark.shield"
                )
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                LabeledContent("当前记录") {
                    Text("\(state.existingRecordCount) 条")
                        .fontWeight(.semibold)
                }
                LabeledContent(
                    state.mode == .merge ? "将合并" : "将恢复"
                ) {
                    Text("\(state.preparation.records.count) 条")
                        .fontWeight(.semibold)
                }
            }

            if !state.preparation.sourceProfiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        state.preparation.sourceScope == .fullArchive
                            ? "逐用户映射预览"
                            : "来源用户映射"
                    )
                    .font(.headline)
                    ForEach(state.preparation.sourceProfiles, id: \.id) { source in
                        HStack(alignment: .firstTextBaseline) {
                            Text(source.displayName)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            if state.mode == .fullRestore {
                                Text("保留原用户 ID")
                                    .fontWeight(.semibold)
                            } else {
                                Picker(
                                    "目标",
                                    selection: destinationBinding(source)
                                ) {
                                    ForEach(localProfiles, id: \.id) { profile in
                                        Text("现有：\(profile.displayName)")
                                            .tag(
                                                ProfileImportDestination
                                                    .existing(profile.id)
                                            )
                                    }
                                    let create = createDestination(for: source)
                                    Text("新建用户").tag(create)
                                }
                                .labelsHidden()
                            }
                        }
                        .accessibilityElement(children: .combine)
                        if case let .create(_, displayName, color) =
                            destinationBinding(source).wrappedValue,
                            state.mode != .fullRestore
                        {
                            HStack {
                                TextField(
                                    "唯一昵称",
                                    text: createNameBinding(source)
                                )
                                Picker(
                                    "颜色",
                                    selection: createColorBinding(source)
                                ) {
                                    ForEach(
                                        ["blue", "orange", "green", "purple", "pink"],
                                        id: \.self
                                    ) {
                                        Text($0).tag($0)
                                    }
                                }
                                Text("\(displayName) · \(color)")
                                    .hidden()
                            }
                        }
                    }
                }
            }

            Text(state.message)
                .fixedSize(horizontal: false, vertical: true)

            if state.isDestructive {
                Text(
                    state.mode == .fullRestore
                        ? SettingsPresentation.fullRestoreConfirmation.warning
                        : SettingsPresentation.replaceConfirmation.warning
                )
                    .font(.caption)
                    .foregroundStyle(palette.dangerInk.color)
            }

            Spacer()

            HStack {
                if controls.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                    Text(controls.statusText ?? "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消", role: .cancel) {
                    onCancel()
                }
                .disabled(controls.disablesCancel)
                Button(
                    state.confirmButtonTitle,
                    role: state.isDestructive ? .destructive : nil
                ) {
                    onConfirm(mappingPlan)
                }
                .buttonStyle(.borderedProminent)
                .disabled(controls.disablesConfirm)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 320)
    }

    private func destinationBinding(
        _ source: UserProfileBackupDTO
    ) -> Binding<ProfileImportDestination> {
        Binding(
            get: {
                mappingPlan.entries.first {
                    $0.sourceProfileID == source.id
                }?.destination ?? createDestination(for: source)
            },
            set: { destination in
                setDestination(destination, for: source.id)
            }
        )
    }

    private func createNameBinding(
        _ source: UserProfileBackupDTO
    ) -> Binding<String> {
        Binding(
            get: {
                guard case let .create(_, name, _) =
                    destinationBinding(source).wrappedValue
                else {
                    return ""
                }
                return name
            },
            set: { name in
                guard case let .create(id, _, color) =
                    destinationBinding(source).wrappedValue
                else {
                    return
                }
                setDestination(
                    .create(
                        localProfileID: id,
                        displayName: name,
                        color: color
                    ),
                    for: source.id
                )
            }
        )
    }

    private func createColorBinding(
        _ source: UserProfileBackupDTO
    ) -> Binding<String> {
        Binding(
            get: {
                guard case let .create(_, _, color) =
                    destinationBinding(source).wrappedValue
                else {
                    return "blue"
                }
                return color
            },
            set: { color in
                guard case let .create(id, name, _) =
                    destinationBinding(source).wrappedValue
                else {
                    return
                }
                setDestination(
                    .create(
                        localProfileID: id,
                        displayName: name,
                        color: color
                    ),
                    for: source.id
                )
            }
        )
    }

    private func setDestination(
        _ destination: ProfileImportDestination,
        for sourceID: UUID
    ) {
        if let index = mappingPlan.entries.firstIndex(where: {
            $0.sourceProfileID == sourceID
        }) {
            mappingPlan.entries[index].destination = destination
        } else {
            mappingPlan.entries.append(
                .init(
                    sourceProfileID: sourceID,
                    destination: destination
                )
            )
        }
    }

    private func createDestination(
        for source: UserProfileBackupDTO
    ) -> ProfileImportDestination {
        if let destination = mappingPlan.entries.first(where: {
            $0.sourceProfileID == source.id
        })?.destination,
           case .create = destination
        {
            return destination
        }
        var attempt = 0
        var id: UUID
        repeat {
            id = BackupService.stableRemappedRecordID(
                sourceID: source.id,
                targetProfileID: ProfileImportMappingPlan.legacySourceProfileID,
                attempt: attempt
            )
            attempt += 1
        } while localProfiles.contains { $0.id == id }
        return .create(
            localProfileID: id,
            displayName: "\(source.displayName)（导入）",
            color: source.color
        )
    }
}

private struct ImportReportView: View {
    let report: FlightImportReport
    let onCopy: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    private var displayedIssues: [FlightImportIssue] {
        Array(report.issues.prefix(200))
    }

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 100), alignment: .leading),
                    ],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ImportCountView(
                        title: "成功",
                        count: report.successCount,
                        color: palette.successInk.color
                    )
                    ImportCountView(
                        title: "失败",
                        count: report.failureCount,
                        color: palette.dangerInk.color
                    )
                    ImportCountView(
                        title: "重复跳过",
                        count: report.duplicateCount,
                        color: palette.goldInk.color
                    )
                    Button("复制报告", systemImage: "doc.on.doc") {
                        onCopy()
                    }
                    .disabled(!report.canCopy)
                }

                if report.issues.isEmpty {
                    Text("没有错误或重复记录。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Divider()
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(displayedIssues) { issue in
                            HStack(alignment: .top, spacing: 8) {
                                Image(
                                    systemName: issue.kind == .duplicate
                                        ? "doc.on.doc"
                                        : "exclamationmark.circle"
                                )
                                .foregroundStyle(
                                    issue.kind == .duplicate
                                        ? palette.goldInk.color
                                        : palette.dangerInk.color
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location(for: issue))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Text(issue.reason)
                                        .font(.callout)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    if report.issues.count > displayedIssues.count {
                        Text(
                            "界面仅显示前 \(displayedIssues.count) 条；复制报告可获得全部 \(report.issues.count) 条明细。"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(
                "\(report.format.rawValue) 导入结果",
                systemImage: "list.bullet.clipboard"
            )
        }
    }

    private func location(for issue: FlightImportIssue) -> String {
        guard let number = issue.rowNumber else { return "文件" }
        switch report.format {
        case .csv:
            return "第 \(number) 行"
        case .json:
            return "第 \(number) 条记录"
        }
    }
}

private struct ImportCountView: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .frame(minWidth: 72, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(count)")
    }
}

#Preview {
    SettingsView(
        repository: AirportRepository(airports: [])
    )
    .modelContainer(for: FlightRecord.self, inMemory: true)
    .frame(width: 720, height: 520)
}
