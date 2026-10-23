import Charts
import SwiftData
import SwiftUI

struct OverviewView: View {
    @Query
    private var flights: [FlightRecord]

    let profileID: UUID
    let onAddFlight: () -> Void
    let onOpenFlight: (UUID) -> Void
    var holderDisplayName = UserProfileDefaults.displayName
    private let mountID = UUID()

    @AppStorage("statistics.distanceUnit")
    private var distanceUnit: DistanceUnit = .kilometers
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    private let statistics = FlightStatisticsService()

    init(
        profileID: UUID = UserProfileDefaults.id,
        onAddFlight: @escaping () -> Void,
        onOpenFlight: @escaping (UUID) -> Void,
        holderDisplayName: String = UserProfileDefaults.displayName
    ) {
        self.profileID = profileID
        self.onAddFlight = onAddFlight
        self.onOpenFlight = onOpenFlight
        self.holderDisplayName = holderDisplayName
        let ownerID: UUID? = profileID
        _flights = Query(
            filter: #Predicate { $0.ownerProfileID == ownerID },
            sort: \.flightDate,
            order: .reverse
        )
    }

    var body: some View {
        let presentation = OverviewPresentation(
            records: flights,
            snapshot: statistics.snapshot(flights),
            distanceUnit: distanceUnit,
            holderDisplayName: holderDisplayName
        )
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )

        ScrollView {
            LazyVStack(alignment: .leading, spacing: FlightTheme.Spacing.xl) {
                passportHero(presentation.hero, palette: palette)
                metricsSection(presentation.metrics)
                YearbookSection(points: presentation.yearbook)
                recentFlightsSection(presentation.recentFlights)
            }
            .padding(FlightTheme.Spacing.lg)
            .frame(maxWidth: 1_120)
            .frame(maxWidth: .infinity)
        }
        .onAppear(perform: reportProfileScope)
        .onChange(of: flights.map(\.id)) {
            reportProfileScope()
        }
    }

    private func reportProfileScope() {
        #if DEBUG
        ProfileScopeMountProbe.record(
            ProfileScopeMountSnapshot(
                section: .overview,
                profileID: profileID,
                recordCount: flights.count,
                holderDisplayName: holderDisplayName,
                mountID: mountID
            )
        )
        #endif
    }

    private func passportHero(
        _ hero: OverviewHeroPresentation,
        palette: FlightTheme.Palette
    ) -> some View {
        PassportSurface(.cover) {
            ZStack(alignment: .trailing) {
                PassportRouteNetwork(color: palette.warmGold.color)
                    .frame(maxWidth: 390)
                    .opacity(accessibilityContrast == .increased ? 0.55 : 0.34)

                VStack(alignment: .leading, spacing: FlightTheme.Spacing.lg) {
                    HStack(alignment: .center, spacing: FlightTheme.Spacing.md) {
                        PassportBadge()
                        VStack(alignment: .leading, spacing: FlightTheme.Spacing.xxs) {
                            Text("FLIGHT PASSPORT")
                                .font(
                                    FlightTheme.Typography.monospaced(
                                        .caption,
                                        weight: .semibold
                                    )
                                )
                                .tracking(1.6)
                            Text(hero.title)
                                .font(
                                    FlightTheme.Typography.serif(
                                        .largeTitle,
                                        weight: .bold
                                    )
                                )
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: FlightTheme.Spacing.xl) {
                            heroField("持有人", value: hero.holder)
                            heroField("首次飞行", value: hero.firstFlightYear)
                            heroField("总航班", value: hero.totalFlights)
                            heroField("累计里程", value: hero.totalDistance)
                        }
                        VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
                            heroField("持有人", value: hero.holder)
                            heroField("首次飞行", value: hero.firstFlightYear)
                            heroField("总航班", value: hero.totalFlights)
                            heroField("累计里程", value: hero.totalDistance)
                        }
                    }
                }
                .padding(FlightTheme.Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(hero.title)，持有人 \(hero.holder)，首次飞行 \(hero.firstFlightYear)，总航班 \(hero.totalFlights)，累计里程 \(hero.totalDistance)"
            )
        }
    }

    private func heroField(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: FlightTheme.Spacing.xxs) {
            Text(label.uppercased())
                .font(
                    FlightTheme.Typography.monospaced(
                        .caption2,
                        weight: .semibold
                    )
                )
                .opacity(0.78)
            Text(value)
                .font(FlightTheme.Typography.rounded(.headline, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metricsSection(
        _ metrics: [OverviewMetricPresentation]
    ) -> some View {
        VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
            ChapterHeader(
                title: "飞行印章",
                narrative: "六枚印章沿用统计章节的口径与距离单位；信息按钮说明每项计算范围。",
                eyebrow: "PASSPORT STAMPS"
            )
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 190, maximum: 320),
                        spacing: FlightTheme.Spacing.md
                    ),
                ],
                alignment: .leading,
                spacing: FlightTheme.Spacing.md
            ) {
                ForEach(metrics) { metric in
                    OverviewMetricCard(metric: metric)
                }
            }
        }
    }

    @ViewBuilder
    private func recentFlightsSection(
        _ recentFlights: [OverviewRecentFlightPresentation]
    ) -> some View {
        VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
            ChapterHeader(
                title: "近期航班",
                narrative: "最近五段旅程以紧凑登机牌归档，保留航班、日期、航线、本地时间与时长。",
                eyebrow: "RECENT BOARDING PASSES"
            )
            if recentFlights.isEmpty {
                PassportSurface(.paper) {
                    ContentUnavailableView {
                        Label("还没有航班记录", systemImage: "airplane.circle")
                    } description: {
                        Text("录入第一条航班后，护照统计、年份册与登机牌会在这里自然展开。")
                    } actions: {
                        Button("前往新增航班", systemImage: "plus") {
                            onAddFlight()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 210)
                    .padding(FlightTheme.Spacing.md)
                }
            } else {
                LazyVStack(spacing: FlightTheme.Spacing.md) {
                    ForEach(recentFlights) { flight in
                        Button {
                            onOpenFlight(flight.id)
                        } label: {
                            BoardingPassCard(
                                flight: flight.boardingPass,
                                density: .compact
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            flight.boardingPass.boardingPassAccessibility.label
                        )
                        .accessibilityValue(
                            flight.boardingPass.boardingPassAccessibility.value
                        )
                        .accessibilityHint("打开详情")
                        .accessibilityAction(named: "打开详情") {
                            onOpenFlight(flight.id)
                        }
                    }
                }
            }
        }
    }
}

private struct OverviewMetricCard: View {
    let metric: OverviewMetricPresentation

    @State private var isShowingExplanation = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MetricStampCard(presentation: metric.card)
                .frame(maxWidth: .infinity)

            Button {
                isShowingExplanation.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .padding(FlightTheme.Spacing.sm)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(metric.explanation)
            .accessibilityLabel("\(metric.card.title)计算说明")
            .popover(isPresented: $isShowingExplanation, arrowEdge: .top) {
                Text(metric.explanation)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(FlightTheme.Spacing.md)
                    .frame(idealWidth: 280, maxWidth: 340, alignment: .leading)
            }
        }
    }
}

enum OverviewFlightOrdering {
    static func recent(_ records: [FlightRecord]) -> [FlightRecord] {
        records.sorted { lhs, rhs in
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
}

private struct PassportRouteNetwork: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let points = [
                CGPoint(x: size.width * 0.12, y: size.height * 0.28),
                CGPoint(x: size.width * 0.46, y: size.height * 0.18),
                CGPoint(x: size.width * 0.82, y: size.height * 0.36),
                CGPoint(x: size.width * 0.68, y: size.height * 0.74),
                CGPoint(x: size.width * 0.26, y: size.height * 0.70),
            ]
            for (startIndex, endIndex) in [
                (0, 1), (1, 2), (2, 3), (3, 4), (4, 0), (1, 3),
            ] {
                let start = points[startIndex]
                let end = points[endIndex]
                var route = Path()
                route.move(to: start)
                route.addQuadCurve(
                    to: end,
                    control: CGPoint(
                        x: (start.x + end.x) / 2,
                        y: min(start.y, end.y) - size.height * 0.12
                    )
                )
                context.stroke(
                    route,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
            }
            for point in points {
                context.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: point.x - 3,
                            y: point.y - 3,
                            width: 6,
                            height: 6
                        )
                    ),
                    with: .color(color)
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct YearbookSection: View {
    let points: [OverviewYearbookPoint]

    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast
    @State private var hoveredYear: Int?

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        let maximumFlightCount = max(1, points.map(\.flightCount).max() ?? 1)

        VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
            ChapterHeader(
                title: "旅行年份册",
                narrative: "按 UTC 日历中的飞行日期汇总航班次数；将指针停在柱形上可查看年份签注。",
                eyebrow: "TRAVEL YEARBOOK"
            )
            PassportSurface(.paper) {
                if points.isEmpty {
                    ContentUnavailableView(
                        "暂无旅行年份",
                        systemImage: "chart.bar.xaxis",
                        description: Text("录入航班后，这里会按年份保存旅行足迹。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 230)
                    .padding(FlightTheme.Spacing.md)
                } else {
                    VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
                        yearChart(
                            maximumFlightCount: maximumFlightCount,
                            palette: palette
                        )
                        yearStamps(palette: palette)
                    }
                    .padding(FlightTheme.Spacing.lg)
                }
            }
        }
    }

    private func yearChart(
        maximumFlightCount: Int,
        palette: FlightTheme.Palette
    ) -> some View {
        Chart(points) { point in
            BarMark(
                x: .value("年份", point.year),
                y: .value("航班次数", point.flightCount)
            )
            .foregroundStyle(palette.routeAccent.color.gradient)
            .accessibilityLabel("\(point.year) 年")
            .accessibilityValue("\(point.flightCount) 次航班")
            .annotation(position: .top, spacing: FlightTheme.Spacing.xxs) {
                if hoveredYear == point.year {
                    Text(point.hoverText)
                        .font(.caption)
                        .foregroundStyle(palette.paperInk.color)
                        .padding(.horizontal, FlightTheme.Spacing.xs)
                        .padding(.vertical, FlightTheme.Spacing.xxs)
                        .background(palette.archiveCard.color, in: Capsule())
                        .fixedSize()
                }
            }
        }
        .chartYScale(domain: 0...maximumFlightCount)
        .chartXAxis {
            AxisMarks(values: points.map(\.year)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let year = value.as(Int.self) {
                        Text(String(year))
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
                        updateHover(phase, proxy: proxy, geometry: geometry)
                    }
            }
        }
        .frame(minHeight: 190, idealHeight: 220, maxHeight: 250)
    }

    private func yearStamps(
        palette: FlightTheme.Palette
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: 62),
                    spacing: FlightTheme.Spacing.sm
                ),
            ],
            spacing: FlightTheme.Spacing.sm
        ) {
            ForEach(points) { point in
                Text(String(point.year))
                    .font(
                        FlightTheme.Typography.monospaced(
                            .caption,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(palette.routeAccent.color)
                    .padding(FlightTheme.Spacing.xs)
                    .overlay {
                        Circle()
                            .stroke(
                                palette.routeAccent.color,
                                style: StrokeStyle(
                                    lineWidth: 1,
                                    dash: [3, 2]
                                )
                            )
                    }
                    .accessibilityHidden(true)
            }
        }
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
}

enum VisitMetricPresentation {
    static let airportTitle = "到访机场"
    static let airportDetail =
        "所有有 IATA 代码的出发与到达机场按 IATA 去重，同一机场多次只算一次"

    static let cityTitle = "到访城市"
    static let cityDetail =
        "按城市+国家去重，同城多个机场只算一个城市（例如 LHR/LGW 为 2 机场 1 城市）"
}

struct SummaryCard: View {
    let title: String
    let value: String
    var detail: String? = nil
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(
            [value, detail].compactMap { $0 }.joined(separator: "，")
        )
    }
}

#Preview {
    OverviewView(onAddFlight: {}, onOpenFlight: { _ in })
        .modelContainer(for: FlightRecord.self, inMemory: true)
        .frame(width: 720, height: 520)
}
