import Foundation

enum RouteVisualScale {
    static func lineWidth(
        flightCount: Int,
        maximumFlightCount: Int
    ) -> Double {
        let minimumWidth = 2.0
        let maximumWidth = 8.0
        guard maximumFlightCount > 1 else {
            return minimumWidth
        }

        let count = min(
            max(1, flightCount),
            maximumFlightCount
        )
        let normalized = (sqrt(Double(count)) - 1)
            / (sqrt(Double(maximumFlightCount)) - 1)
        return minimumWidth
            + normalized * (maximumWidth - minimumWidth)
    }
}
