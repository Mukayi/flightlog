import Foundation

typealias BoardingPassPresentation = FlightPresentation

struct OverviewRecentFlightPresentation: Identifiable, Equatable, Sendable {
    let id: UUID
    let boardingPass: BoardingPassPresentation
}

enum OverviewMetricID: String, CaseIterable, Equatable, Sendable {
    case flights
    case distance
    case duration
    case airports
    case cities
    case countries
}

struct OverviewHeroPresentation: Equatable, Sendable {
    let title: String
    let holder: String
    let firstFlightYear: String
    let totalFlights: String
    let totalDistance: String
}

struct OverviewMetricPresentation: Identifiable, Equatable, Sendable {
    let id: OverviewMetricID
    let card: MetricStampPresentation
    let explanation: String
}

struct OverviewYearbookPoint: Identifiable, Equatable, Sendable {
    let year: Int
    let flightCount: Int

    var id: Int { year }

    var hoverText: String {
        "\(year) 年 · \(flightCount) 次航班"
    }
}

struct OverviewPresentation {
    let hero: OverviewHeroPresentation
    let metrics: [OverviewMetricPresentation]
    let yearbook: [OverviewYearbookPoint]
    let recentFlights: [OverviewRecentFlightPresentation]
    let distanceUnit: DistanceUnit

    init(
        records: [FlightRecord],
        snapshot: StatisticsSnapshot,
        distanceUnit: DistanceUnit,
        holderDisplayName: String? = nil
    ) {
        self.distanceUnit = distanceUnit
        let normalizedHolder = holderDisplayName.map(
            UserProfileNameValidator.normalize
        )
        hero = OverviewHeroPresentation(
            title: "我的飞行护照",
            holder: normalizedHolder?.isEmpty == false
                ? normalizedHolder!
                : UserProfileDefaults.displayName,
            firstFlightYear: records
                .map { Self.year(for: $0.flightDate) }
                .min()
                .map(String.init) ?? "—",
            totalFlights: "\(snapshot.totalFlightCount) 次",
            totalDistance: Self.distance(
                snapshot.totalDistanceKilometers,
                unit: distanceUnit
            )
        )
        metrics = Self.metrics(snapshot: snapshot, distanceUnit: distanceUnit)
        yearbook = snapshot.yearlyTrend.map {
            OverviewYearbookPoint(
                year: $0.year,
                flightCount: $0.flightCount
            )
        }
        recentFlights = OverviewFlightOrdering.recent(records)
            .prefix(5)
            .map {
                OverviewRecentFlightPresentation(
                    id: $0.id,
                    boardingPass: Self.boardingPass($0)
                )
            }
    }

    private static func metrics(
        snapshot: StatisticsSnapshot,
        distanceUnit: DistanceUnit
    ) -> [OverviewMetricPresentation] {
        [
            metric(
                .flights,
                title: "飞行次数",
                value: "\(snapshot.totalFlightCount) 次",
                systemImage: "airplane",
                explanation: "包含全部已保存的航班记录。"
            ),
            metric(
                .distance,
                title: "累计里程",
                value: distance(
                    snapshot.totalDistanceKilometers,
                    unit: distanceUnit
                ),
                systemImage: "ruler",
                explanation: coverageExplanation(
                    measured: snapshot.measuredDistanceFlightCount,
                    missing: snapshot.missingDistanceFlightCount,
                    noun: "里程"
                )
            ),
            metric(
                .duration,
                title: "累计时长",
                value: FlightDisplayFormatting.duration(
                    minutes: snapshot.totalDurationMinutes
                ),
                systemImage: "clock",
                explanation: coverageExplanation(
                    measured: snapshot.measuredDurationFlightCount,
                    missing: snapshot.missingDurationFlightCount,
                    noun: "时长"
                )
            ),
            metric(
                .airports,
                title: "到访机场",
                value: knownCount(snapshot.uniqueAirportCount),
                systemImage: "building.2",
                explanation: "仅统计有 IATA 代码的出发与到达机场，并按 IATA 代码去重；同一机场多次到访只计一次。"
            ),
            metric(
                .cities,
                title: "到访城市",
                value: knownCount(snapshot.uniqueCityCount),
                systemImage: "building.2.crop.circle",
                explanation: "按城市与国家/地区组合去重；同城多个机场只计一个城市。"
            ),
            metric(
                .countries,
                title: "到访国家",
                value: knownCount(snapshot.uniqueCountryCount),
                systemImage: "globe.asia.australia",
                explanation: "按已知国家/地区代码或名称去重；资料未知的地点不计入。"
            ),
        ]
    }

    private static func metric(
        _ id: OverviewMetricID,
        title: String,
        value: String,
        systemImage: String,
        explanation: String
    ) -> OverviewMetricPresentation {
        OverviewMetricPresentation(
            id: id,
            card: MetricStampPresentation(
                title: title,
                value: value,
                detail: nil,
                systemImage: systemImage
            ),
            explanation: explanation
        )
    }

    private static func distance(
        _ kilometers: Double?,
        unit: DistanceUnit
    ) -> String {
        FlightDisplayFormatting.routeDistance(
            kilometers: kilometers,
            unit: unit,
            missingFlightCount: 0
        )
    }

    private static func knownCount(_ count: Int) -> String {
        count > 0 ? "\(count) 个" : "未知"
    }

    private static func coverageExplanation(
        measured: Int,
        missing: Int,
        noun: String
    ) -> String {
        guard missing > 0 else {
            return measured > 0
                ? "全部 \(measured) 次航班均有可计算\(noun)。"
                : "尚无可计算\(noun)的航班。"
        }
        return "\(measured)/\(measured + missing) 次航班可计算\(noun)，另有 \(missing) 次资料缺失。"
    }

    private static func boardingPass(
        _ record: FlightRecord
    ) -> BoardingPassPresentation {
        BoardingPassPresentation(
            flightNumber: record.flightNumber,
            date: dateText(record.flightDate),
            airline: airlineText(record),
            departure: FlightEndpointPresentation(
                iata: record.departureAirportIATA,
                city: record.departureCity,
                localTime: localTime(
                    snapshot: record.departureLocalDateTime,
                    absoluteDate: record.departureDate,
                    timeZoneID: record.departureTimeZoneID
                )
            ),
            arrival: FlightEndpointPresentation(
                iata: record.arrivalAirportIATA,
                city: record.arrivalCity,
                localTime: localTime(
                    snapshot: record.arrivalLocalDateTime,
                    absoluteDate: record.arrivalDate,
                    timeZoneID: record.arrivalTimeZoneID
                )
            ),
            duration: FlightDisplayFormatting.duration(
                minutes: FlightMetricsService.standard.durationMinutes(for: record)
            )
        )
    }

    private static func airlineText(_ record: FlightRecord) -> String? {
        let code = FlightRecordNormalization.code(record.airlineCode)
        let name = record.airlineName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return switch (code.isEmpty, name.isEmpty) {
        case (false, false): "\(code) · \(name)"
        case (false, true): code
        case (true, false): name
        case (true, true): nil
        }
    }

    private static func year(for date: Date) -> Int {
        utcCalendar.component(.year, from: date)
    }

    private static func dateText(_ date: Date) -> String {
        formatter("yyyy年M月d日").string(from: date)
    }

    private static func localTime(
        snapshot: String?,
        absoluteDate: Date,
        timeZoneID: String
    ) -> String {
        let date = HistoricalLocalTime.wallClockDate(
            snapshot: snapshot,
            absoluteDate: absoluteDate,
            timeZoneID: timeZoneID
        )
        return formatter("HH:mm").string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
