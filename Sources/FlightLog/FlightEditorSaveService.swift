import Foundation
import SwiftData

enum FlightEditorSaveOutcome: Equatable {
    case saved(id: UUID)
    case requiresDuplicateConfirmation(count: Int)
}

enum FlightEditorSaveError: LocalizedError, Equatable {
    case editConflict
    case recordDeleted
    case ownerMismatch

    var errorDescription: String? {
        switch self {
        case .editConflict:
            "这条记录已被其他操作修改。为避免覆盖新内容，请关闭编辑器后重新打开。"
        case .recordDeleted:
            "这条记录已被其他操作删除，无法继续保存。"
        case .ownerMismatch:
            "这条记录不属于当前用户，无法保存修改。"
        }
    }
}

enum FlightEditorSaveService {
    @MainActor
    static func save(
        draft: FlightDraft,
        editingID: UUID?,
        openedUpdatedAt: Date?,
        ownerProfileID: UUID,
        repository: AirportRepository,
        in context: ModelContext,
        allowDuplicate: Bool,
        now: Date = .now
    ) throws -> FlightEditorSaveOutcome {
        let transactionContext = ModelContext(context.container)
        transactionContext.autosaveEnabled = false

        do {
            let latestRecords = try ProfileFlightQuery.records(
                profileID: ownerProfileID,
                in: transactionContext
            )
            let currentRecord: FlightRecord?
            if let editingID {
                guard
                    let latest = try fetchRecord(
                        id: editingID,
                        in: transactionContext
                    )
                else {
                    throw FlightEditorSaveError.recordDeleted
                }
                guard latest.ownerProfileID == ownerProfileID else {
                    throw FlightEditorSaveError.ownerMismatch
                }
                guard latest.updatedAt == openedUpdatedAt else {
                    throw FlightEditorSaveError.editConflict
                }
                currentRecord = latest
            } else {
                currentRecord = nil
            }

            let duplicates = FlightDuplicateDetector.matches(
                draft,
                in: latestRecords,
                ownerProfileID: ownerProfileID,
                excluding: editingID
            )
            if !allowDuplicate, !duplicates.isEmpty {
                return .requiresDuplicateConfirmation(
                    count: duplicates.count
                )
            }

            let savedID: UUID
            if let currentRecord {
                try FlightRecordWriter.update(
                    currentRecord,
                    from: draft,
                    repository: repository,
                    ownerProfileID: ownerProfileID,
                    now: now
                )
                savedID = currentRecord.id
            } else {
                let record = try FlightRecordWriter.makeRecord(
                    from: draft,
                    repository: repository,
                    ownerProfileID: ownerProfileID,
                    now: now
                )
                transactionContext.insert(record)
                savedID = record.id
            }
            try transactionContext.save()
            return .saved(id: savedID)
        } catch {
            transactionContext.rollback()
            throw error
        }
    }

    @MainActor
    private static func fetchRecord(
        id: UUID,
        in context: ModelContext
    ) throws -> FlightRecord? {
        let recordID = id
        var descriptor = FetchDescriptor<FlightRecord>(
            predicate: #Predicate { $0.id == recordID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
