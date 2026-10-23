enum FlightDisplayFormatting {
    static func duration(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else {
            return "未知"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if remainingMinutes == 0 {
            return "\(hours) 小时"
        }

        return "\(hours) 小时 \(remainingMinutes) 分钟"
    }

    static func routeDistance(
        kilometers: Double?,
        unit: FlightDistanceUnit,
        missingFlightCount: Int
    ) -> String {
        guard
            let kilometers,
            kilometers.isFinite,
            kilometers >= 0
        else {
            return "未知"
        }

        let distance = FlightMetricsService.standard.formattedDistance(
            kilometers: kilometers,
            unit: unit
        )
        guard missingFlightCount > 0 else {
            return distance
        }
        return "\(distance)（另有 \(missingFlightCount) 次无法计算）"
    }
}
