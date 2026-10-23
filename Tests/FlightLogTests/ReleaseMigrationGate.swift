import CoreData
import Foundation
import SwiftData
@testable import FlightLog

@MainActor
enum ReleaseMigrationGate {
    static let stablePollCount = 3
    static let pollInterval: TimeInterval = 0.1

    static func hasV2SchemaMetadata(at storeURL: URL) -> Bool {
        guard
            let metadata = try? NSPersistentStoreCoordinator
                .metadataForPersistentStore(
                    ofType: NSSQLiteStoreType,
                    at: storeURL
                ),
            let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data]
        else {
            return false
        }
        return hashes["UserProfile"] != nil
    }

    static func isPostconditionMet(at storeURL: URL) -> Bool {
        guard hasV2SchemaMetadata(at: storeURL) else { return false }
        guard let controller = try? PersistenceController.readOnly(storeURL: storeURL)
        else { return false }
        guard
            let profiles = try? controller.container.mainContext.fetch(
                FetchDescriptor<UserProfile>()
            ),
            let records = try? controller.container.mainContext.fetch(
                FetchDescriptor<FlightRecord>()
            )
        else {
            return false
        }
        guard !profiles.isEmpty else { return false }
        let profileIDs = Set(profiles.map(\.id))
        return records.allSatisfy { record in
            guard let ownerProfileID = record.ownerProfileID else {
                return false
            }
            return profileIDs.contains(ownerProfileID)
        }
    }

    static func wouldLegacyMetadataGateComplete(on postconditionStates: [Bool])
        -> Bool
    {
        postconditionStates.contains(true)
    }

    static func wouldStablePostconditionGateComplete(
        postconditionStates: [Bool],
        stablePollCount: Int = ReleaseMigrationGate.stablePollCount
    ) -> Bool {
        var consecutiveStable = 0
        for isMet in postconditionStates {
            if isMet {
                consecutiveStable += 1
                if consecutiveStable >= stablePollCount {
                    return true
                }
            } else {
                consecutiveStable = 0
            }
        }
        return false
    }

    @discardableResult
    static func awaitPostcondition(
        storeURL: URL,
        process: Process?,
        timeout: TimeInterval = 12,
        stablePollCount: Int = ReleaseMigrationGate.stablePollCount
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var consecutiveStable = 0
        while Date() < deadline {
            if isPostconditionMet(at: storeURL) {
                consecutiveStable += 1
                if consecutiveStable >= stablePollCount {
                    return true
                }
            } else {
                consecutiveStable = 0
            }
            if let process, !process.isRunning {
                return false
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return false
    }
}
