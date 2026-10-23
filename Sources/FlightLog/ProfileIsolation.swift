import Foundation
import SwiftData

enum ProfileSwitchResetPolicy {
    enum State: String, Equatable, Sendable {
        case selection
        case search
        case filter
        case editor
        case hover
    }

    static let flightBrowserState: [State] = [
        .selection,
        .search,
        .filter,
        .editor,
    ]
    static let routeMapState: [State] = [
        .selection,
        .filter,
        .hover,
    ]

    static func identity(_ profileID: UUID) -> String {
        "profile-scope-\(profileID.uuidString)"
    }
}

#if DEBUG
struct ProfileScopeMountSnapshot: Equatable, Sendable {
    let section: AppSection
    let profileID: UUID
    let recordCount: Int
    let holderDisplayName: String?
    let mountID: UUID
}

@MainActor
enum ProfileScopeMountProbe {
    static var observer: ((ProfileScopeMountSnapshot) -> Void)?

    static func record(_ snapshot: ProfileScopeMountSnapshot) {
        observer?(snapshot)
    }
}
#endif

enum ProfileFlightQuery {
    static func descriptor(
        profileID: UUID,
        sortBy: [SortDescriptor<FlightRecord>] = []
    ) -> FetchDescriptor<FlightRecord> {
        let ownerID: UUID? = profileID
        return FetchDescriptor(
            predicate: #Predicate { $0.ownerProfileID == ownerID },
            sortBy: sortBy
        )
    }

    @MainActor
    static func records(
        profileID: UUID,
        in context: ModelContext,
        sortBy: [SortDescriptor<FlightRecord>] = []
    ) throws -> [FlightRecord] {
        try context.fetch(descriptor(profileID: profileID, sortBy: sortBy))
    }
}

@MainActor
enum ImportTargetGuard {
    static func isAcceptable(
        capturedTarget: UUID,
        activeProfileID: UUID?,
        in container: ModelContainer
    ) throws -> Bool {
        guard activeProfileID == capturedTarget else {
            return false
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let target = capturedTarget
        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.id == target }
        )
        return try context.fetchCount(descriptor) == 1
    }

    static func isAcceptable(
        capturedActiveProfileID: UUID,
        currentActiveProfileID: UUID?,
        importTargetProfileID: UUID?,
        in container: ModelContainer
    ) throws -> Bool {
        guard currentActiveProfileID == capturedActiveProfileID else {
            return false
        }
        guard let importTargetProfileID else {
            return true
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let target = importTargetProfileID
        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.id == target }
        )
        return try context.fetchCount(descriptor) == 1
    }
}

enum FlightDataClearError: LocalizedError, Equatable {
    case staleConfirmation

    var errorDescription: String? {
        switch self {
        case .staleConfirmation:
            "航班数据已发生变化，请重新确认后再清空。"
        }
    }
}

struct FlightDataClearPlan: Sendable {
    enum Scope: Sendable, Equatable {
        case current(UUID)
        case all
    }

    let scope: Scope
    let recordCount: Int
    let fingerprint: FlightDatasetFingerprint
}

@MainActor
struct FlightDataClearService {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func prepareCurrent(profileID: UUID) throws -> FlightDataClearPlan {
        let context = transactionContext()
        let records = try ProfileFlightQuery.records(
            profileID: profileID,
            in: context
        )
        return FlightDataClearPlan(
            scope: .current(profileID),
            recordCount: records.count,
            fingerprint: FlightDatasetFingerprint(records: records)
        )
    }

    func prepareAll() throws -> FlightDataClearPlan {
        let context = transactionContext()
        let records = try context.fetch(FetchDescriptor<FlightRecord>())
        return FlightDataClearPlan(
            scope: .all,
            recordCount: records.count,
            fingerprint: FlightDatasetFingerprint(records: records)
        )
    }

    func clearCurrent(_ plan: FlightDataClearPlan) throws {
        guard case .current(let profileID) = plan.scope else {
            throw FlightDataClearError.staleConfirmation
        }
        try clear(plan: plan) { context in
            try ProfileFlightQuery.records(profileID: profileID, in: context)
        }
    }

    func clearAll(_ plan: FlightDataClearPlan) throws {
        guard plan.scope == .all else {
            throw FlightDataClearError.staleConfirmation
        }
        try clear(plan: plan) { context in
            try context.fetch(FetchDescriptor<FlightRecord>())
        }
    }

    private func clear(
        plan: FlightDataClearPlan,
        fetch: (ModelContext) throws -> [FlightRecord]
    ) throws {
        let context = transactionContext()
        let records = try fetch(context)
        guard FlightDatasetFingerprint(records: records) == plan.fingerprint else {
            throw FlightDataClearError.staleConfirmation
        }
        records.forEach(context.delete)
        try context.save()
    }

    private func transactionContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }
}
