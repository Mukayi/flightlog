import MapKit
import SwiftData
import SwiftUI

enum RouteMapLayout {
    enum Mode: Equatable {
        case stacked
        case sideBySide
    }

    enum Density: Equatable {
        case compact
        case standard
    }

    struct VerticalPolicy: Equatable {
        let density: Density
        let mapMinimumHeight: CGFloat
        let listMinimumHeight: CGFloat

        var requiredHeight: CGFloat {
            mapMinimumHeight + listMinimumHeight + splitDividerHeight
        }
    }

    static let minimumUsableMapHeight: CGFloat = 170
    static let minimumUsableListHeight: CGFloat = 150
    private static let standardMapHeight: CGFloat = 250
    private static let standardListHeight: CGFloat = 240
    private static let splitDividerHeight: CGFloat = 8

    static func mode(forWidth width: Double) -> Mode {
        width >= 900 ? .sideBySide : .stacked
    }

    static func verticalPolicy(availableHeight: CGFloat) -> VerticalPolicy {
        let standard = VerticalPolicy(
            density: .standard,
            mapMinimumHeight: standardMapHeight,
            listMinimumHeight: standardListHeight
        )
        guard availableHeight < standard.requiredHeight else {
            return standard
        }

        let usableHeight = max(
            minimumUsableMapHeight + minimumUsableListHeight,
            availableHeight - splitDividerHeight
        )
        let proposedMapHeight = (usableHeight * 0.54).rounded(.down)
        let mapHeight = max(minimumUsableMapHeight, proposedMapHeight)
        let listHeight = max(
            minimumUsableListHeight,
            usableHeight - mapHeight
        )
        return VerticalPolicy(
            density: .compact,
            mapMinimumHeight: mapHeight,
            listMinimumHeight: listHeight
        )
    }
}

struct RouteMapView: View {
    @Query
    private var records: [FlightRecord]

    @State private var selectedYear: Int?
    @State private var selectedAirline: String?
    @State private var selectedAirportIATA: String?
    @State private var selectedRouteID: String?
    @State private var hoveredRouteID: String?
    @State private var mapOverlayAppeared = false
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 15, longitude: 0),
            span: MKCoordinateSpan(
                latitudeDelta: 150,
                longitudeDelta: 360
            )
        )
    )

    let profileID: UUID
    private let mountID = UUID()
    let initialSelectedRouteID: String?
    private let metrics = FlightMetricsService.standard
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast
    @FlightLogReduceMotion private var reduceMotion

    init(
        profileID: UUID = UserProfileDefaults.id,
        initialSelectedRouteID: String? = nil
    ) {
        self.profileID = profileID
        self.initialSelectedRouteID = initialSelectedRouteID
        _selectedRouteID = State(initialValue: initialSelectedRouteID)
        let ownerID: UUID? = profileID
        _records = Query(
            filter: #Predicate { $0.ownerProfileID == ownerID },
            sort: \.flightDate,
            order: .reverse
        )
    }

    var body: some View {
        let filteredRecords = routeFilter.apply(to: records)
        let routes = RouteAggregator(metrics: metrics).aggregate(filteredRecords)

        VStack(spacing: 0) {
            filterBar(routeCount: routes.count)
            Divider()

            if records.isEmpty {
                emptyRecordsView
            } else if filteredRecords.isEmpty {
                noMatchesView
            } else {
                GeometryReader { proxy in
                    routeContent(
                        routes: routes,
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                }
            }
        }
        .onChange(of: routes.map(\.id)) { _, visibleRouteIDs in
            selectedRouteID = RouteSelection.reconciled(
                selectedRouteID: selectedRouteID,
                visibleRouteIDs: visibleRouteIDs
            )
        }
        .onChange(of: profileID) {
            resetProfileState()
        }
        .onAppear(perform: reportProfileScope)
        .onChange(of: records.map(\.id)) {
            reportProfileScope()
        }
    }

    @ViewBuilder
    private func routeContent(
        routes: [RouteAggregate],
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        switch RouteMapLayout.mode(forWidth: Double(width)) {
        case .sideBySide:
            HSplitView {
                routeMap(routes: routes)
                    .frame(minWidth: 500)
                routeSidebar(routes: routes)
                    .frame(
                        minWidth: 320,
                        idealWidth: 390,
                        maxWidth: 470
                    )
            }
        case .stacked:
            let policy = RouteMapLayout.verticalPolicy(
                availableHeight: height
            )
            VSplitView {
                routeMap(routes: routes)
                    .frame(minHeight: policy.mapMinimumHeight)
                routeSidebar(routes: routes)
                    .frame(minHeight: policy.listMinimumHeight)
            }
        }
    }

    private var routeFilter: RouteFilter {
        RouteFilter(
            dateRange: selectedYear.flatMap(RouteFilter.dateRange(forYear:)),
            airline: selectedAirline,
            airportIATA: selectedAirportIATA
        )
    }

    private var years: [Int] {
        Array(
            Set(
                records.map {
                    Self.utcCalendar.component(.year, from: $0.flightDate)
                }
            )
        )
        .sorted(by: >)
    }

    private var airlineOptions: [AirlineFilterOption] {
        var optionsByValue: [String: AirlineFilterOption] = [:]
        for record in records {
            let code = record.airlineCode.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let name = record.airlineName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let value = code.isEmpty ? name : code
            guard !value.isEmpty else { continue }
            let label = if code.isEmpty || name.isEmpty {
                value
            } else {
                "\(code) · \(name)"
            }
            let option = AirlineFilterOption(value: value, label: label)
            if
                optionsByValue[value] == nil
                    || label < optionsByValue[value]!.label
            {
                optionsByValue[value] = option
            }
        }
        return optionsByValue.values.sorted {
            ($0.label, $0.value) < ($1.label, $1.value)
        }
    }

    private var airportOptions: [AirportFilterOption] {
        var optionsByIATA: [String: AirportFilterOption] = [:]
        for record in records {
            let candidates = [
                AirportFilterOption(
                    iata: record.departureAirportIATA,
                    name: record.departureAirportName,
                    city: record.departureCity
                ),
                AirportFilterOption(
                    iata: record.arrivalAirportIATA,
                    name: record.arrivalAirportName,
                    city: record.arrivalCity
                ),
            ]
            for option in candidates where !option.iata.isEmpty {
                if
                    optionsByIATA[option.iata] == nil
                        || option.label < optionsByIATA[option.iata]!.label
                {
                    optionsByIATA[option.iata] = option
                }
            }
        }
        return optionsByIATA.values.sorted {
            ($0.iata, $0.label) < ($1.iata, $1.label)
        }
    }

    private var filterIsActive: Bool {
        selectedYear != nil
            || selectedAirline != nil
            || selectedAirportIATA != nil
    }

    private func filterBar(routeCount: Int) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                Picker("年份", selection: $selectedYear) {
                    Text("全部年份").tag(nil as Int?)
                    ForEach(years, id: \.self) { year in
                        Text("\(year) 年").tag(year as Int?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)

                Picker("航司", selection: $selectedAirline) {
                    Text("全部航司").tag(nil as String?)
                    ForEach(airlineOptions) { option in
                        Text(option.label).tag(option.value as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 210)

                Picker("机场", selection: $selectedAirportIATA) {
                    Text("全部机场").tag(nil as String?)
                    ForEach(airportOptions) { option in
                        Text(option.label).tag(option.iata as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 190)

                Button("重置筛选", systemImage: "arrow.counterclockwise") {
                    resetFilters()
                }
                .disabled(!filterIsActive)

                Spacer(minLength: 12)

                Text("\(routeCount) 条航线")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    private var emptyRecordsView: some View {
        ContentUnavailableView(
            "还没有航班记录",
            systemImage: "map",
            description: Text("录入航班后，这里会显示大圆航线和机场标记。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesView: some View {
        ContentUnavailableView {
            Label("没有匹配的航线", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("请调整年份、航司或机场筛选。")
        } actions: {
            Button("重置筛选") {
                resetFilters()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func routeMap(routes: [RouteAggregate]) -> some View {
        let segments = RouteMapVisualPolicy.orderedSegments(
            mapSegments(for: routes),
            selectedID: selectedRouteID
        )
        let airports = mapAirports(for: routes)
        let routeMarkers = mapRouteMarkers(for: routes)
        let maximumFlightCount = routes.map(\.flightCount).max() ?? 1
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )

        return VStack(spacing: 0) {
            HStack(spacing: FlightTheme.Spacing.sm) {
                Image(systemName: "map.fill")
                    .foregroundStyle(palette.warmGold.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text("航线航图")
                        .font(FlightTheme.Typography.serif(.headline, weight: .bold))
                    Text("ROUTE CHART · \(routes.count) ROUTES")
                        .font(FlightTheme.Typography.monospaced(.caption2, weight: .semibold))
                        .foregroundStyle(palette.warmGold.color)
                }
                Spacer()
                Text("选择飞机标记查看档案")
                    .font(.caption)
                    .foregroundStyle(palette.passportInk.color.opacity(0.78))
            }
            .padding(.horizontal, FlightTheme.Spacing.md)
            .padding(.vertical, FlightTheme.Spacing.sm)
            .foregroundStyle(palette.passportInk.color)
            .background(palette.passportCover.color)

            Map(position: $cameraPosition) {
                ForEach(segments) { segment in
                    let baseWidth = RouteVisualScale.lineWidth(
                        flightCount: segment.flightCount,
                        maximumFlightCount: maximumFlightCount
                    )
                    let style = RouteMapVisualPolicy.stroke(
                        isSelected: selectedRouteID == segment.routeID,
                        baseLineWidth: baseWidth
                    )
                    MapPolyline(
                        coordinates: segment.coordinates.map(\.mapKitCoordinate)
                    )
                    .stroke(
                        palette[style.colorRole].color.opacity(style.opacity),
                        style: StrokeStyle(
                            lineWidth: style.lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }

                ForEach(airports) { airport in
                    Annotation(
                        RouteMapVisualPolicy.annotationLabel(for: airport),
                        coordinate: airport.coordinate.mapKitCoordinate
                    ) {
                        ZStack {
                            Circle()
                                .fill(palette.passportCover.color)
                                .frame(width: 12, height: 12)
                            Circle()
                                .strokeBorder(palette.warmGold.color, lineWidth: 2)
                                .frame(width: 8, height: 8)
                            Circle()
                                .fill(palette.paper.color)
                                .frame(width: 2.5, height: 2.5)
                        }
                        .shadow(
                            color: palette.shadow.color.opacity(0.3),
                            radius: 1,
                            y: 1
                        )
                        .accessibilityElement()
                        .accessibilityLabel(
                            RouteMapVisualPolicy.annotationLabel(for: airport)
                        )
                    }
                }

                ForEach(routeMarkers) { marker in
                    Annotation(
                        "选择 \(marker.displayName)",
                        coordinate: marker.coordinate.mapKitCoordinate
                    ) {
                        routeMarker(marker, palette: palette)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
        }
        .background(palette.passportCover.color)
        .clipShape(
            RoundedRectangle(
                cornerRadius: FlightTheme.CornerRadius.medium,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: FlightTheme.CornerRadius.medium,
                style: .continuous
            )
            .strokeBorder(palette.warmGold.color.opacity(0.78), lineWidth: 1.5)
            .padding(3)
            .accessibilityHidden(true)
        }
        .onAppear {
            mapOverlayAppeared = true
        }
        .padding(FlightTheme.Spacing.sm)
    }

    private func routeMarker(
        _ marker: RouteMapMarker,
        palette: FlightTheme.Palette
    ) -> some View {
        let isSelected = selectedRouteID == marker.routeID
        let motion = RouteMapVisualPolicy.motion(
            hasAppeared: mapOverlayAppeared,
            isHovered: hoveredRouteID == marker.routeID,
            reduceMotion: reduceMotion
        )

        return Button {
            selectedRouteID = marker.routeID
        } label: {
            Image(systemName: "airplane")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(
                    isSelected
                        ? palette.passportCover.color
                        : palette.passportInk.color
                )
                .padding(7)
                .background(
                    isSelected
                        ? palette.routeAccent.color
                        : palette.warmGold.color,
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .strokeBorder(palette.paper.color.opacity(0.9), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(motion.scale)
        .offset(y: motion.verticalOffset)
        .opacity(motion.opacity)
        .animation(
            routeMapAnimation(for: motion),
            value: hoveredRouteID
        )
        .animation(
            routeMapAnimation(for: motion),
            value: mapOverlayAppeared
        )
        .onHover { isHovered in
            hoveredRouteID = isHovered ? marker.routeID : nil
        }
        .help("选择航线 \(marker.displayName)")
        .accessibilityLabel("选择航线 \(marker.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func routeMapAnimation(
        for motion: RouteMapMotionPresentation
    ) -> Animation? {
        guard let duration = motion.animationDuration else {
            return nil
        }
        let animation = Animation.easeOut(duration: duration)
        guard motion.repeatCount > 0 else {
            return animation
        }
        return animation.repeatCount(
            motion.repeatCount,
            autoreverses: false
        )
    }

    private func routeSidebar(routes: [RouteAggregate]) -> some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )

        return VSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("航线")
                        .font(.headline)
                    Spacer()
                    Text("\(routes.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(14)

                Divider()

                List(routes, selection: $selectedRouteID) { route in
                    RouteListRow(route: route)
                        .tag(route.id)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(palette.paper.color)
            }
            .frame(minHeight: 190)
            .background(palette.paper.color)

            if let selectedRoute = routes.first(
                where: { $0.id == selectedRouteID }
            ) {
                RouteDetailPanel(route: selectedRoute)
                    .id(selectedRoute.id)
            } else {
                ContentUnavailableView(
                    "选择一条航线",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    description: Text("在地图或上方列表中选择航线以查看详情。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func mapSegments(
        for routes: [RouteAggregate]
    ) -> [RouteMapSegment] {
        routes.flatMap { route -> [RouteMapSegment] in
            guard route.hasValidGeometry else {
                return []
            }
            return GreatCircleRouteSampler.sampleSegments(
                from: route.airportA.coordinate,
                to: route.airportB.coordinate,
                segmentCount: 96
            )
            .enumerated()
            .map { index, coordinates in
                RouteMapSegment(
                    routeID: route.id,
                    segmentIndex: index,
                    flightCount: route.flightCount,
                    coordinates: coordinates
                )
            }
        }
    }

    private func mapAirports(
        for routes: [RouteAggregate]
    ) -> [AirportSnapshot] {
        var snapshotsByIATA: [String: AirportSnapshot] = [:]
        for route in routes {
            for airport in [route.airportA, route.airportB]
                where airport.coordinate.isValid
            {
                if snapshotsByIATA[airport.iata] == nil {
                    snapshotsByIATA[airport.iata] = airport
                }
            }
        }
        return snapshotsByIATA.values.sorted { $0.iata < $1.iata }
    }

    private func mapRouteMarkers(
        for routes: [RouteAggregate]
    ) -> [RouteMapMarker] {
        routes.compactMap { route in
            guard route.hasValidGeometry else {
                return nil
            }
            let coordinates = GreatCircleRouteSampler.sample(
                from: route.airportA.coordinate,
                to: route.airportB.coordinate,
                segmentCount: 32
            )
            guard !coordinates.isEmpty else {
                return nil
            }
            return RouteMapMarker(
                routeID: route.id,
                displayName: route.displayName,
                coordinate: coordinates[coordinates.count / 2]
            )
        }
    }

    private func resetFilters() {
        selectedYear = nil
        selectedAirline = nil
        selectedAirportIATA = nil
    }

    private func resetProfileState() {
        resetFilters()
        selectedRouteID = nil
        hoveredRouteID = nil
        mapOverlayAppeared = false
    }

    private func reportProfileScope() {
        #if DEBUG
        ProfileScopeMountProbe.record(
            ProfileScopeMountSnapshot(
                section: .map,
                profileID: profileID,
                recordCount: records.count,
                holderDisplayName: nil,
                mountID: mountID
            )
        )
        #endif
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private struct RouteListRow: View {
    let route: RouteAggregate

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(route.displayName)
                    .font(.headline)
                Spacer()
                Text("\(route.flightCount) 次")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(
                FlightDisplayFormatting.routeDistance(
                    kilometers: route.totalDistanceKilometers,
                    unit: .kilometers,
                    missingFlightCount: route.missingDistanceFlightCount
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(route.displayName)，\(route.flightCount) 次，\(FlightDisplayFormatting.routeDistance(kilometers: route.totalDistanceKilometers, unit: .kilometers, missingFlightCount: route.missingDistanceFlightCount))"
        )
    }
}

struct RouteDetailPanel: View {
    let route: RouteAggregate
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast
    @FlightLogReduceMotion private var reduceMotion
    @State private var hasAppeared = false
    @State private var isHovered = false

    var body: some View {
        let presentation = RouteMapPresentation(route: route)
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        let motion = RouteMapVisualPolicy.motion(
            hasAppeared: hasAppeared,
            isHovered: isHovered,
            reduceMotion: reduceMotion
        )

        ScrollView {
            PassportSurface(.archiveCard) {
                VStack(alignment: .leading, spacing: FlightTheme.Spacing.lg) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(presentation.airportAIATA)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(
                            systemName:
                                "point.topleft.down.to.point.bottomright.curvepath"
                        )
                        .font(.title3)
                        .foregroundStyle(palette.routeAccent.color)
                        .accessibilityHidden(true)
                        Text(presentation.airportBIATA)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(FlightTheme.Typography.monospaced(.largeTitle, weight: .bold))

                    HStack(spacing: FlightTheme.Spacing.sm) {
                        archiveMetric(
                            title: "飞行次数",
                            value: presentation.flightCountText,
                            palette: palette
                        )
                        archiveMetric(
                            title: "累计里程",
                            value: presentation.distanceText,
                            palette: palette
                        )
                    }

                    VStack(alignment: .leading, spacing: FlightTheme.Spacing.xs) {
                        Text("航线档案")
                            .font(FlightTheme.Typography.serif(.headline, weight: .bold))
                        LabeledContent("里程覆盖", value: presentation.coverageText)
                        LabeledContent(
                            "涉及航司",
                            value: route.airlines.joined(separator: "、")
                        )
                    }

                    VStack(alignment: .leading, spacing: FlightTheme.Spacing.sm) {
                        Text("包含航班")
                            .font(FlightTheme.Typography.serif(.headline, weight: .bold))
                        ForEach(presentation.includedFlights) { flight in
                            HStack(spacing: FlightTheme.Spacing.sm) {
                                Image(systemName: "airplane")
                                    .foregroundStyle(palette.routeAccent.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(flight.flightNumber)
                                        .font(
                                            FlightTheme.Typography.monospaced(
                                                .body,
                                                weight: .bold
                                            )
                                        )
                                    Text(flight.routeText)
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryInk.color)
                                }
                                Spacer()
                                Text(flight.dateText)
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryInk.color)
                            }
                            .padding(FlightTheme.Spacing.sm)
                            .background(
                                palette.paper.color.opacity(0.72),
                                in: RoundedRectangle(
                                    cornerRadius: FlightTheme.CornerRadius.small,
                                    style: .continuous
                                )
                            )
                        }
                    }
                }
                .padding(FlightTheme.Spacing.lg)
            }
            .scaleEffect(motion.scale)
            .offset(y: motion.verticalOffset)
            .opacity(motion.opacity)
            .animation(
                routeMapAnimation(for: motion),
                value: isHovered
            )
            .animation(
                routeMapAnimation(for: motion),
                value: hasAppeared
            )
            .onHover { isHovered = $0 }
            .onAppear {
                hasAppeared = true
            }
            .padding(FlightTheme.Spacing.md)
        }
    }

    private func routeMapAnimation(
        for motion: RouteMapMotionPresentation
    ) -> Animation? {
        guard let duration = motion.animationDuration else {
            return nil
        }
        let animation = Animation.easeOut(duration: duration)
        guard motion.repeatCount > 0 else {
            return animation
        }
        return animation.repeatCount(
            motion.repeatCount,
            autoreverses: false
        )
    }

    private func archiveMetric(
        title: String,
        value: String,
        palette: FlightTheme.Palette
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(FlightTheme.Typography.monospaced(.caption2, weight: .semibold))
                .foregroundStyle(palette.secondaryInk.color)
            Text(value)
                .font(FlightTheme.Typography.rounded(.title3, weight: .bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(FlightTheme.Spacing.sm)
        .background(
            palette.paper.color.opacity(0.64),
            in: RoundedRectangle(
                cornerRadius: FlightTheme.CornerRadius.small,
                style: .continuous
            )
        )
    }
}

private struct AirportSnapshotView: View {
    let title: String
    let airport: AirportSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(airport.iata) · \(airport.name)")
                .fontWeight(.semibold)
            Text([airport.city, airport.country].filter { !$0.isEmpty }.joined(
                separator: "，"
            ))
            .foregroundStyle(.secondary)
            Text("坐标：\(coordinateDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("时区：\(airport.timeZoneID)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var coordinateDescription: String {
        guard airport.coordinate.isValid else {
            return "无效"
        }
        return String(
            format: "%.4f, %.4f",
            airport.latitude,
            airport.longitude
        )
    }
}

private struct AirlineFilterOption: Identifiable {
    let value: String
    let label: String

    var id: String { value }
}

private struct AirportFilterOption: Identifiable {
    let iata: String
    let name: String
    let city: String

    var id: String { iata }

    var label: String {
        let description = city.isEmpty ? name : city
        return description.isEmpty ? iata : "\(iata) · \(description)"
    }
}

private struct RouteMapMarker: Identifiable {
    let routeID: String
    let displayName: String
    let coordinate: FlightCoordinate

    var id: String { routeID }
}

private extension FlightCoordinate {
    var mapKitCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: latitude,
            longitude: longitude
        )
    }
}
