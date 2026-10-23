import Foundation

enum StatisticsSeriesRole: String, Equatable, Sendable {
    case routeAccent
    case secondaryRoute
    case dataGold
    case passport
}

enum StatisticsClassificationKind: String, CaseIterable, Equatable, Sendable {
    case domestic
    case international
    case unknown

    var title: String {
        switch self {
        case .domestic: "国内"
        case .international: "国际"
        case .unknown: "未知"
        }
    }
}

enum StatisticsSeriesPolicy {
    static func trendRole(
        for metric: StatisticsTrendMetric
    ) -> StatisticsSeriesRole {
        switch metric {
        case .flightCount: .routeAccent
        case .distance: .secondaryRoute
        case .duration: .dataGold
        }
    }

    static func classificationRole(
        for kind: StatisticsClassificationKind
    ) -> StatisticsSeriesRole {
        switch kind {
        case .domestic: .routeAccent
        case .international: .dataGold
        case .unknown: .passport
        }
    }
}

struct StatisticsYearOption: Identifiable, Equatable, Sendable {
    let selection: Int?
    let title: String
    let stamp: PassportStampPresentation

    var id: String {
        selection.map(String.init) ?? "all"
    }
}

struct StatisticsCoverageNotice: Identifiable, Equatable, Sendable {
    let id: String
    let message: String
    let systemImage: String
}

enum StatisticsRankingKind: Equatable, Sendable {
    case airport
    case airline
    case route
}

struct StatisticsRankingPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let count: Int
    let countText: String
    let airportCode: String?
    let routeBadge: RouteBadgePresentation?

    init(item: StatisticsRankingItem, kind: StatisticsRankingKind) {
        id = item.id
        label = item.label
        count = item.count
        countText = "\(item.count) 次"

        switch kind {
        case .airport:
            airportCode = Self.iata(item.id)
            routeBadge = nil
        case .airline:
            airportCode = nil
            routeBadge = nil
        case .route:
            airportCode = nil
            let endpoints = item.id.split(
                separator: "-",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            routeBadge = RouteBadgePresentation(
                departureIATA: endpoints.first.flatMap {
                    Self.iata(String($0))
                },
                arrivalIATA: endpoints.count > 1
                    ? Self.iata(String(endpoints[1]))
                    : nil
            )
        }
    }

    private static func iata(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !normalized.isEmpty,
            normalized != "未知",
            normalized != "unknown-airport"
        else {
            return nil
        }
        return normalized
    }
}

struct StatisticsClassificationItem: Identifiable, Equatable, Sendable {
    let kind: StatisticsClassificationKind
    let count: Int
    let percentage: Double
    let seriesRole: StatisticsSeriesRole

    var id: StatisticsClassificationKind { kind }
    var label: String { kind.title }

    var tooltip: String {
        "\(label) · \(count) 次 · \(Int((percentage * 100).rounded()))%"
    }
}

enum StatisticsPresentation {
    static func yearOptions(
        availableYears: [Int]
    ) -> [StatisticsYearOption] {
        let all = StatisticsYearOption(
            selection: nil,
            title: "全部年份",
            stamp: PassportStampPresentation(
                title: "全部",
                detail: "ALL YEARS"
            )
        )
        return [all] + Set(availableYears).sorted(by: >).map { year in
            StatisticsYearOption(
                selection: year,
                title: "\(year) 年",
                stamp: PassportStampPresentation(
                    title: String(year),
                    detail: "YEAR STAMP"
                )
            )
        }
    }

    static func coverageNotices(
        snapshot: StatisticsSnapshot
    ) -> [StatisticsCoverageNotice] {
        var notices: [StatisticsCoverageNotice] = []
        if snapshot.missingDistanceFlightCount > 0 {
            notices.append(
                StatisticsCoverageNotice(
                    id: "distance",
                    message: "\(snapshot.missingDistanceFlightCount) 次航班因机场坐标无效，未计入距离。",
                    systemImage: "exclamationmark.triangle"
                )
            )
        }
        if snapshot.missingDurationFlightCount > 0 {
            notices.append(
                StatisticsCoverageNotice(
                    id: "duration",
                    message: "\(snapshot.missingDurationFlightCount) 次航班因起降时间无有效正时长，未计入时长。",
                    systemImage: "exclamationmark.triangle"
                )
            )
        }
        if snapshot.unknownClassificationFlightCount > 0 {
            notices.append(
                StatisticsCoverageNotice(
                    id: "classification",
                    message: "\(snapshot.unknownClassificationFlightCount) 次航班缺少有效机场 ISO 国家码，保留为“未知”，未归入国内或国际。",
                    systemImage: "questionmark.circle"
                )
            )
        }
        return notices
    }

    static func coverageText(measured: Int, missing: Int) -> String? {
        guard missing > 0 else {
            return "\(measured) 次均可计算"
        }
        return "\(measured)/\(measured + missing) 次可计算，\(missing) 次缺失"
    }

    static func classificationItems(
        snapshot: StatisticsSnapshot
    ) -> [StatisticsClassificationItem] {
        let counts: [(StatisticsClassificationKind, Int)] = [
            (.domestic, snapshot.domesticFlightCount),
            (.international, snapshot.internationalFlightCount),
            (.unknown, snapshot.unknownClassificationFlightCount),
        ]
        let total = max(1, counts.reduce(0) { $0 + $1.1 })
        return counts.compactMap { kind, count in
            guard count > 0 else { return nil }
            return StatisticsClassificationItem(
                kind: kind,
                count: count,
                percentage: Double(count) / Double(total),
                seriesRole: StatisticsSeriesPolicy.classificationRole(for: kind)
            )
        }
    }

    static func tooltip(
        label: String,
        value: Double,
        metric: StatisticsTrendMetric,
        distanceUnit: DistanceUnit
    ) -> String {
        "\(label) · \(valueText(value, metric: metric, distanceUnit: distanceUnit))"
    }

    static func valueText(
        _ value: Double,
        metric: StatisticsTrendMetric,
        distanceUnit: DistanceUnit
    ) -> String {
        let formattedValue: String
        switch metric {
        case .flightCount:
            formattedValue = "\(Int(value.rounded())) 次"
        case .distance:
            let kilometers = switch distanceUnit {
            case .kilometers:
                value
            case .miles:
                value / 0.621_371_192_2
            }
            formattedValue = FlightMetricsService.standard.formattedDistance(
                kilometers: kilometers,
                unit: distanceUnit
            )
        case .duration:
            formattedValue = String(format: "%.1f 小时", value)
        }
        return formattedValue
    }
}
