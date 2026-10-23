import XCTest
@testable import FlightLog

final class StatisticsVisualTests: XCTestCase {
    func testYearOptionsKeepAllFirstAndStableDescendingYears() {
        let options = StatisticsPresentation.yearOptions(
            availableYears: [2024, 2026, 2025, 2026]
        )

        XCTAssertEqual(options.map(\.selection), [nil, 2026, 2025, 2024])
        XCTAssertEqual(options.map(\.title), ["全部年份", "2026 年", "2025 年", "2024 年"])
        XCTAssertEqual(options.first?.stamp.detail, "ALL YEARS")
    }

    func testBrandSeriesMappingIsStableAcrossTrendAndClassification() {
        XCTAssertEqual(
            StatisticsSeriesPolicy.trendRole(for: .flightCount),
            .routeAccent
        )
        XCTAssertEqual(
            StatisticsSeriesPolicy.trendRole(for: .distance),
            .secondaryRoute
        )
        XCTAssertEqual(
            StatisticsSeriesPolicy.trendRole(for: .duration),
            .dataGold
        )
        XCTAssertEqual(
            StatisticsSeriesPolicy.classificationRole(for: .domestic),
            .routeAccent
        )
        XCTAssertEqual(
            StatisticsSeriesPolicy.classificationRole(for: .international),
            .dataGold
        )
        XCTAssertEqual(
            StatisticsSeriesPolicy.classificationRole(for: .unknown),
            .passport
        )
    }

    func testStatisticsGoldTokensMeetTextAndMarkContrastOnEverySurface() {
        for appearance in FlightTheme.Appearance.allCases {
            for contrast in [FlightTheme.Contrast.standard, .increased] {
                let palette = FlightTheme.palette(
                    for: appearance,
                    contrast: contrast
                )

                for (surface, background) in [
                    ("paper", palette.paper),
                    ("archiveCard", palette.archiveCard),
                ] {
                    XCTAssertGreaterThanOrEqual(
                        palette.goldInk.contrastRatio(with: background),
                        FlightTheme.ContrastThreshold.ordinaryText,
                        "\(appearance) \(contrast) goldInk on \(surface)"
                    )
                    XCTAssertGreaterThanOrEqual(
                        palette.dataGold.contrastRatio(with: background),
                        FlightTheme.ContrastThreshold.largeText,
                        "\(appearance) \(contrast) dataGold on \(surface)"
                    )
                }

                if appearance == .light {
                    XCTAssertNotEqual(
                        palette.goldInk,
                        palette.warmGold,
                        "\(contrast) must not use decorative warmGold for small paper text"
                    )
                }
            }
        }
    }

    func testUnknownAndPartialCoverageNoticesRemainExplicit() {
        let notices = StatisticsPresentation.coverageNotices(
            snapshot: snapshot(
                measuredDistance: 2,
                missingDistance: 1,
                measuredDuration: 1,
                missingDuration: 2,
                unknownClassification: 1
            )
        )

        XCTAssertEqual(
            notices.map(\.message),
            [
                "1 次航班因机场坐标无效，未计入距离。",
                "2 次航班因起降时间无有效正时长，未计入时长。",
                "1 次航班缺少有效机场 ISO 国家码，保留为“未知”，未归入国内或国际。",
            ]
        )
        XCTAssertEqual(
            StatisticsPresentation.coverageText(measured: 2, missing: 1),
            "2/3 次可计算，1 次缺失"
        )
    }

    func testRankingRouteBadgeNormalizesMissingIATAWithoutDroppingLabel() {
        let item = StatisticsRankingItem(
            id: "PVG-未知",
            label: "上海浦东国际机场 → 很长的未知机场标签",
            count: 3
        )

        let presentation = StatisticsRankingPresentation(
            item: item,
            kind: .route
        )

        XCTAssertEqual(presentation.routeBadge?.departureIATA, "PVG")
        XCTAssertEqual(presentation.routeBadge?.arrivalIATA, "Unknown")
        XCTAssertEqual(presentation.label, item.label)
        XCTAssertEqual(presentation.countText, "3 次")
    }

    func testDomesticInternationalRatioKeepsUnknownAsItsOwnShare() {
        let items = StatisticsPresentation.classificationItems(
            snapshot: snapshot(
                domestic: 2,
                international: 1,
                unknownClassification: 1
            )
        )

        XCTAssertEqual(items.map(\.kind), [.domestic, .international, .unknown])
        XCTAssertEqual(items.map(\.count), [2, 1, 1])
        XCTAssertEqual(items.map(\.percentage), [0.5, 0.25, 0.25])
        XCTAssertEqual(items[0].tooltip, "国内 · 2 次 · 50%")
    }

    func testTrendTooltipPreservesDistanceUnitAndDurationHours() {
        XCTAssertEqual(
            StatisticsPresentation.tooltip(
                label: "2026 年",
                value: 621.371_192_2,
                metric: .distance,
                distanceUnit: .miles
            ),
            "2026 年 · 621 英里"
        )
        XCTAssertEqual(
            StatisticsPresentation.tooltip(
                label: "2026 年",
                value: 1.5,
                metric: .duration,
                distanceUnit: .kilometers
            ),
            "2026 年 · 1.5 小时"
        )
        XCTAssertEqual(
            StatisticsTrendMetric.distance.chartSubtitle(distanceUnit: .miles),
            "有效距离（mi）"
        )
    }

    private func snapshot(
        measuredDistance: Int = 0,
        missingDistance: Int = 0,
        measuredDuration: Int = 0,
        missingDuration: Int = 0,
        domestic: Int = 0,
        international: Int = 0,
        unknownClassification: Int = 0
    ) -> StatisticsSnapshot {
        StatisticsSnapshot(
            totalFlightCount: domestic + international + unknownClassification,
            totalDistanceKilometers: measuredDistance > 0 ? 1 : nil,
            measuredDistanceFlightCount: measuredDistance,
            missingDistanceFlightCount: missingDistance,
            totalDurationMinutes: measuredDuration > 0 ? 1 : nil,
            measuredDurationFlightCount: measuredDuration,
            missingDurationFlightCount: missingDuration,
            uniqueAirportCount: 0,
            uniqueCityCount: 0,
            uniqueCountryCount: 0,
            domesticFlightCount: domestic,
            internationalFlightCount: international,
            unknownClassificationFlightCount: unknownClassification,
            airportRankings: [],
            airlineRankings: [],
            routeRankings: [],
            longestFlights: [],
            yearlyTrend: [],
            monthlyTrend: []
        )
    }
}
