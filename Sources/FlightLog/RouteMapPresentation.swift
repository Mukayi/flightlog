import Foundation
import SwiftUI

struct RouteMapStrokePresentation: Equatable, Sendable {
    let colorRole: FlightTheme.SemanticColorRole
    let opacity: Double
    let lineWidth: CGFloat
    let zIndex: Double
}

struct RouteMapMotionPresentation: Equatable, Sendable {
    let animationDuration: Double?
    let scale: CGFloat
    let verticalOffset: CGFloat
    let opacity: Double
    let repeatCount: Int
}

struct RouteMapSegment: Identifiable {
    let routeID: String
    let segmentIndex: Int
    let flightCount: Int
    let coordinates: [FlightCoordinate]

    var id: String {
        "\(routeID)#\(segmentIndex)"
    }
}

enum RouteMapVisualPolicy {
    static func stroke(
        isSelected: Bool,
        baseLineWidth: CGFloat
    ) -> RouteMapStrokePresentation {
        RouteMapStrokePresentation(
            colorRole: isSelected ? .routeAccent : .warmGold,
            opacity: isSelected ? 1 : 0.68,
            lineWidth: baseLineWidth + (isSelected ? 2 : 0),
            zIndex: isSelected ? 1 : 0
        )
    }

    static func orderedSegments(
        _ segments: [RouteMapSegment],
        selectedID: String?
    ) -> [RouteMapSegment] {
        segments.sorted { lhs, rhs in
            let lhsLayer = stroke(
                isSelected: lhs.routeID == selectedID,
                baseLineWidth: 0
            ).zIndex
            let rhsLayer = stroke(
                isSelected: rhs.routeID == selectedID,
                baseLineWidth: 0
            ).zIndex
            if lhsLayer != rhsLayer {
                return lhsLayer < rhsLayer
            }
            return lhs.id < rhs.id
        }
    }

    static func motion(
        hasAppeared: Bool,
        isHovered: Bool,
        reduceMotion: Bool
    ) -> RouteMapMotionPresentation {
        guard !reduceMotion else {
            return RouteMapMotionPresentation(
                animationDuration: nil,
                scale: 1,
                verticalOffset: 0,
                opacity: 1,
                repeatCount: 0
            )
        }
        return RouteMapMotionPresentation(
            animationDuration: FlightTheme.Animation.quick,
            scale: hasAppeared && isHovered ? 1.035 : 1,
            verticalOffset: hasAppeared
                ? (isHovered ? -2 : 0)
                : 6,
            opacity: hasAppeared ? 1 : 0,
            repeatCount: 0
        )
    }

    static func annotationLabel(for airport: AirportSnapshot) -> String {
        let details = [airport.iata, airport.name, airport.city, airport.country]
            .filter { !$0.isEmpty }
            .joined(separator: "，")
        return "机场 \(details)"
    }
}

struct RouteMapIncludedFlightPresentation: Identifiable, Equatable {
    let id: UUID
    let flightNumber: String
    let dateText: String
    let routeText: String
}

struct RouteMapPresentation {
    let routeID: String
    let airportAIATA: String
    let airportBIATA: String
    let flightCountText: String
    let distanceText: String
    let coverageText: String
    let includedFlights: [RouteMapIncludedFlightPresentation]

    init(route: RouteAggregate) {
        routeID = route.id
        airportAIATA = route.airportA.iata
        airportBIATA = route.airportB.iata
        flightCountText = "\(route.flightCount) 次"
        distanceText = FlightDisplayFormatting.routeDistance(
            kilometers: route.totalDistanceKilometers,
            unit: .kilometers,
            missingFlightCount: route.missingDistanceFlightCount
        )
        coverageText =
            "\(route.measuredDistanceFlightCount)/\(route.flightCount) 次可计算"
        includedFlights = route.flights.map { flight in
            RouteMapIncludedFlightPresentation(
                id: flight.id,
                flightNumber: flight.flightNumber,
                dateText: Self.dateFormatter.string(from: flight.flightDate),
                routeText:
                    "\(flight.departureAirportIATA) → \(flight.arrivalAirportIATA)"
            )
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()
}
