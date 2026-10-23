import Combine
import Foundation
import SwiftData

enum ImportConfirmationOutcome: Equatable {
    case requiresReconfirmation
    case applied(FlightImportReport)
}

@MainActor
final class ImportConfirmationState: ObservableObject, Identifiable {
    let id = UUID()
    let sourceData: Data
    let mode: BackupRestoreMode

    @Published private(set) var preparation: PreparedFlightImport
    @Published private(set) var existingRecordCount: Int
    @Published private(set) var notice: String?
    @Published private(set) var confirmationRevision = 0

    var targetProfileID: UUID? {
        preparation.targetProfileID
    }

    static func prepareJSON(
        sourceData: Data,
        mode: BackupRestoreMode,
        existingRecords: [FlightRecord],
        targetProfileID: UUID
    ) throws -> ImportConfirmationState {
        let preparation = try BackupService.prepareJSONImport(
            sourceData,
            existingRecords: existingRecords,
            targetProfileID: targetProfileID,
            mode: mode
        )
        return try preparedJSON(
            sourceData: sourceData,
            mode: mode,
            preparation: preparation,
            existingRecordCount: existingRecords.count,
            targetProfileID: targetProfileID
        )
    }

    static func preparedJSON(
        sourceData: Data,
        mode: BackupRestoreMode,
        preparation: PreparedFlightImport,
        existingRecordCount: Int,
        targetProfileID: UUID
    ) throws -> ImportConfirmationState {
        guard let derived = preparation.targetProfileID else {
            throw BackupServiceError.invalidProfileMapping(
                "兼容 target 参数仅支持单一目标映射。"
            )
        }
        guard derived == targetProfileID else {
            throw BackupServiceError.targetProfileMismatch(
                expected: derived,
                actual: targetProfileID
            )
        }
        return try ImportConfirmationState(
            sourceData: sourceData,
            mode: mode,
            preparation: preparation,
            existingRecordCount: existingRecordCount
        )
    }

    static func preparedJSON(
        sourceData: Data,
        mode: BackupRestoreMode,
        preparation: PreparedFlightImport,
        existingRecordCount: Int
    ) throws -> ImportConfirmationState {
        try ImportConfirmationState(
            sourceData: sourceData,
            mode: mode,
            preparation: preparation,
            existingRecordCount: existingRecordCount
        )
    }

    var title: String {
        switch mode {
        case .merge:
            "合并 JSON 备份？"
        case .replace:
            "替换全部航班数据？"
        case .fullRestore:
            "完整恢复所有档案？"
        }
    }

    var message: String {
        switch mode {
        case .merge:
            "将向当前 \(existingRecordCount) 条数据合并 \(preparation.records.count) 条新记录；重复记录会跳过。"
        case .replace:
            "将删除当前 \(existingRecordCount) 条记录，再恢复 \(preparation.records.count) 条；此操作无法撤销。"
        case .fullRestore:
            "将原子替换所有用户档案与航班；此高风险操作无法撤销。"
        }
    }

    var confirmButtonTitle: String {
        switch mode {
        case .merge:
            "确认合并"
        case .replace:
            "删除现有数据并恢复"
        case .fullRestore:
            "确认完整恢复所有档案"
        }
    }

    var isDestructive: Bool {
        mode == .replace || mode == .fullRestore
    }

    private init(
        sourceData: Data,
        mode: BackupRestoreMode,
        preparation: PreparedFlightImport,
        existingRecordCount: Int
    ) throws {
        self.sourceData = sourceData
        self.mode = mode
        self.preparation = preparation
        self.existingRecordCount = existingRecordCount
    }

    func confirm(
        in context: ModelContext
    ) throws -> ImportConfirmationOutcome {
        do {
            return .applied(try applyPreparation(in: context))
        } catch BackupServiceError.staleImportPlan {
            let latestRecords = try allRecords(in: context)
            let latestProfiles = try allProfiles(in: context)
            let refreshed = try refreshedPreparation(
                recordSnapshots: latestRecords.map(FlightRecordBackupDTO.init),
                profileSnapshots: latestProfiles.map(UserProfileBackupDTO.init)
            )
            preparation = refreshed
            existingRecordCount = mappedExistingRecordCount(
                snapshots: latestRecords.map(FlightRecordBackupDTO.init)
            )
            confirmationRevision += 1
            notice = "数据已变化，请再次确认。"
            return .requiresReconfirmation
        }
    }

    func confirmAsync(
        in context: ModelContext
    ) async throws -> ImportConfirmationOutcome {
        do {
            return .applied(try applyPreparation(in: context))
        } catch BackupServiceError.staleImportPlan {
            let dataset = try await BackupDatasetSnapshot.load(
                from: context.container
            )
            let snapshots = dataset.records
            let profileSnapshots = dataset.profiles
            let data = sourceData
            let mode = mode
            let mappingPlan = preparation.mappingPlan
            let fingerprintScope = preparation.fingerprintScope
            let refreshed = try await BackupWorkScheduler.run {
                let prepared = try BackupService.prepareJSONImport(
                    data,
                    existingRecordSnapshots: snapshots,
                    mappingPlan: mappingPlan,
                    mode: mode
                )
                return PreparedFlightImport(
                    records: prepared.records,
                    report: prepared.report,
                    mode: mode,
                    mappingPlan: mappingPlan,
                    sourceSchemaVersion: prepared.sourceSchemaVersion,
                    sourceScope: prepared.sourceScope,
                    sourceProfiles: prepared.sourceProfiles,
                    existingDatasetFingerprint: Self.scopedFingerprint(
                        profiles: profileSnapshots,
                        records: snapshots,
                        scope: fingerprintScope
                    ),
                    fingerprintScope: fingerprintScope,
                    occupiedRecordIDs: Set(snapshots.map(\.id))
                )
            }
            preparation = refreshed
            existingRecordCount = mappedExistingRecordCount(
                snapshots: snapshots
            )
            confirmationRevision += 1
            notice = "数据已变化，请再次确认。"
            return .requiresReconfirmation
        }
    }

    func updateMapping(
        _ mappingPlan: ProfileImportMappingPlan,
        in context: ModelContext
    ) async throws {
        guard mode != .fullRestore else { return }
        let dataset = try await BackupDatasetSnapshot.load(
            from: context.container
        )
        let records = dataset.records
        let profiles = dataset.profiles
        let sources = preparation.sourceProfiles.isEmpty
            ? [
                UserProfileBackupDTO(
                    id: ProfileImportMappingPlan.legacySourceProfileID,
                    displayName: "旧版/CSV 来源",
                    createdAt: Date(timeIntervalSince1970: 0),
                    sortOrder: 0,
                    color: "blue"
                ),
            ]
            : preparation.sourceProfiles
        _ = try mappingPlan.validated(
            sourceProfiles: sources,
            localProfiles: profiles
        )
        let data = sourceData
        let mode = mode
        let refreshed = try await BackupWorkScheduler.run {
            try BackupService.prepareJSONImport(
                data,
                existingRecordSnapshots: records,
                mappingPlan: mappingPlan,
                mode: mode
            )
        }
        let scope = ImportFingerprintScope(
            profileIDs: nil,
            recordOwnerIDs: Set(
                mappingPlan.entries.compactMap {
                    guard case .existing(let id) = $0.destination else {
                        return nil
                    }
                    return id
                }
            )
        )
        preparation = PreparedFlightImport(
            records: refreshed.records,
            report: refreshed.report,
            mode: mode,
            mappingPlan: mappingPlan,
            sourceSchemaVersion: refreshed.sourceSchemaVersion,
            sourceScope: refreshed.sourceScope,
            sourceProfiles: refreshed.sourceProfiles,
            existingDatasetFingerprint: scopedFingerprint(
                profiles: profiles,
                records: records,
                scope: scope
            ),
            fingerprintScope: scope,
            occupiedRecordIDs: Set(records.map(\.id))
        )
        existingRecordCount = mappedExistingRecordCount(snapshots: records)
    }

    private func applyPreparation(
        in context: ModelContext
    ) throws -> FlightImportReport {
        try BackupService.apply(preparation, to: context)
    }

    private func refreshedPreparation(
        recordSnapshots: [FlightRecordBackupDTO],
        profileSnapshots: [UserProfileBackupDTO]
    ) throws -> PreparedFlightImport {
        let prepared = try BackupService.prepareJSONImport(
            sourceData,
            existingRecordSnapshots: recordSnapshots,
            mappingPlan: preparation.mappingPlan,
            mode: mode
        )
        return PreparedFlightImport(
            records: prepared.records,
            report: prepared.report,
            mode: mode,
            mappingPlan: preparation.mappingPlan,
            sourceSchemaVersion: prepared.sourceSchemaVersion,
            sourceScope: prepared.sourceScope,
            sourceProfiles: prepared.sourceProfiles,
            existingDatasetFingerprint: scopedFingerprint(
                profiles: profileSnapshots,
                records: recordSnapshots,
                scope: preparation.fingerprintScope
            ),
            fingerprintScope: preparation.fingerprintScope,
            occupiedRecordIDs: Set(recordSnapshots.map(\.id))
        )
    }

    private func allRecords(in context: ModelContext) throws -> [FlightRecord] {
        try context.fetch(FetchDescriptor<FlightRecord>())
    }

    private func allProfiles(in context: ModelContext) throws -> [UserProfile] {
        try context.fetch(FetchDescriptor<UserProfile>())
    }

    private func mappedExistingRecordCount(
        snapshots: [FlightRecordBackupDTO]
    ) -> Int {
        if mode == .fullRestore {
            return snapshots.count
        }
        let targets = Set(
            preparation.mappingPlan.entries.compactMap { entry -> UUID? in
                guard case .existing(let id) = entry.destination else {
                    return nil
                }
                return id
            }
        )
        return snapshots.reduce(into: 0) { count, record in
            if let owner = record.ownerProfileID, targets.contains(owner) {
                count += 1
            }
        }
    }

    nonisolated private static func scopedFingerprint(
        profiles: [UserProfileBackupDTO],
        records: [FlightRecordBackupDTO],
        scope: ImportFingerprintScope
    ) -> FlightDatasetFingerprint {
        let scopedProfiles = scope.profileIDs.map { ids in
            profiles.filter { ids.contains($0.id) }
        } ?? profiles
        let scopedRecords = scope.recordOwnerIDs.map { ids in
            records.filter {
                guard let owner = $0.ownerProfileID else { return false }
                return ids.contains(owner)
            }
        } ?? records
        return FlightDatasetFingerprint(
            profiles: scopedProfiles,
            recordSnapshots: scopedRecords
        )
    }

    private func scopedFingerprint(
        profiles: [UserProfileBackupDTO],
        records: [FlightRecordBackupDTO],
        scope: ImportFingerprintScope
    ) -> FlightDatasetFingerprint {
        Self.scopedFingerprint(
            profiles: profiles,
            records: records,
            scope: scope
        )
    }
}
