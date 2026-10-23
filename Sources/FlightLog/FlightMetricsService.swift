import Foundation

struct FlightCoordinate: Equatable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(airport: Airport) {
        self.init(
            latitude: airport.latitude,
            longitude: airport.longitude
        )
    }

    var isValid: Bool {
        latitude.isFinite
            && longitude.isFinite
            && (-90...90).contains(latitude)
            && (-180...180).contains(longitude)
    }
}

enum DistanceUnit: String, CaseIterable, Identifiable, Sendable {
    case kilometers = "km"
    case miles = "mi"

    var id: Self { self }

    var title: String {
        switch self {
        case .kilometers: "公里"
        case .miles: "英里"
        }
    }

    fileprivate var chineseName: String {
        title
    }

    func convert(kilometers: Double) -> Double {
        switch self {
        case .kilometers: kilometers
        case .miles: kilometers * 0.621_371_192_2
        }
    }
}

typealias FlightDistanceUnit = DistanceUnit

struct FlightMetricsService: Sendable {
    static let standard = FlightMetricsService()

    let earthRadiusKilometers: Double

    init(earthRadiusKilometers: Double = 6_371.008_8) {
        self.earthRadiusKilometers = earthRadiusKilometers
    }

    func distanceKilometers(
        from start: FlightCoordinate,
        to end: FlightCoordinate
    ) -> Double? {
        guard
            start.isValid,
            end.isValid,
            earthRadiusKilometers.isFinite,
            earthRadiusKilometers > 0
        else {
            return nil
        }

        let startLatitude = start.latitude.radians
        let endLatitude = end.latitude.radians
        let latitudeDelta = (end.latitude - start.latitude).radians
        let longitudeDelta = (end.longitude - start.longitude).radians

        let haversine = pow(sin(latitudeDelta / 2), 2)
            + cos(startLatitude)
                * cos(endLatitude)
                * pow(sin(longitudeDelta / 2), 2)
        let centralAngle = 2 * asin(sqrt(min(1, max(0, haversine))))
        return earthRadiusKilometers * centralAngle
    }

    func distanceKilometers(
        from departureAirport: Airport,
        to arrivalAirport: Airport
    ) -> Double? {
        distanceKilometers(
            from: FlightCoordinate(airport: departureAirport),
            to: FlightCoordinate(airport: arrivalAirport)
        )
    }

    func distanceKilometers(for record: FlightRecord) -> Double? {
        distanceKilometers(
            from: FlightCoordinate(
                latitude: record.departureLatitude,
                longitude: record.departureLongitude
            ),
            to: FlightCoordinate(
                latitude: record.arrivalLatitude,
                longitude: record.arrivalLongitude
            )
        )
    }

    func durationMinutes(
        departureDate: Date,
        arrivalDate: Date
    ) -> Int? {
        let interval = arrivalDate.timeIntervalSince(departureDate)
        guard interval.isFinite, interval > 0 else {
            return nil
        }
        return Int(interval / 60)
    }

    func durationMinutes(for record: FlightRecord) -> Int? {
        durationMinutes(
            departureDate: record.departureDate,
            arrivalDate: record.arrivalDate
        )
    }

    func formattedDistance(
        kilometers: Double,
        unit: DistanceUnit
    ) -> String {
        guard kilometers.isFinite, kilometers >= 0 else {
            return "无法计算"
        }

        let value = unit.convert(kilometers: kilometers)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = value < 100 ? 1 : 0
        let number = formatter.string(from: NSNumber(value: value))
            ?? String(format: "%.0f", value)
        return "\(number) \(unit.chineseName)"
    }
}

private extension Double {
    var radians: Double {
        self * .pi / 180
    }
}
