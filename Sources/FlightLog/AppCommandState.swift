import Combine
import Foundation

struct OpenFlightRequest: Equatable, Sendable {
    let id: UUID
    let token: UInt
}

@MainActor
final class AppCommandState: ObservableObject {
    @Published var selection: AppSection? = .overview
    @Published private(set) var newFlightRequest = 0
    @Published private(set) var focusSearchRequest = 0
    @Published private(set) var openFlightRequest: OpenFlightRequest?
    private var consumedNewFlightRequest = 0
    private var consumedFocusSearchRequest = 0
    private var openFlightRequestSequence: UInt = 0
    private var consumedOpenFlightRequestSequence: UInt = 0

    func navigate(to section: AppSection) {
        selection = section
    }

    func requestNewFlight() {
        selection = .flights
        newFlightRequest &+= 1
    }

    func requestFlightSearch() {
        selection = .flights
        focusSearchRequest &+= 1
    }

    func requestOpenFlight(id: UUID) {
        selection = .flights
        openFlightRequestSequence &+= 1
        openFlightRequest = OpenFlightRequest(
            id: id,
            token: openFlightRequestSequence
        )
    }

    func takeNewFlightRequest() -> Bool {
        guard newFlightRequest != consumedNewFlightRequest else {
            return false
        }
        consumedNewFlightRequest = newFlightRequest
        return true
    }

    func takeFocusSearchRequest() -> Bool {
        guard focusSearchRequest != consumedFocusSearchRequest else {
            return false
        }
        consumedFocusSearchRequest = focusSearchRequest
        return true
    }

    func takeOpenFlightRequest() -> UUID? {
        guard
            let request = openFlightRequest,
            request.token != consumedOpenFlightRequestSequence
        else {
            return nil
        }
        consumedOpenFlightRequestSequence = request.token
        return request.id
    }
}
