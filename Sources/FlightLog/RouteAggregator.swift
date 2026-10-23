import Foundation

struct AirportSnapshot: Identifiable, Hashable, Sendable {
    let iata: String
    let name: String
    let city: String
    let country: String
    let latitude: Double
    let longitude: Double
    let timeZoneID: String

    var id: String { iata }

    var coordinate: FlightCoordinate {
        FlightCoordinate(latitude: latitude, longitude: longitude)
    }

    var displayName: String {
        let location = [city, country]
            .filter { !$0.isEmpty }
            .joined(separator: "，")
        if location.isEmpty {
            return "\(iata) · \(name)"
        }
        return "\(iata) · \(name)\n\(location)"
    }
}

struct RouteAggregate: Identifiable {
    let id: String
    let airportA: AirportSnapshot
    let airportB: AirportSnapshot
    let flights: [FlightRecord]
    let airlines: [String]
    let totalDistanceKilometers: Double?
    let measuredDistanceFlightCount: Int
    let missingDistanceFlightCount: Int

    var flightCount: Int {
        flights.count
    }

    var displayName: String {
        "\(airportA.iata) ↔ \(airportB.iata)"
    }

    var hasValidGeometry: Bool {
        airportA.coordinate.isValid
            && airportB.coordinate.isValid
            && airportA.coordinate != airportB.coordinate
    }
}

struct RouteAggregator {
    let metrics: FlightMetricsService

    init(metrics: FlightMetricsService = .standard) {
        self.metrics = metrics
    }

    func aggregate(_ records: [FlightRecord]) -> [RouteAggregate] {
        // The nonthrowing path is retained for existing synchronous pages.
        (try? aggregate(records, checksCancellation: false)) ?? []
    }

    func aggregateCheckingCancellation(
        _ records: [FlightRecord]
    ) throws -> [RouteAggregate] {
        try aggregate(records, checksCancellation: true)
    }

    private func aggregate(
        _ records: [FlightRecord],
        checksCancellation: Bool
    ) throws -> [RouteAggregate] {
        var grouped: [String: [FlightRecord]] = [:]
        for (index, record) in records.enumerated() {
            if checksCancellation, index.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            grouped[Self.routeID(record), default: []].append(record)
        }
        var output: [RouteAggregate] = []
        for (index, routeID) in grouped.keys.sorted().enumerated() {
            if checksCancellation, index.isMultiple(of: 16) {
                try Task.checkCancellation()
            }
            guard let groupedFlights = grouped[routeID] else {
                continue
            }
            let flights = groupedFlights.sorted(by: Self.flightComesFirst)
            guard let fallbackRepresentative = flights.first else {
                continue
            }
            let representative = flights.first { flight in
                let airports = Self.canonicalAirports(for: flight)
                return airports.0.coordinate.isValid
                    && airports.1.coordinate.isValid
                    && airports.0.coordinate != airports.1.coordinate
            } ?? fallbackRepresentative
            let airports = Self.canonicalAirports(for: representative)
            let airlines = Array(
                Set(flights.map(Self.airlineDescription))
            ).sorted()
            let measuredDistances = flights.compactMap(
                metrics.distanceKilometers(for:)
            )
            let totalDistance = measuredDistances.isEmpty
                ? nil
                : measuredDistances.reduce(0, +)

            output.append(RouteAggregate(
                id: routeID,
                airportA: airports.0,
                airportB: airports.1,
                flights: flights,
                airlines: airlines,
                totalDistanceKilometers: totalDistance,
                measuredDistanceFlightCount: measuredDistances.count,
                missingDistanceFlightCount: flights.count
                    - measuredDistances.count
            ))
        }
        return output
    }

    private static func routeID(_ record: FlightRecord) -> String {
        let departure = normalizedAirportCode(record.departureAirportIATA)
        let arrival = normalizedAirportCode(record.arrivalAirportIATA)
        let pair = [departure, arrival].sorted()
        return "\(pair[0])-\(pair[1])"
    }

    private static func canonicalAirports(
        for record: FlightRecord
    ) -> (AirportSnapshot, AirportSnapshot) {
        let departure = departureSnapshot(for: record)
        let arrival = arrivalSnapshot(for: record)
        if departure.iata <= arrival.iata {
            return (departure, arrival)
        }
        return (arrival, departure)
    }

    private static func departureSnapshot(
        for record: FlightRecord
    ) -> AirportSnapshot {
        AirportSnapshot(
            iata: normalizedAirportCode(record.departureAirportIATA),
            name: record.departureAirportName,
            city: record.departureCity,
            country: record.departureCountry,
            latitude: record.departureLatitude,
            longitude: record.departureLongitude,
            timeZoneID: record.departureTimeZoneID
        )
    }

    private static func arrivalSnapshot(
        for record: FlightRecord
    ) -> AirportSnapshot {
        AirportSnapshot(
            iata: normalizedAirportCode(record.arrivalAirportIATA),
            name: record.arrivalAirportName,
            city: record.arrivalCity,
            country: record.arrivalCountry,
            latitude: record.arrivalLatitude,
            longitude: record.arrivalLongitude,
            timeZoneID: record.arrivalTimeZoneID
        )
    }

    private static func normalizedAirportCode(_ value: String) -> String {
        let code = FlightRecordNormalization.code(value)
        return code.isEmpty ? "未知" : code
    }

    private static func airlineDescription(_ record: FlightRecord) -> String {
        let code = record.airlineCode.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let name = record.airlineName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return switch (code.isEmpty, name.isEmpty) {
        case (false, false): "\(code) · \(name)"
        case (false, true): code
        case (true, false): name
        case (true, true): "未知航司"
        }
    }

    private static func flightComesFirst(
        _ lhs: FlightRecord,
        _ rhs: FlightRecord
    ) -> Bool {
        if lhs.flightDate != rhs.flightDate {
            return lhs.flightDate > rhs.flightDate
        }
        if lhs.departureDate != rhs.departureDate {
            return lhs.departureDate > rhs.departureDate
        }
        if lhs.flightNumber != rhs.flightNumber {
            return lhs.flightNumber < rhs.flightNumber
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
