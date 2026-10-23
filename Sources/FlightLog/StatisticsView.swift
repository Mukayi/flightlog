import Charts
import SwiftData
import SwiftUI

struct StatisticsView: View {
    @Query
    private var records: [FlightRecord]

    let profileID: UUID
    private let mountID = UUID()
    @State private var selectedYear: Int?
    @State private var trendMetric: StatisticsTrendMetric = .flightCount
    @AppStorage("statistics.distanceUnit")
    private var distanceUnit: DistanceUnit = .kilometers

    private let statistics = FlightStatisticsService()

    init(profileID: UUID = UserProfileDefaults.id) {
        self.profileID = profileID
        let ownerID: UUID? = profileID
        _records = Query(
            filter: #Predicate { $0.ownerProfileID == ownerID },
            sort: \.flightDate
        )
    }

    var body: some View {
        let viewData = statistics.viewData(
            records,
            selectedYear: selectedYear
        )
        let years = viewData.availableYears
        let snapshot = viewData.snapshot

        VStack(spacing: 0) {
            filterBar(
                years: years,
                visibleFlightCount: snapshot.totalFlightCount
            )
            Divider()

            if records.isEmpty {
                ContentUnavailableView(
                    "还没有可统计的航班",
                    systemImage: "chart.bar.xaxis",
                    description: Text("录入航班后，这里会生成趋势、排行和飞行构成。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshot.totalFlightCount == 0 {
                ContentUnavailableView {
                    Label(
                        "筛选范围内没有航班",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                } description: {
                    Text("请选择其他年份或查看全部年份。")
                } actions: {
                    Button("查看全部年份") {
                        selectedYear = nil
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                statisticsContent(snapshot)
            }
        }
        .onChange(of: years) { _, availableYears in
            if
                let selectedYear,
                !availableYears.contains(selectedYear)
            {
                self.selectedYear = nil
            }
        }
        .onChange(of: profileID) {
            selectedYear = nil
            trendMetric = .flightCount
        }
        .onAppear(perform: reportProfileScope)
        .onChange(of: records.map(\.id)) {
            reportProfileScope()
        }
    }

    private func reportProfileScope() {
        #if DEBUG
        ProfileScopeMountProbe.record(
            ProfileScopeMountSnapshot(
                section: .statistics,
                profileID: profileID,
                recordCount: records.count,
                holderDisplayName: nil,
                mountID: mountID
            )
        )
        #endif
    }

    private func filterBar(
        years: [Int],
        visibleFlightCount: Int
    ) -> some View {
        let options = StatisticsPresentation.yearOptions(
            availableYears: years
        )
        let selectedOption = options.first {
            $0.selection == selectedYear
        } ?? options[0]

        return ScrollView(.horizontal) {
            HStack(spacing: 14) {
                Picker(selection: $selectedYear) {
                    ForEach(options) { option in
                        Text(option.title).tag(option.selection)
                    }
                } label: {
                    PassportStamp(presentation: selectedOption.stamp)
                }
                .pickerStyle(.menu)
                .accessibilityLabel("年份")
                .accessibilityValue(selectedOption.title)
                .frame(minWidth: 168)

                Picker("距离单位", selection: $distanceUnit) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)

                Spacer(minLength: 12)

                Text("\(visibleFlightCount) 次航班")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private func statisticsContent(
        _ snapshot: StatisticsSnapshot
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                metricGrid(snapshot)
                dataQualityNotice(snapshot)

                VStack(alignment: .leading, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            trendHeading
                            Spacer()
                            Picker("趋势指标", selection: $trendMetric) {
                                ForEach(StatisticsTrendMetric.allCases) { metric in
                                    Text(metric.title).tag(metric)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 360)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            trendHeading
                            Picker("趋势指标", selection: $trendMetric) {
                                ForEach(StatisticsTrendMetric.allCases) { metric in
                                    Text(metric.title).tag(metric)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: 350, maximum: 720),
                                spacing: 18
                            ),
                        ],
                        spacing: 18
                    ) {
                        AnnualTrendChart(
                            points: snapshot.yearlyTrend,
                            metric: trendMetric,
                            distanceUnit: distanceUnit
                        )
                        MonthlyTrendChart(
                            points: snapshot.monthlyTrend,
                            metric: trendMetric,
                            distanceUnit: distanceUnit,
                            usesShortMonthLabels: selectedYear != nil
                        )
                    }
                }

                rankingSection(snapshot)

                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 350, maximum: 720),
                            spacing: 18
                        ),
                    ],
                    spacing: 18
                ) {
                    LongestFlightsChart(
                        flights: Array(snapshot.longestFlights.prefix(8)),
                        distanceUnit: distanceUnit
                    )
                    FlightClassificationChart(snapshot: snapshot)
                }
            }
            .padding(28)
            .frame(maxWidth: 1_080)
            .frame(maxWidth: .infinity)
        }
    }

    private var trendHeading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("趋势")
                .font(.title2.bold())
            Text("月份键使用 UTC 公历，不随用户时区变化")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metricGrid(
        _ snapshot: StatisticsSnapshot
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 205, maximum: 320), spacing: 16),
            ],
            alignment: .leading,
            spacing: 16
        ) {
            MetricStampCard(
                presentation: MetricStampPresentation(
                    title: "航班总数",
                    value: "\(snapshot.totalFlightCount) 次",
                    detail: nil,
                    systemImage: "airplane"
                )
            )
            MetricStampCard(
                presentation: MetricStampPresentation(
                    title: "有效累计距离",
                    value: formattedDistance(snapshot.totalDistanceKilometers),
                    detail: StatisticsPresentation.coverageText(
                        measured: snapshot.measuredDistanceFlightCount,
                        missing: snapshot.missingDistanceFlightCount
                    ),
                    systemImage: "ruler"
                )
            )
            MetricStampCard(
                presentation: MetricStampPresentation(
                    title: "有效累计时长",
                    value: FlightDisplayFormatting.duration(
                        minutes: snapshot.totalDurationMinutes
                    ),
                    detail: StatisticsPresentation.coverageText(
                        measured: snapshot.measuredDurationFlightCount,
                        missing: snapshot.missingDurationFlightCount
                    ),
                    systemImage: "clock"
                )
            )
            MetricStampCard(
                presentation: MetricStampPresentation(
                    title: VisitMetricPresentation.airportTitle,
                    value: knownCount(snapshot.uniqueAirportCount),
                    detail: VisitMetricPresentation.airportDetail,
                    systemImage: "building.2"
                )
            )
            MetricStampCard(
                presentation: MetricStampPresentation(
                    title: VisitMetricPresentation.cityTitle,
                    value: knownCount(snapshot.uniqueCityCount),
                    detail: VisitMetricPresentation.cityDetail,
                    systemImage: "building.2.crop.circle"
                )
            )
            MetricStampCard(
                presentation: MetricStampPresentation(
                    title: "唯一国家/地区",
                    value: knownCount(snapshot.uniqueCountryCount),
                    detail: nil,
                    systemImage: "globe"
                )
            )
        }
    }

    @ViewBuilder
    private func dataQualityNotice(
        _ snapshot: StatisticsSnapshot
    ) -> some View {
        let notices = StatisticsPresentation.coverageNotices(snapshot: snapshot)
        if !notices.isEmpty {
            PassportSurface(.archiveCard) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("数据完整性")
                        .font(FlightTheme.Typography.serif(.headline, weight: .semibold))
                    ForEach(notices) { notice in
                        Label(notice.message, systemImage: notice.systemImage)
                    }
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(FlightTheme.Spacing.md)
            }
        }
    }

    private func rankingSection(
        _ snapshot: StatisticsSnapshot
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("常用排行")
                .font(.title2.bold())

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 340, maximum: 620),
                        spacing: 18
                    ),
                ],
                spacing: 18
            ) {
                RankingChartCard(
                    title: "常用机场",
                    systemImage: "building.2",
                    items: Array(snapshot.airportRankings.prefix(8)),
                    kind: .airport,
                    footnote: "每趟航班起飞和到达各计一次；次数并列时按机场代码和标签稳定排序。"
                )
                RankingChartCard(
                    title: "常用航司",
                    systemImage: "airplane.circle",
                    items: Array(snapshot.airlineRankings.prefix(8)),
                    kind: .airline,
                    footnote: "缺少代码和名称的记录归入“未知航司”；并列时未知项排在已知项之后。"
                )
                RankingChartCard(
                    title: "常用航线",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    items: Array(snapshot.routeRankings.prefix(8)),
                    kind: .route,
                    footnote: "沿用地图聚合语义：AAA → BBB 与 BBB → AAA 合并；并列时按稳定航线键排序。"
                )
            }
        }
    }

    private func formattedDistance(_ kilometers: Double?) -> String {
        FlightDisplayFormatting.routeDistance(
            kilometers: kilometers,
            unit: distanceUnit,
            missingFlightCount: 0
        )
    }

    private func knownCount(_ count: Int) -> String {
        count > 0 ? "\(count)" : "未知"
    }
}

enum StatisticsTrendMetric: String, CaseIterable, Identifiable {
    case flightCount
    case distance
    case duration

    var id: Self { self }

    var title: String {
        switch self {
        case .flightCount: "航班次数"
        case .distance: "有效距离"
        case .duration: "有效时长"
        }
    }

    func value(
        flightCount: Int,
        distanceKilometers: Double?,
        durationMinutes: Int?,
        distanceUnit: DistanceUnit
    ) -> Double? {
        switch self {
        case .flightCount:
            Double(flightCount)
        case .distance:
            distanceKilometers.map(distanceUnit.convert(kilometers:))
        case .duration:
            durationMinutes.map { Double($0) / 60 }
        }
    }

    func missingCount(
        distance: Int,
        duration: Int
    ) -> Int {
        switch self {
        case .flightCount: 0
        case .distance: distance
        case .duration: duration
        }
    }

    var unitLabel: String {
        switch self {
        case .flightCount: "次"
        case .distance: ""
        case .duration: "小时"
        }
    }

    func chartSubtitle(distanceUnit: DistanceUnit) -> String {
        let label = self == .distance
            ? distanceUnit.rawValue
            : unitLabel
        return "\(title)（\(label)）"
    }
}

private struct AnnualTrendChart: View {
    let points: [YearlyStatisticsTrend]
    let metric: StatisticsTrendMetric
    let distanceUnit: DistanceUnit
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast
    @State private var hoveredYear: Int?

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        StatisticsChartContainer(
            title: "年度趋势",
            subtitle: chartSubtitle,
            missingCount: missingCount
        ) {
            if hasValues {
                ScrollView(.horizontal) {
                    Chart(points) { point in
                        if let value = value(point) {
                            BarMark(
                                x: .value("年份", point.year),
                                y: .value(metric.title, value)
                            )
                            .foregroundStyle(
                                statisticsColor(
                                    StatisticsSeriesPolicy.trendRole(for: metric),
                                    palette: palette,
                                    colorScheme: colorScheme
                                ).gradient
                            )
                            .annotation(position: .top) {
                                if hoveredYear == point.year {
                                    Text(
                                        StatisticsPresentation.tooltip(
                                            label: "\(point.year) 年",
                                            value: value,
                                            metric: metric,
                                            distanceUnit: distanceUnit
                                        )
                                    )
                                    .font(.caption)
                                    .padding(.horizontal, FlightTheme.Spacing.xs)
                                    .padding(.vertical, FlightTheme.Spacing.xxs)
                                    .background(
                                        palette.archiveCard.color,
                                        in: Capsule()
                                    )
                                    .fixedSize()
                                }
                            }
                            .accessibilityLabel("\(point.year) 年")
                            .accessibilityValue(accessibilityValue(value))
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    updateHover(
                                        phase,
                                        proxy: proxy,
                                        geometry: geometry
                                    )
                                }
                        }
                    }
                    .frame(
                        minWidth: max(520, CGFloat(points.count) * 72),
                        minHeight: 230
                    )
                }
            } else {
                missingChartView
            }
        }
    }

    private var hasValues: Bool {
        points.contains { value($0) != nil }
    }

    private var missingCount: Int {
        points.reduce(0) {
            $0 + metric.missingCount(
                distance: $1.missingDistanceFlightCount,
                duration: $1.missingDurationFlightCount
            )
        }
    }

    private var chartSubtitle: String {
        metric.chartSubtitle(distanceUnit: distanceUnit)
    }

    private func value(_ point: YearlyStatisticsTrend) -> Double? {
        metric.value(
            flightCount: point.flightCount,
            distanceKilometers: point.totalDistanceKilometers,
            durationMinutes: point.totalDurationMinutes,
            distanceUnit: distanceUnit
        )
    }

    private func accessibilityValue(_ value: Double) -> String {
        StatisticsPresentation.valueText(
            value,
            metric: metric,
            distanceUnit: distanceUnit
        )
    }

    private func updateHover(
        _ phase: HoverPhase,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        switch phase {
        case let .active(location):
            guard let plotFrame = proxy.plotFrame else {
                hoveredYear = nil
                return
            }
            let frame = geometry[plotFrame]
            guard frame.contains(location) else {
                hoveredYear = nil
                return
            }
            let x = location.x - frame.minX
            guard let year = proxy.value(atX: x, as: Int.self) else {
                hoveredYear = nil
                return
            }
            hoveredYear = points.min {
                abs($0.year - year) < abs($1.year - year)
            }?.year
        case .ended:
            hoveredYear = nil
        }
    }

    private var missingChartView: some View {
        ContentUnavailableView(
            "没有有效\(metric.title)",
            systemImage: "chart.bar.xaxis",
            description: Text("当前筛选范围只有缺失值，未用 0 代替。")
        )
        .frame(maxWidth: .infinity, minHeight: 230)
    }
}

private struct MonthlyTrendChart: View {
    let points: [MonthlyStatisticsTrend]
    let metric: StatisticsTrendMetric
    let distanceUnit: DistanceUnit
    let usesShortMonthLabels: Bool
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast
    @State private var hoveredMonthID: String?

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        StatisticsChartContainer(
            title: "月度趋势",
            subtitle: chartSubtitle,
            missingCount: missingCount
        ) {
            if hasValues {
                ScrollView(.horizontal) {
                    Chart(points) { point in
                        if let value = value(point) {
                            BarMark(
                                x: .value("月份", point.month.id),
                                y: .value(metric.title, value)
                            )
                            .foregroundStyle(
                                statisticsColor(
                                    StatisticsSeriesPolicy.trendRole(for: metric),
                                    palette: palette,
                                    colorScheme: colorScheme
                                ).gradient
                            )
                            .annotation(position: .top) {
                                if hoveredMonthID == point.month.id {
                                    Text(
                                        StatisticsPresentation.tooltip(
                                            label: point.month.label,
                                            value: value,
                                            metric: metric,
                                            distanceUnit: distanceUnit
                                        )
                                    )
                                    .font(.caption)
                                    .padding(.horizontal, FlightTheme.Spacing.xs)
                                    .padding(.vertical, FlightTheme.Spacing.xxs)
                                    .background(
                                        palette.archiveCard.color,
                                        in: Capsule()
                                    )
                                    .fixedSize()
                                }
                            }
                            .accessibilityLabel(point.month.label)
                            .accessibilityValue(
                                StatisticsPresentation.tooltip(
                                    label: point.month.label,
                                    value: value,
                                    metric: metric,
                                    distanceUnit: distanceUnit
                                )
                            )
                        }
                    }
                    .chartXAxis {
                        AxisMarks { axisValue in
                            AxisValueLabel {
                                if
                                    let id = axisValue.as(String.self),
                                    let point = points.first(
                                        where: { $0.month.id == id }
                                    )
                                {
                                    Text(
                                        usesShortMonthLabels
                                            ? point.month.shortLabel
                                            : point.month.id
                                    )
                                }
                            }
                        }
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    updateHover(
                                        phase,
                                        proxy: proxy,
                                        geometry: geometry
                                    )
                                }
                        }
                    }
                    .frame(
                        minWidth: max(520, CGFloat(points.count) * 62),
                        minHeight: 230
                    )
                }
            } else {
                ContentUnavailableView(
                    "没有有效\(metric.title)",
                    systemImage: "chart.bar.xaxis",
                    description: Text("当前筛选范围只有缺失值，未用 0 代替。")
                )
                .frame(maxWidth: .infinity, minHeight: 230)
            }
        }
    }

    private var hasValues: Bool {
        points.contains { value($0) != nil }
    }

    private var missingCount: Int {
        points.reduce(0) {
            $0 + metric.missingCount(
                distance: $1.missingDistanceFlightCount,
                duration: $1.missingDurationFlightCount
            )
        }
    }

    private var chartSubtitle: String {
        metric.chartSubtitle(distanceUnit: distanceUnit)
    }

    private func value(_ point: MonthlyStatisticsTrend) -> Double? {
        metric.value(
            flightCount: point.flightCount,
            distanceKilometers: point.totalDistanceKilometers,
            durationMinutes: point.totalDurationMinutes,
            distanceUnit: distanceUnit
        )
    }

    private func updateHover(
        _ phase: HoverPhase,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        switch phase {
        case let .active(location):
            guard let plotFrame = proxy.plotFrame else {
                hoveredMonthID = nil
                return
            }
            let frame = geometry[plotFrame]
            guard frame.contains(location) else {
                hoveredMonthID = nil
                return
            }
            hoveredMonthID = proxy.value(
                atX: location.x - frame.minX,
                as: String.self
            )
        case .ended:
            hoveredMonthID = nil
        }
    }
}

private struct StatisticsChartContainer<Content: View>: View {
    let title: String
    let subtitle: String
    let missingCount: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            content()

            if missingCount > 0 {
                Text("\(missingCount) 次缺失记录未计入该指标。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .passportSurface(.paper)
    }
}

private struct RankingChartCard: View {
    let title: String
    let systemImage: String
    let items: [StatisticsRankingItem]
    let kind: StatisticsRankingKind
    let footnote: String
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        let presentations = items.map {
            StatisticsRankingPresentation(item: $0, kind: kind)
        }

        VStack(alignment: .leading, spacing: FlightTheme.Spacing.sm) {
            Label(title, systemImage: systemImage)
                .font(FlightTheme.Typography.serif(.headline, weight: .semibold))

            ForEach(Array(presentations.enumerated()), id: \.element.id) {
                index,
                item in
                HStack(alignment: .center, spacing: FlightTheme.Spacing.sm) {
                    Text(String(format: "%02d", index + 1))
                        .font(
                            FlightTheme.Typography.monospaced(
                                .caption,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(palette.goldInk.color)
                        .frame(width: 24)

                    if let routeBadge = item.routeBadge {
                        RouteBadge(presentation: routeBadge)
                            .layoutPriority(1)
                    } else if let airportCode = item.airportCode {
                        Text(airportCode)
                            .font(
                                FlightTheme.Typography.monospaced(
                                    .subheadline,
                                    weight: .bold
                                )
                            )
                            .foregroundStyle(palette.routeAccent.color)
                            .padding(.horizontal, FlightTheme.Spacing.xs)
                            .padding(.vertical, FlightTheme.Spacing.xxs)
                            .overlay {
                                Capsule()
                                    .stroke(palette.routeAccent.color, lineWidth: 1)
                            }
                    }

                    Text(item.label)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: FlightTheme.Spacing.xs)

                    Text(item.countText)
                        .font(
                            FlightTheme.Typography.monospaced(
                                .caption,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(palette.secondaryInk.color)
                }
                .padding(.vertical, FlightTheme.Spacing.xxs)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(index + 1) 名，\(item.label)")
                .accessibilityValue(item.countText)

                if index < presentations.count - 1 {
                    Divider()
                }
            }

            Text(footnote)
                .font(.caption)
                .foregroundStyle(palette.secondaryInk.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(FlightTheme.Spacing.md)
        .passportSurface(.archiveCard)
    }
}

private struct LongestFlightsChart: View {
    let flights: [LongestFlightStatistic]
    let distanceUnit: DistanceUnit
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    var body: some View {
        let items = flights.enumerated().map {
            LongestChartItem(index: $0.offset, flight: $0.element)
        }
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )

        VStack(alignment: .leading, spacing: 12) {
            Label("最长航班", systemImage: "arrow.left.and.right")
                .font(.headline)

            if items.isEmpty {
                ContentUnavailableView(
                    "没有可计算的最长航班",
                    systemImage: "ruler",
                    description: Text("当前记录的机场坐标均无效，未用 0 代替距离。")
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                Chart(items) { item in
                    BarMark(
                        x: .value(
                            "距离",
                            distanceUnit.convert(
                                kilometers: item.flight.distanceKilometers
                            )
                        ),
                        y: .value("航班", item.label)
                    )
                    .foregroundStyle(palette.secondaryInk.color.gradient)
                    .accessibilityLabel(item.label)
                    .accessibilityValue(
                        FlightMetricsService.standard.formattedDistance(
                            kilometers: item.flight.distanceKilometers,
                            unit: distanceUnit
                        )
                    )
                }
                .chartYScale(domain: items.map(\.label).reversed())
                .frame(minHeight: max(180, CGFloat(items.count) * 38))
            }

            Text("仅排列坐标有效的航班；等距时依次按较新日期、航班号和记录 ID 稳定排序。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .passportSurface(.paper)
    }
}

private struct LongestChartItem: Identifiable {
    let index: Int
    let flight: LongestFlightStatistic

    var id: UUID { flight.id }

    var label: String {
        "\(index + 1). \(flight.route) · \(flight.flightNumber)"
    }
}

private struct FlightClassificationChart: View {
    let snapshot: StatisticsSnapshot
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    var body: some View {
        let items = StatisticsPresentation.classificationItems(snapshot: snapshot)
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )

        VStack(alignment: .leading, spacing: 12) {
            Label("国内 / 国际构成", systemImage: "chart.pie")
                .font(.headline)

            Chart(items) { item in
                SectorMark(
                    angle: .value("航班次数", item.count),
                    innerRadius: .ratio(0.55),
                    angularInset: 2
                )
                .foregroundStyle(
                    statisticsColor(
                        item.seriesRole,
                        palette: palette,
                        colorScheme: colorScheme
                    )
                )
                .cornerRadius(4)
                .accessibilityLabel(item.label)
                .accessibilityValue(item.tooltip)
            }
            .frame(minHeight: 240)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: FlightTheme.Spacing.md) {
                    classificationLegend(items, palette: palette)
                }
                VStack(alignment: .leading, spacing: FlightTheme.Spacing.xs) {
                    classificationLegend(items, palette: palette)
                }
            }

            Text(
                "国内 \(snapshot.domesticFlightCount) 次 · 国际 \(snapshot.internationalFlightCount) 次 · 未知 \(snapshot.unknownClassificationFlightCount) 次"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            Text("仅比较航班保存时两端机场的 ISO 国家码；缺码记录不强行归类。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .passportSurface(.paper)
    }

    @ViewBuilder
    private func classificationLegend(
        _ items: [StatisticsClassificationItem],
        palette: FlightTheme.Palette
    ) -> some View {
        ForEach(items) { item in
            Label {
                Text(item.tooltip)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Circle()
                    .fill(
                        statisticsColor(
                            item.seriesRole,
                            palette: palette,
                            colorScheme: colorScheme
                        )
                    )
                    .frame(width: 9, height: 9)
            }
        }
    }
}

private func statisticsColor(
    _ role: StatisticsSeriesRole,
    palette: FlightTheme.Palette,
    colorScheme: ColorScheme
) -> Color {
    switch role {
    case .routeAccent:
        palette.routeAccent.color
    case .secondaryRoute:
        palette.secondaryInk.color
    case .dataGold:
        palette.dataGold.color
    case .passport:
        colorScheme == .dark
            ? palette.passportInk.color
            : palette.passportCover.color
    }
}

#Preview {
    StatisticsView()
        .modelContainer(for: FlightRecord.self, inMemory: true)
        .frame(width: 720, height: 520)
}
