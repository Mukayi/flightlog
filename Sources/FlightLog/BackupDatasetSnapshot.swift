import Foundation
import SwiftData

struct BackupDatasetSnapshot: Equatable, Sendable {
    let profiles: [UserProfileBackupDTO]
    let records: [FlightRecordBackupDTO]

    var occupiedRecordIDs: Set<UUID> {
        Set(records.map(\.id))
    }

    func records(
        forExistingProfileID profileID: UUID
    ) -> [FlightRecordBackupDTO] {
        records.filter { $0.ownerProfileID == profileID }
    }

    func recordCount(forExistingProfileID profileID: UUID) -> Int {
        records.reduce(into: 0) { result, record in
            if record.ownerProfileID == profileID {
                result += 1
            }
        }
    }

    static func load(from container: ModelContainer) async throws
        -> BackupDatasetSnapshot
    {
        try await BackupWorkScheduler.run {
            try capture(from: container)
        }
    }

    static func capture(from container: ModelContainer) throws
        -> BackupDatasetSnapshot
    {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let profileModels = try context.fetch(FetchDescriptor<UserProfile>())
        let recordModels = try context.fetch(FetchDescriptor<FlightRecord>())
        var profiles: [UserProfileBackupDTO] = []
        profiles.reserveCapacity(profileModels.count)
        for (index, profile) in profileModels.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            profiles.append(UserProfileBackupDTO(profile: profile))
        }
        var records: [FlightRecordBackupDTO] = []
        records.reserveCapacity(recordModels.count)
        for (index, record) in recordModels.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            records.append(FlightRecordBackupDTO(record: record))
        }
        return BackupDatasetSnapshot(
            profiles: profiles,
            records: records
        )
    }
}
