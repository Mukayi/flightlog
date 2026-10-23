import Combine
import Foundation
import SwiftData

extension UserProfileNameValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidLength:
            "昵称需包含 1–30 个字符。"
        case .duplicate:
            "该昵称已被其他用户使用。"
        }
    }
}

@MainActor
final class UserSession: ObservableObject {
    static let activeProfileDefaultsKey = "userSession.activeProfileID"

    @Published private(set) var activeProfileID: UUID?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        activeProfileID = defaults
            .string(forKey: Self.activeProfileDefaultsKey)
            .flatMap(UUID.init(uuidString:))
    }

    func activate(_ profileID: UUID) {
        activeProfileID = profileID
        defaults.set(
            profileID.uuidString,
            forKey: Self.activeProfileDefaultsKey
        )
    }

    @discardableResult
    func resolve(profiles: [UserProfile]) -> UserProfile? {
        guard !profiles.isEmpty else {
            activeProfileID = nil
            defaults.removeObject(forKey: Self.activeProfileDefaultsKey)
            return nil
        }

        if
            let activeProfileID,
            let active = profiles.first(where: { $0.id == activeProfileID })
        {
            return active
        }

        let fallback = profiles.first(where: {
            $0.id == UserProfileDefaults.id
        }) ?? profiles.sorted(by: Self.profilePrecedes).first!
        activate(fallback.id)
        return fallback
    }

    private static func profilePrecedes(
        _ lhs: UserProfile,
        _ rhs: UserProfile
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

enum ProfileComparisonColor: String, CaseIterable, Equatable, Identifiable, Sendable {
    case blue
    case orange
    case green
    case purple
    case pink

    static let fallback = ProfileComparisonColor.blue

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .blue: "蓝色"
        case .orange: "橙色"
        case .green: "绿色"
        case .purple: "紫色"
        case .pink: "粉色"
        }
    }

    static func normalizedRawValue(_ value: String) -> String {
        ProfileComparisonColor(rawValue: value)?.rawValue
            ?? fallback.rawValue
    }
}

enum ProfileDeletionStrategy: Equatable, Sendable {
    case deleteFlights
    case transferFlights(targetProfileID: UUID)
}

enum ProfileManagementError: Error, Equatable {
    case cannotDeleteOnlyProfile
    case invalidTransferTarget
    case profileNotFound
}

extension ProfileManagementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cannotDeleteOnlyProfile:
            "至少需要保留一个用户档案。"
        case .invalidTransferTarget:
            "请选择另一个仍然存在的用户档案来接收航班。"
        case .profileNotFound:
            "该用户档案已不存在。"
        }
    }
}

@MainActor
struct ProfileManagementService {
    typealias Save = @MainActor (ModelContext) throws -> Void

    private let container: ModelContainer
    private let save: Save

    init(
        container: ModelContainer,
        save: @escaping Save = { try $0.save() }
    ) {
        self.container = container
        self.save = save
    }

    @discardableResult
    func create(
        displayName: String,
        comparisonColorRawValue: String
    ) throws -> ProfileMutationResult {
        let context = mutationContext()
        let profiles = try fetchProfiles(in: context)
        let name = try UserProfileNameValidator.validatedName(
            displayName,
            existingProfiles: profiles.map {
                UserProfileNameCandidate(
                    id: $0.id,
                    displayName: $0.displayName
                )
            }
        )
        let nextOrder = (profiles.map(\.sortOrder).max() ?? -1) + 1
        let profile = UserProfile(
            displayName: name,
            sortOrder: nextOrder,
            comparisonColorRawValue:
                ProfileComparisonColor.normalizedRawValue(
                    comparisonColorRawValue
                )
        )
        context.insert(profile)
        try save(context)
        return ProfileMutationResult(profile)
    }

    @discardableResult
    func rename(
        profileID: UUID,
        displayName: String
    ) throws -> ProfileMutationResult {
        let context = mutationContext()
        let profiles = try fetchProfiles(in: context)
        guard let profile = try fetchProfile(id: profileID, in: context) else {
            throw ProfileManagementError.profileNotFound
        }
        let name = try UserProfileNameValidator.validatedName(
            displayName,
            existingProfiles: profiles.map {
                UserProfileNameCandidate(
                    id: $0.id,
                    displayName: $0.displayName
                )
            },
            excludingProfileID: profileID
        )
        profile.displayName = name
        try save(context)
        return ProfileMutationResult(profile)
    }

    @discardableResult
    func setColor(
        profileID: UUID,
        comparisonColorRawValue: String
    ) throws -> ProfileMutationResult {
        let context = mutationContext()
        guard let profile = try fetchProfile(id: profileID, in: context) else {
            throw ProfileManagementError.profileNotFound
        }
        profile.comparisonColorRawValue =
            ProfileComparisonColor.normalizedRawValue(
                comparisonColorRawValue
            )
        try save(context)
        return ProfileMutationResult(profile)
    }

    @discardableResult
    func delete(
        profileID: UUID,
        strategy: ProfileDeletionStrategy
    ) throws -> ProfileDeletionResult {
        let context = mutationContext()
        let profiles = try fetchProfiles(in: context)
        guard let profile = try fetchProfile(id: profileID, in: context) else {
            throw ProfileManagementError.profileNotFound
        }
        guard profiles.count > 1 else {
            throw ProfileManagementError.cannotDeleteOnlyProfile
        }

        let targetID: UUID?
        switch strategy {
        case .deleteFlights:
            targetID = nil
        case .transferFlights(let candidateID):
            guard
                candidateID != profileID,
                profiles.contains(where: { $0.id == candidateID })
            else {
                throw ProfileManagementError.invalidTransferTarget
            }
            targetID = candidateID
        }

        let deletingProfileID: UUID? = profileID
        let ownedFlights = try context.fetch(
            FetchDescriptor<FlightRecord>(
                predicate: #Predicate {
                    $0.ownerProfileID == deletingProfileID
                }
            )
        )
        switch strategy {
        case .deleteFlights:
            ownedFlights.forEach(context.delete)
        case .transferFlights:
            ownedFlights.forEach { $0.ownerProfileID = targetID }
        }
        context.delete(profile)
        try save(context)

        let remaining = profiles.filter { $0.id != profileID }
        let fallback = remaining.first(where: {
            $0.id == UserProfileDefaults.id
        }) ?? remaining.sorted(by: profilePrecedes).first!
        return ProfileDeletionResult(
            deletedProfileID: profileID,
            fallbackProfileID: fallback.id
        )
    }

    private func mutationContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func fetchProfiles(
        in context: ModelContext
    ) throws -> [UserProfile] {
        try context.fetch(
            FetchDescriptor<UserProfile>(
                sortBy: [
                    SortDescriptor(\.sortOrder),
                    SortDescriptor(\.createdAt),
                ]
            )
        )
    }

    private func fetchProfile(
        id: UUID,
        in context: ModelContext
    ) throws -> UserProfile? {
        let requestedID = id
        var descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.id == requestedID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func profilePrecedes(
        _ lhs: UserProfile,
        _ rhs: UserProfile
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct ProfileMutationResult: Equatable, Sendable {
    let profileID: UUID
    let displayName: String
    let sortOrder: Int
    let comparisonColorRawValue: String

    init(_ profile: UserProfile) {
        profileID = profile.id
        displayName = profile.displayName
        sortOrder = profile.sortOrder
        comparisonColorRawValue = profile.comparisonColorRawValue
    }
}

struct ProfileDeletionResult: Equatable, Sendable {
    let deletedProfileID: UUID
    let fallbackProfileID: UUID
}

@MainActor
final class ProfileMutationGate: ObservableObject {
    @Published private(set) var isSubmitting = false

    private var task: Task<Void, Never>?
    private var token: UUID?

    @discardableResult
    func submit<Result>(
        _ operation: @escaping @MainActor () async throws -> Result,
        onSuccess: @escaping @MainActor (Result) -> Void = { _ in },
        onError: @escaping @MainActor (Error) -> Void
    ) -> Bool {
        guard !isSubmitting else { return false }

        let submissionToken = UUID()
        token = submissionToken
        isSubmitting = true
        task = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else {
                self?.finish(submissionToken)
                return
            }
            do {
                let result = try await operation()
                guard !Task.isCancelled else {
                    self?.finish(submissionToken)
                    return
                }
                onSuccess(result)
            } catch is CancellationError {
                // Closing the sheet or replacing its selection is not an error.
            } catch {
                guard !Task.isCancelled else {
                    self?.finish(submissionToken)
                    return
                }
                onError(error)
            }
            self?.finish(submissionToken)
        }
        return true
    }

    func cancel() {
        token = nil
        task?.cancel()
        task = nil
        isSubmitting = false
    }

    private func finish(_ submissionToken: UUID) {
        guard token == submissionToken else { return }
        token = nil
        task = nil
        isSubmitting = false
    }
}

enum ProfileManagementAccessibility {
    static let createLabel = "新建用户"
    static let createHint = "创建后切换到新用户"
    static let deletionStrategyLabel = "航班处理方式"
    static let deletionStrategyValues = ["连同航班删除", "迁移到其他用户"]

    static func colorLabel(profileName: String) -> String {
        "\(profileName)，显示颜色"
    }

    static func currentProfileLabel(profileName: String) -> String {
        "\(profileName)，当前用户"
    }

    static func deleteHint(canDelete: Bool) -> String {
        canDelete
            ? "选择删除航班或迁移航班，并再次确认"
            : "至少需要保留一个用户"
    }
}
