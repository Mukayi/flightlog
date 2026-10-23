import Foundation

enum GreatCircleRouteSampler {
    static func sample(
        from start: FlightCoordinate,
        to end: FlightCoordinate,
        segmentCount: Int = 64
    ) -> [FlightCoordinate] {
        guard start.isValid, end.isValid else {
            return []
        }
        guard start != end else {
            return [start, end]
        }

        let startVector = Vector3(coordinate: start)
        let endVector = Vector3(coordinate: end)
        let dotProduct = min(1, max(-1, startVector.dot(endVector)))
        let angle = acos(dotProduct)
        let angleSine = sin(angle)
        guard angle.isFinite, abs(angleSine) > 0.000_000_000_001 else {
            return [start, end]
        }

        let count = max(1, segmentCount)
        var coordinates = (0...count).map { index in
            let progress = Double(index) / Double(count)
            let startWeight = sin((1 - progress) * angle) / angleSine
            let endWeight = sin(progress * angle) / angleSine
            return (startVector * startWeight + endVector * endWeight)
                .coordinate
        }
        coordinates[0] = start
        coordinates[count] = end
        return coordinates
    }

    static func sampleSegments(
        from start: FlightCoordinate,
        to end: FlightCoordinate,
        segmentCount: Int = 64
    ) -> [[FlightCoordinate]] {
        splitAtAntimeridian(
            sample(
                from: start,
                to: end,
                segmentCount: segmentCount
            )
        )
    }

    static func splitAtAntimeridian(
        _ coordinates: [FlightCoordinate]
    ) -> [[FlightCoordinate]] {
        guard let first = coordinates.first else {
            return []
        }
        guard coordinates.count > 1 else {
            return [[first]]
        }

        var result: [[FlightCoordinate]] = []
        var currentSegment = [first]
        var previous = first

        for coordinate in coordinates.dropFirst() {
            let longitudeDelta = coordinate.longitude - previous.longitude
            if abs(longitudeDelta) > 180 {
                let crossesEastward = previous.longitude > 0
                    && coordinate.longitude < 0
                let boundaryLongitude = crossesEastward ? 180.0 : -180.0
                let oppositeBoundary = -boundaryLongitude
                let adjustedLongitude = coordinate.longitude
                    + (crossesEastward ? 360 : -360)
                let boundaryLatitude = interpolatedLatitude(
                    from: previous,
                    previousLongitude: previous.longitude,
                    to: coordinate,
                    longitude: adjustedLongitude,
                    boundaryLongitude: boundaryLongitude
                )
                appendIfNeeded(
                    FlightCoordinate(
                        latitude: boundaryLatitude,
                        longitude: boundaryLongitude
                    ),
                    to: &currentSegment
                )
                if currentSegment.count >= 2 {
                    result.append(currentSegment)
                }
                currentSegment = [
                    FlightCoordinate(
                        latitude: boundaryLatitude,
                        longitude: oppositeBoundary
                    )
                ]
            }

            appendIfNeeded(
                FlightCoordinate(
                    latitude: coordinate.latitude,
                    longitude: normalizedLongitude(coordinate.longitude)
                ),
                to: &currentSegment
            )
            previous = coordinate
        }

        if currentSegment.count >= 2 || result.isEmpty {
            result.append(currentSegment)
        }
        return result
    }

    private static func interpolatedLatitude(
        from start: FlightCoordinate,
        previousLongitude: Double,
        to end: FlightCoordinate,
        longitude: Double,
        boundaryLongitude: Double
    ) -> Double {
        let longitudeDelta = longitude - previousLongitude
        guard abs(longitudeDelta) > 0.000_000_000_001 else {
            return start.latitude
        }
        let progress = (boundaryLongitude - previousLongitude)
            / longitudeDelta
        return start.latitude + (end.latitude - start.latitude) * progress
    }

    private static func appendIfNeeded(
        _ coordinate: FlightCoordinate,
        to coordinates: inout [FlightCoordinate]
    ) {
        if coordinates.last != coordinate {
            coordinates.append(coordinate)
        }
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        var normalized = longitude.truncatingRemainder(dividingBy: 360)
        if normalized > 180 {
            normalized -= 360
        } else if normalized < -180 {
            normalized += 360
        }
        return normalized
    }
}

private struct Vector3 {
    let x: Double
    let y: Double
    let z: Double

    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(coordinate: FlightCoordinate) {
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180
        x = cos(latitude) * cos(longitude)
        y = cos(latitude) * sin(longitude)
        z = sin(latitude)
    }

    var coordinate: FlightCoordinate {
        let magnitude = sqrt(x * x + y * y + z * z)
        guard magnitude > 0 else {
            return FlightCoordinate(latitude: 0, longitude: 0)
        }
        return FlightCoordinate(
            latitude: asin(z / magnitude) * 180 / .pi,
            longitude: atan2(y, x) * 180 / .pi
        )
    }

    static func * (lhs: Self, rhs: Double) -> Self {
        Self(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    func dot(_ other: Self) -> Double {
        x * other.x + y * other.y + z * other.z
    }
}
