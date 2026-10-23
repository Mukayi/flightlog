import AppKit
import Charts
import SwiftData
import SwiftUI

struct ComparisonView: View {
    @Query(sort: \UserProfile.sortOrder)
    private var profiles: [UserProfile]
    @Query(sort: \FlightRecord.flightDate, order: .reverse)
    private var records: [FlightRecord]

    @ObservedObject var userSession: UserSession
    @ObservedObject var commandState: AppCommandState

    @AppStorage("comparison.selectedProfileIDs")
    private var storedSelection = ""
    @AppStorage("statistics.distanceUnit")
    private var distanceUnit: DistanceUnit = .kilometers

    @State private var selectedIDs: [UUID] = []
    @State private var selectedYear: Int?
    @State private var metric: StatisticsTrendMetric = .flightCount
    @State private var hoveredYear: Int?
    @State private var result: ComparisonPresentation?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showingProfileManagement = false
    @State private var generationGate = ComparisonGenerationGate()
    @State private var calculationTask: Task<Void, Never>?
    @State private var workerLane = ComparisonWorkerLane<ComparisonPresentation>()

    init(
        userSession: UserSession,
        commandState: AppCommandState,
        initialSelection: [UUID] = []
    ) {
        self.userSession = userSession
        self.commandState = commandState
        _selectedIDs = State(initialValue: initialSelection)
    }

    var body: some View {
        VStack(spacing: 0) {
            selectionBar
            Divider()
            content
        }
        .foregroundStyle(
            FlightTheme.palette(
                colorScheme: colorScheme,
                accessibilityContrast: accessibilityContrast
            ).paperInk.color
        )
        .background(
            FlightTheme.palette(
                colorScheme: colorScheme,
                accessibilityContrast: accessibilityContrast
            ).paper.color
        )
        .onAppear(perform: reconcileSelection)
        .onChange(of: profileSignature) {
            reconcileSelection()
        }
        .onChange(of: selectedIDs) {
            persistSelection()
            scheduleComparison()
        }
        .onChange(of: selectedYear) {
            scheduleComparison()
        }
        .onChange(of: comparisonFingerprint) {
            scheduleComparison()
        }
        .onDisappear {
            generationGate.cancel()
            calculationTask?.cancel()
        }
        .sheet(isPresented: $showingProfileManagement) {
            ProfileManagementView()
                .environmentObject(userSession)
        }
    }

    private var orderedProfiles: [UserProfile] {
        profiles.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var selectedProfiles: [UserProfile] {
        selectedIDs.compactMap { id in
            orderedProfiles.first { $0.id == id }
        }
    }

    private var profileSignature: String {
        orderedProfiles.map {
            "\($0.id.uuidString)|\($0.sortOrder)|\($0.createdAt.timeIntervalSince1970)"
        }.joined(separator: ";")
    }

    private var comparisonFingerprint: FlightDatasetFingerprint {
        ComparisonInvalidation.fingerprint(
            profiles: orderedProfiles,
            records: records
        )
    }

    private var selectionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: FlightTheme.Spacing.sm) {
                profilePicker
                yearPicker
                metricPicker
                    .frame(width: 340)
                distanceUnitPicker
                    .frame(width: 150)
                selectionLimit
            }
            compactSelectionBar
        }
        .padding(.horizontal, FlightTheme.Spacing.md)
        .padding(.vertical, FlightTheme.Spacing.sm)
        .background(.bar)
    }

    private var compactSelectionBar: some View {
        VStack(alignment: .leading, spacing: FlightTheme.Spacing.xs) {
            HStack(spacing: FlightTheme.Spacing.sm) {
                profilePicker
                Spacer(minLength: FlightTheme.Spacing.sm)
                selectionLimit
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: FlightTheme.Spacing.sm) {
                    yearPicker
                        .frame(minWidth: 120)
                    metricPicker
                        .frame(minWidth: 260, maxWidth: 340)
                    distanceUnitPicker
                        .frame(width: 150)
                }
                VStack(alignment: .leading, spacing: FlightTheme.Spacing.xs) {
                    HStack {
                        yearPicker
                        distanceUnitPicker
                    }
                    metricPicker
                }
            }
        }
    }

    private var profilePicker: some View {
        ComparisonAccessiblePopUp(
            title: "选择对比用户（\(selectedIDs.count)/\(ComparisonSelection.maximumCount)）",
            label: ComparisonAccessibilityContract.profilesLabel,
            value: "已选择 \(selectedIDs.count) 位，最少 2 位，最多 4 位",
            help: ComparisonAccessibilityContract.profilesHint,
            items: orderedProfiles.map { profile in
                ComparisonAccessiblePopUp.Item(
                    id: profile.id.uuidString,
                    title: profile.displayName,
                    isSelected: selectedIDs.contains(profile.id),
                    isEnabled: !(
                        (!selectedIDs.contains(profile.id)
                            && selectedIDs.count >= ComparisonSelection.maximumCount)
                            || (selectedIDs.contains(profile.id)
                                && selectedIDs.count <= ComparisonSelection.minimumCount)
                    )
                )
            }
        ) { id in
            guard let profileID = UUID(uuidString: id) else { return }
            toggle(profileID)
        }
        .frame(minWidth: 220, minHeight: 28)
    }

    @ViewBuilder
    private var yearPicker: some View {
        if let result {
            VStack(alignment: .leading, spacing: 2) {
                controlCaption(
                    ComparisonAccessibilityContract.yearLabel,
                    hint: ComparisonAccessibilityContract.yearHint
                )
                yearMenu(result.availableYears)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(ComparisonAccessibilityContract.yearLabel)
            .accessibilityHint(ComparisonAccessibilityContract.yearHint)
        }
    }

    private var selectedYearText: String {
        selectedYear.map { "\($0) 年" } ?? "全部年份"
    }

    private func yearMenu(_ years: [Int]) -> some View {
        ComparisonAccessiblePopUp(
            title: "\(ComparisonAccessibilityContract.yearLabel)：\(selectedYearText)",
            label: ComparisonAccessibilityContract.yearLabel,
            value: selectedYearText,
            help: ComparisonAccessibilityContract.yearHint,
            items: [
                ComparisonAccessiblePopUp.Item(
                    id: "all",
                    title: "全部年份",
                    isSelected: selectedYear == nil,
                    isEnabled: true
                ),
            ] + years.map {
                ComparisonAccessiblePopUp.Item(
                    id: String($0),
                    title: "\($0) 年",
                    isSelected: selectedYear == $0,
                    isEnabled: true
                )
            }
        ) { value in
            selectedYear = value == "all" ? nil : Int(value)
        }
        .frame(minWidth: 150, minHeight: 28)
    }

    private var metricPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            controlCaption(
                ComparisonAccessibilityContract.metricLabel,
                hint: ComparisonAccessibilityContract.metricHint
            )
            Picker("趋势指标", selection: $metric) {
                ForEach(StatisticsTrendMetric.allCases) {
                    Text($0.title)
                        .accessibilityLabel(
                            "\(ComparisonAccessibilityContract.metricLabel)，\($0.title)"
                        )
                        .accessibilityHint(
                            ComparisonAccessibilityContract.metricHint
                        )
                        .tag($0)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(ComparisonAccessibilityContract.metricLabel)
            .accessibilityHint(ComparisonAccessibilityContract.metricHint)
            .help(ComparisonAccessibilityContract.metricHint)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ComparisonAccessibilityContract.metricLabel)
        .accessibilityHint(ComparisonAccessibilityContract.metricHint)
    }

    private var distanceUnitPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            controlCaption(
                ComparisonAccessibilityContract.distanceUnitLabel,
                hint: ComparisonAccessibilityContract.distanceUnitHint
            )
            Picker("距离单位", selection: $distanceUnit) {
                ForEach(DistanceUnit.allCases) {
                    Text($0.rawValue)
                        .accessibilityLabel(
                            "\(ComparisonAccessibilityContract.distanceUnitLabel)，\($0.rawValue)"
                        )
                        .accessibilityHint(
                            ComparisonAccessibilityContract.distanceUnitHint
                        )
                        .tag($0)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(ComparisonAccessibilityContract.distanceUnitLabel)
            .accessibilityHint(ComparisonAccessibilityContract.distanceUnitHint)
            .help(ComparisonAccessibilityContract.distanceUnitHint)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ComparisonAccessibilityContract.distanceUnitLabel)
        .accessibilityHint(ComparisonAccessibilityContract.distanceUnitHint)
    }

    private func controlCaption(
        _ label: String,
        hint: String
    ) -> some View {
        Text(label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .help(hint)
    }

    private var selectionLimit: some View {
        Text("支持 2–4 位用户")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var content: some View {
        if orderedProfiles.count < ComparisonSelection.minimumCount {
            ContentUnavailableView {
                Label(
                    ComparisonUIPresentation.lessThanTwoProfilesTitle,
                    systemImage: "person.badge.plus"
                )
            } description: {
                Text("对比至少需要两位用户；新用户建好后会自动加入可选列表。")
            } actions: {
                Button("管理用户…") {
                    showingProfileManagement = true
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading && result == nil {
            ProgressView("正在整理同行航迹…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView(
                "无法生成对比",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let result {
            if result.combinedStatistics.snapshot.totalFlightCount == 0 {
                ContentUnavailableView(
                    "所选用户还没有航班",
                    systemImage: "airplane.circle",
                    description: Text("录入航班后，这里会生成共同航迹与年度趋势。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                comparisonContent(result)
                    .overlay(alignment: .topTrailing) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .padding()
                                .accessibilityLabel("正在更新对比")
                        }
                    }
            }
        } else {
            ProgressView("准备对比…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func comparisonContent(
        _ result: ComparisonPresentation
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlightTheme.Spacing.xl) {
                summaryGrid(result)
                sharedCountSection(result)
                trendSection(result)
                sharedFlightsSection(result)
                sharedRoutesSection(result)
                sharedLocationsSection(result)
                ComparisonMapView(
                    result: result,
                    distanceUnit: distanceUnit
                )
            }
            .padding(FlightTheme.Spacing.lg)
            .frame(maxWidth: 1_280)
            .frame(maxWidth: .infinity)
        }
    }

    private func summaryGrid(
        _ result: ComparisonPresentation
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.adaptive(minimum: 250, maximum: 430), spacing: 16),
            ],
            spacing: 16
        ) {
            ForEach(result.profiles, id: \.profileID) { profile in
                let snapshot = profile.statistics
                PassportSurface(.archiveCard) {
                    VStack(alignment: .leading, spacing: FlightTheme.Spacing.sm) {
                        profileHeading(
                            id: profile.profileID,
                            name: profile.name,
                            color: profile.color
                        )
                        metricLine("航班", "\(snapshot.totalFlightCount) 次")
                        metricLine(
                            "里程",
                            FlightDisplayFormatting.routeDistance(
                                kilometers: snapshot.totalDistanceKilometers,
                                unit: distanceUnit,
                                missingFlightCount: snapshot.missingDistanceFlightCount
                            )
                        )
                        metricLine(
                            "时长",
                            FlightDisplayFormatting.duration(
                                minutes: snapshot.totalDurationMinutes
                            )
                        )
                        metricLine("机场 / 城市 / 国家", [
                            snapshot.uniqueAirportCount,
                            snapshot.uniqueCityCount,
                            snapshot.uniqueCountryCount,
                        ].map(String.init).joined(separator: " / "))
                    }
                    .padding(FlightTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(profile.name)，\(snapshot.totalFlightCount) 次航班，"
                            + "\(snapshot.uniqueAirportCount) 个机场，"
                            + "\(snapshot.uniqueCityCount) 个城市，"
                            + "\(snapshot.uniqueCountryCount) 个国家或地区"
                    )
                }
            }
        }
    }

    private func sharedCountSection(
        _ result: ComparisonPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: FlightTheme.Spacing.sm) {
            HStack {
                Text("我们共同去过")
                    .font(.title2.bold())
                Spacer()
                Image(systemName: "info.circle")
                    .help(ComparisonUIPresentation.strictMatchingCopy)
                    .accessibilityLabel("共同项目匹配说明")
                    .accessibilityValue(ComparisonUIPresentation.strictMatchingCopy)
            }
            let counts = result.sharedCounts
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: 12)],
                spacing: 12
            ) {
                sharedCount("共同航班", counts.flightCount, "airplane")
                sharedCount("共同航线", counts.routeCount, "point.topleft.down.to.point.bottomright.curvepath")
                sharedCount("共同机场", counts.airportCount, "building.2")
                sharedCount("共同城市", counts.cityCount, "building.2.crop.circle")
                sharedCount("共同国家", counts.countryCount, "globe")
            }
        }
    }

    private func trendSection(
        _ result: ComparisonPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: FlightTheme.Spacing.sm) {
            Text("年度同行趋势")
                .font(.title2.bold())
            PassportSurface(.paper) {
                Chart {
                    ForEach(result.yearlySeries, id: \.profileID) { series in
                        ForEach(series.points, id: \.year) { point in
                            if let value = ComparisonUIPresentation.metricValue(
                                metric: metric,
                                flightCount: point.flightCount,
                                distanceKilometers: point.totalDistanceKilometers,
                                durationMinutes: point.totalDurationMinutes,
                                distanceUnit: distanceUnit
                            ) {
                                BarMark(
                                    x: .value("年份", String(point.year)),
                                    y: .value(metric.title, value)
                                )
                                .position(by: .value("用户", series.profileID.uuidString))
                                .foregroundStyle(
                                    profileColor(series.profileID)
                                )
                                .annotation(position: .top) {
                                    if hoveredYear == point.year {
                                        Text(
                                            ComparisonUIPresentation.tooltip(
                                                year: point.year,
                                                profileName: profileName(series.profileID),
                                                metric: metric,
                                                value: value,
                                                distanceUnit: distanceUnit
                                            )
                                        )
                                        .font(.caption2)
                                        .padding(4)
                                        .background(.regularMaterial, in: Capsule())
                                        .fixedSize()
                                    }
                                }
                                .accessibilityLabel(
                                    ComparisonUIPresentation.tooltip(
                                        year: point.year,
                                        profileName: profileName(series.profileID),
                                        metric: metric,
                                        value: value,
                                        distanceUnit: distanceUnit
                                    )
                                )
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                updateChartHover(
                                    phase,
                                    proxy: proxy,
                                    geometry: geometry
                                )
                            }
                    }
                }
                .frame(minHeight: 260)
                .padding(FlightTheme.Spacing.md)
            }
            comparisonLegend(result.legend)
        }
    }

    @ViewBuilder
    private func sharedFlightsSection(
        _ result: ComparisonPresentation
    ) -> some View {
        sectionHeading("共同航班", count: result.sharedFlights.count)
        if result.sharedFlights.isEmpty {
            intersectionEmpty("还没有严格匹配的共同航班")
        } else {
            LazyVStack(spacing: FlightTheme.Spacing.md) {
                ForEach(result.sharedFlights, id: \.key) { group in
                    PassportSurface(.archiveCard) {
                        VStack(alignment: .leading, spacing: FlightTheme.Spacing.sm) {
                            RouteBadge(
                                presentation: .init(
                                    departureIATA: group.key.departureIATA,
                                    arrivalIATA: group.key.arrivalIATA
                                )
                            )
                            ForEach(group.recordsByProfile, id: \.profileID) { profileRecords in
                                ForEach(profileRecords.records) { record in
                                    Button {
                                        open(record)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            profileHeading(
                                                id: profileRecords.profileID,
                                                name: profileName(profileRecords.profileID),
                                                color: profileComparisonColor(profileRecords.profileID)
                                            )
                                            BoardingPassCard(
                                                flight: record.flightPresentation,
                                                density: .compact
                                            )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("切换到该用户并打开航班档案")
                                }
                            }
                        }
                        .padding(FlightTheme.Spacing.md)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sharedRoutesSection(
        _ result: ComparisonPresentation
    ) -> some View {
        sectionHeading("共同航线", count: result.sharedRoutes.count)
        if result.sharedRoutes.isEmpty {
            intersectionEmpty("还没有所有人都飞过的共同航线")
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280), spacing: 16)],
                spacing: 16
            ) {
                ForEach(result.sharedRoutes, id: \.id) { route in
                    PassportSurface(.paper) {
                        VStack(alignment: .leading, spacing: 8) {
                            RouteBadge(
                                presentation: .init(
                                    departureIATA: route.airportA.iata,
                                    arrivalIATA: route.airportB.iata
                                )
                            )
                            ForEach(route.profiles, id: \.profileID) { profile in
                                metricLine(
                                    profileName(profile.profileID),
                                    "\(profile.flightCount) 次 · "
                                        + FlightDisplayFormatting.routeDistance(
                                            kilometers: profile.totalDistanceKilometers,
                                            unit: distanceUnit,
                                            missingFlightCount: profile.missingDistanceFlightCount
                                        )
                                )
                            }
                            Text(
                                "总计 \(route.flightCount) 次 · "
                                    + FlightDisplayFormatting.routeDistance(
                                        kilometers: route.totalDistanceKilometers,
                                        unit: distanceUnit,
                                        missingFlightCount: route.missingDistanceFlightCount
                                    )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(FlightTheme.Spacing.md)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func sharedLocationsSection(
        _ result: ComparisonPresentation
    ) -> some View {
        VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
            Text("共同地点排行")
                .font(.title2.bold())
            locationGroup("机场", result.sharedAirports)
            locationGroup("城市", result.sharedCities)
            locationGroup("国家与地区", result.sharedCountries)
        }
    }

    private func locationGroup(
        _ title: String,
        _ locations: [SharedLocationComparison]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if locations.isEmpty {
                Text(ComparisonUIPresentation.emptyIntersectionCopy)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(Array(locations.enumerated()), id: \.element.id) { index, location in
                        Text("\(index + 1). \(location.label) · \(location.combinedVisitCount)")
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary, in: Capsule())
                            .accessibilityLabel(
                                "\(title)第 \(index + 1) 名，\(location.label)，合计 \(location.combinedVisitCount) 次"
                            )
                    }
                }
            }
        }
    }

    private func comparisonLegend(
        _ items: [ComparisonLegendItem]
    ) -> some View {
        FlowLayout(spacing: 12) {
            ForEach(items, id: \.profileID) { item in
                Label {
                    Text(item.profileName)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Circle()
                        .fill(profileColor(item.profileID))
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func sectionHeading(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.title2.bold())
            Spacer()
            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func intersectionEmpty(_ title: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "point.3.connected.trianglepath.dotted",
            description: Text(ComparisonUIPresentation.emptyIntersectionCopy)
        )
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func sharedCount(
        _ title: String,
        _ count: Int,
        _ systemImage: String
    ) -> some View {
        MetricStampCard(
            presentation: .init(
                title: title,
                value: "\(count)",
                detail: nil,
                systemImage: systemImage
            )
        )
    }

    private func metricLine(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func profileHeading(
        id: UUID,
        name: String,
        color: ProfileComparisonColor
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(profileColor(id, fallback: color))
                .frame(width: 11, height: 11)
                .accessibilityHidden(true)
            Text(ComparisonUIPresentation.displayName(name))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func profileName(_ id: UUID) -> String {
        selectedProfiles.first(where: { $0.id == id })?.displayName
            ?? result?.legend.first(where: { $0.profileID == id })?.profileName
            ?? "同行者"
    }

    private func profileComparisonColor(_ id: UUID) -> ProfileComparisonColor {
        result?.legend.first(where: { $0.profileID == id })?.color ?? .fallback
    }

    private func profileColor(
        _ id: UUID,
        fallback: ProfileComparisonColor = .fallback
    ) -> Color {
        let profileColor = result?.legend.first(where: { $0.profileID == id })?.color
            ?? fallback
        return ComparisonColorPalette.swiftUIColor(
            profileColor,
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
    }

    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    private func open(_ record: ComparisonRecordSnapshot) {
        guard let owner = record.ownerProfileID else { return }
        ComparisonFlightOpening.open(
            recordID: record.id,
            ownerProfileID: owner,
            userSession: userSession,
            commandState: commandState
        )
    }

    private func updateChartHover(
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
            hoveredYear = proxy.value(
                atX: location.x - frame.minX,
                as: String.self
            ).flatMap(Int.init)
        case .ended:
            hoveredYear = nil
        }
    }

    private func toggle(_ id: UUID) {
        if let index = selectedIDs.firstIndex(of: id) {
            guard selectedIDs.count > ComparisonSelection.minimumCount else { return }
            selectedIDs.remove(at: index)
        } else {
            guard selectedIDs.count < ComparisonSelection.maximumCount else { return }
            selectedIDs.append(id)
        }
    }

    private func reconcileSelection() {
        let saved = storedSelection
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
        selectedIDs = ComparisonSelection.reconciled(
            saved: selectedIDs.isEmpty ? saved : selectedIDs,
            available: orderedProfiles.map(\.id),
            active: userSession.activeProfileID
        )
        if orderedProfiles.count >= ComparisonSelection.minimumCount {
            scheduleComparison()
        } else {
            calculationTask?.cancel()
            result = nil
            isLoading = false
        }
    }

    private func persistSelection() {
        storedSelection = selectedIDs.map(\.uuidString).joined(separator: ",")
    }

    private func scheduleComparison() {
        guard selectedIDs.count >= ComparisonSelection.minimumCount else {
            result = nil
            return
        }
        let selectedSet = Set(selectedIDs)
        let recordsByOwner = Dictionary(grouping: records) {
            $0.ownerProfileID
        }
        let datasets = selectedProfiles.map { profile in
            ProfileSnapshotDataset(
                profileID: profile.id,
                name: profile.displayName,
                color: ProfileComparisonColor(
                    rawValue: profile.comparisonColorRawValue
                ) ?? .fallback,
                records: (recordsByOwner[profile.id] ?? []).map(
                    ComparisonRecordSnapshot.init
                )
            )
        }.filter { selectedSet.contains($0.profileID) }
        let requestedYear = selectedYear

        let requestedGeneration = generationGate.begin()
        calculationTask?.cancel()
        isLoading = true
        errorMessage = nil
        calculationTask = Task {
            do {
                let comparison = try await workerLane.run {
                    try Task.checkCancellation()
                    let value = try ComparisonService().compareSnapshots(
                        datasets,
                        selectedYear: requestedYear
                    )
                    try Task.checkCancellation()
                    return value
                }
                guard
                    !Task.isCancelled,
                    generationGate.accept(requestedGeneration)
                else { return }
                result = comparison
                errorMessage = nil
                isLoading = false
            } catch is CancellationError {
                // A newer selection or query result owns the visible state.
            } catch {
                guard generationGate.accept(requestedGeneration) else { return }
                result = nil
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

private struct ComparisonAccessiblePopUp: NSViewRepresentable {
    struct Item: Equatable {
        let id: String
        let title: String
        let isSelected: Bool
        let isEnabled: Bool
    }

    let title: String
    let label: String
    let value: String
    let help: String
    let items: [Item]
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.bezelStyle = .rounded
        update(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        update(button, coordinator: context.coordinator)
    }

    private func update(
        _ button: NSPopUpButton,
        coordinator: Coordinator
    ) {
        coordinator.onSelect = onSelect
        button.removeAllItems()
        button.addItem(withTitle: title)
        button.menu?.addItem(.separator())
        for item in items {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(Coordinator.selectItem(_:)),
                keyEquivalent: ""
            )
            menuItem.target = coordinator
            menuItem.representedObject = item.id
            menuItem.state = item.isSelected ? .on : .off
            menuItem.isEnabled = item.isEnabled
            button.menu?.addItem(menuItem)
        }
        button.selectItem(at: 0)
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(value)
        button.setAccessibilityHelp(help)
        button.setAccessibilityRole(.popUpButton)
    }

    final class Coordinator: NSObject {
        var onSelect: (String) -> Void

        init(onSelect: @escaping (String) -> Void) {
            self.onSelect = onSelect
        }

        @objc func selectItem(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            onSelect(id)
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let arrangement = arrange(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews
        )
        for (index, point) in arrangement.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (
            CGSize(width: width.isFinite ? width : x, height: y + rowHeight),
            points
        )
    }
}
