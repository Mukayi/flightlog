import Foundation

enum FlightLookupCoordinatorState: Equatable, Sendable {
    case idle
    case querying
    case awaitingCandidateSelection([FlightLookupResult])
    case awaitingOverwriteConfirmation(FlightLookupResult)
    case applied(FlightLookupApplyReport)
    case failed(String)
}

@MainActor
final class FlightLookupCoordinator {
    static let identityChangedMessage = "航班号或日期已更改，请重新查询"

    private(set) var draft: FlightDraft
    private(set) var state: FlightLookupCoordinatorState = .idle

    private let repository: AirportRepository
    private let isEditing: Bool
    private let keyStore: any APIKeyStore
    private let client: any FlightLookupClient
    private var queryIdentity: QueryIdentity?
    private var activeQueryID: UUID?

    init(
        draft: FlightDraft,
        repository: AirportRepository,
        isEditing: Bool,
        keyStore: any APIKeyStore,
        client: any FlightLookupClient
    ) {
        self.draft = draft
        self.repository = repository
        self.isEditing = isEditing
        self.keyStore = keyStore
        self.client = client
    }

    func replaceDraft(_ draft: FlightDraft) {
        self.draft = draft
        activeQueryID = nil
        queryIdentity = nil
        state = .idle
    }

    func query(
        currentDraft: @escaping @MainActor () -> FlightDraft
    ) async {
        let queryID = UUID()
        let identity = QueryIdentity(draft)
        activeQueryID = queryID
        queryIdentity = identity
        state = .querying
        do {
            guard
                let key = try keyStore.load()?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !key.isEmpty
            else {
                throw AeroDataBoxError.missingAPIKey
            }
            let results = try await client.lookup(
                flightNumber: draft.normalizedFlightNumber,
                localDate: draft.departureLocalDate,
                apiKey: key
            )
            guard !results.isEmpty else {
                throw AeroDataBoxError.noResults
            }
            guard activeQueryID == queryID, !Task.isCancelled else {
                if activeQueryID == queryID {
                    draft = currentDraft()
                    activeQueryID = nil
                    queryIdentity = nil
                    state = .idle
                }
                return
            }
            let latestDraft = currentDraft()
            draft = latestDraft
            guard QueryIdentity(latestDraft) == identity else {
                activeQueryID = nil
                queryIdentity = nil
                state = .failed(Self.identityChangedMessage)
                return
            }
            activeQueryID = nil
            state = .awaitingCandidateSelection(results)
        } catch is CancellationError {
            guard activeQueryID == queryID else { return }
            draft = currentDraft()
            activeQueryID = nil
            queryIdentity = nil
            state = .idle
        } catch {
            guard activeQueryID == queryID else { return }
            draft = currentDraft()
            activeQueryID = nil
            queryIdentity = nil
            state = .failed(error.localizedDescription)
        }
    }

    func selectCandidate(
        _ result: FlightLookupResult,
        currentDraft: FlightDraft
    ) {
        guard case .awaitingCandidateSelection(let results) = state,
              results.contains(where: { $0.id == result.id })
        else {
            return
        }
        guard adoptLatestDraftIfIdentityMatches(currentDraft) else { return }
        if isEditing {
            state = .awaitingOverwriteConfirmation(result)
        } else {
            apply(result)
        }
    }

    func confirmOverwrite(currentDraft: FlightDraft) {
        guard case .awaitingOverwriteConfirmation(let result) = state else {
            return
        }
        guard adoptLatestDraftIfIdentityMatches(currentDraft) else { return }
        apply(result)
    }

    func cancel() {
        activeQueryID = nil
        queryIdentity = nil
        state = .idle
    }

    private func apply(_ result: FlightLookupResult) {
        do {
            let report = try FlightLookupDraftApplicator.apply(
                result,
                to: &draft,
                repository: repository
            )
            queryIdentity = nil
            state = .applied(report)
        } catch {
            queryIdentity = nil
            state = .failed(error.localizedDescription)
        }
    }

    private func adoptLatestDraftIfIdentityMatches(
        _ latestDraft: FlightDraft
    ) -> Bool {
        draft = latestDraft
        guard
            let queryIdentity,
            QueryIdentity(latestDraft) == queryIdentity
        else {
            self.queryIdentity = nil
            state = .failed(Self.identityChangedMessage)
            return false
        }
        return true
    }
}

private struct QueryIdentity: Equatable {
    let flightNumber: String
    let departureLocalDate: Date

    init(_ draft: FlightDraft) {
        flightNumber = draft.normalizedFlightNumber
        departureLocalDate = FlightDateNormalization.canonicalDate(
            draft.departureLocalDate
        )
    }
}
