import AppKit
import MapKit
import SwiftUI

enum ComparisonMapLayout {
    enum Mode: Equatable, Sendable {
        case stacked
        case sideBySide
    }

    static func mode(forWidth width: CGFloat) -> Mode {
        width >= 900 ? .sideBySide : .stacked
    }

    struct Frames: Equatable, Sendable {
        let header: CGRect
        let legend: CGRect
        let routeList: CGRect
        let map: CGRect
        let detail: CGRect
    }

    static func frames(for size: CGSize) -> Frames {
        let padding: CGFloat = 8
        let spacing: CGFloat = 8
        let headerHeight: CGFloat = 28
        let legendHeight: CGFloat = 24
        let routeListHeight: CGFloat = 38
        let contentY = padding + headerHeight + spacing
            + legendHeight + spacing + routeListHeight + spacing
        let contentHeight = max(240, size.height - contentY - padding)
        let contentWidth = max(320, size.width - padding * 2)
        let header = CGRect(
            x: padding,
            y: padding,
            width: contentWidth,
            height: headerHeight
        )
        let legend = CGRect(
            x: padding,
            y: header.maxY,
            width: contentWidth,
            height: legendHeight
        )
        let routeList = CGRect(
            x: padding,
            y: legend.maxY,
            width: contentWidth,
            height: routeListHeight
        )
        switch mode(forWidth: size.width) {
        case .sideBySide:
            let detailWidth = min(360, max(320, contentWidth * 0.34))
            let mapWidth = max(320, contentWidth - detailWidth - 12)
            return Frames(
                header: header,
                legend: legend,
                routeList: routeList,
                map: CGRect(
                    x: padding,
                    y: contentY,
                    width: mapWidth,
                    height: contentHeight
                ),
                detail: CGRect(
                    x: padding + mapWidth + 12,
                    y: contentY,
                    width: detailWidth,
                    height: contentHeight
                )
            )
        case .stacked:
            let mapHeight = max(300, contentHeight * 0.57)
            return Frames(
                header: header,
                legend: legend,
                routeList: routeList,
                map: CGRect(
                    x: padding,
                    y: contentY,
                    width: contentWidth,
                    height: mapHeight
                ),
                detail: CGRect(
                    x: padding,
                    y: contentY + mapHeight + 12,
                    width: contentWidth,
                    height: max(220, contentHeight - mapHeight - 12)
                )
            )
        }
    }
}

struct ComparisonMapViewport: Equatable, Sendable {
    let center: FlightCoordinate
    let latitudeDelta: Double
    let longitudeDelta: Double

    var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: center.latitude,
                longitude: center.longitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }
}

struct ComparisonMapSegment: Identifiable, Equatable, Sendable {
    let routeID: String
    let index: Int
    let coordinates: [FlightCoordinate]

    var id: String { "\(routeID)#\(index)" }
}

enum ComparisonMapGeometry {
    static let fallbackViewport = ComparisonMapViewport(
        center: FlightCoordinate(latitude: 15, longitude: 0),
        latitudeDelta: 120,
        longitudeDelta: 240
    )

    static func segments(
        routeID: String,
        from start: FlightCoordinate,
        to end: FlightCoordinate,
        segmentCount: Int = 96
    ) -> [ComparisonMapSegment] {
        GreatCircleRouteSampler.sampleSegments(
            from: start,
            to: end,
            segmentCount: segmentCount
        ).enumerated().map {
            ComparisonMapSegment(
                routeID: routeID,
                index: $0.offset,
                coordinates: $0.element
            )
        }
    }

    static func viewport(
        routes: [ComparisonOverlayRoute],
        selectedRouteID: String?
    ) -> ComparisonMapViewport {
        let selected = selectedRouteID.flatMap { id in
            routes.first { $0.id == id }
        }
        let fittedRoutes = selected.map { [$0] } ?? routes
        let coordinates = fittedRoutes.flatMap {
            GreatCircleRouteSampler.sample(
                from: $0.airportA.coordinate,
                to: $0.airportB.coordinate,
                segmentCount: 48
            )
        }
        return viewport(fitting: coordinates)
    }

    static func viewport(
        fitting coordinates: [FlightCoordinate]
    ) -> ComparisonMapViewport {
        let valid = coordinates.filter(\.isValid)
        guard !valid.isEmpty else { return fallbackViewport }

        let minimumLatitude = valid.map(\.latitude).min() ?? 0
        let maximumLatitude = valid.map(\.latitude).max() ?? 0
        let latitudeRange = maximumLatitude - minimumLatitude
        let latitudeDelta = min(160, max(20, latitudeRange * 1.35 + 8))
        let centerLatitude = max(
            -85,
            min(85, (minimumLatitude + maximumLatitude) / 2)
        )

        let longitudes = valid.map {
            normalizedPositiveLongitude($0.longitude)
        }.sorted()
        let longitudeArc = minimumLongitudeArc(longitudes)
        let longitudeDelta = min(
            330,
            max(24, longitudeArc.length * 1.25 + 8)
        )
        return ComparisonMapViewport(
            center: FlightCoordinate(
                latitude: centerLatitude,
                longitude: normalizedLongitude(longitudeArc.center)
            ),
            latitudeDelta: latitudeDelta,
            longitudeDelta: longitudeDelta
        )
    }

    private static func minimumLongitudeArc(
        _ sortedLongitudes: [Double]
    ) -> (center: Double, length: Double) {
        guard let first = sortedLongitudes.first else { return (0, 0) }
        guard sortedLongitudes.count > 1 else { return (first, 0) }
        var largestGap = -Double.infinity
        var arcStart = first
        for index in sortedLongitudes.indices {
            let current = sortedLongitudes[index]
            let next = index == sortedLongitudes.index(before: sortedLongitudes.endIndex)
                ? sortedLongitudes[0] + 360
                : sortedLongitudes[index + 1]
            let gap = next - current
            if gap > largestGap {
                largestGap = gap
                arcStart = next.truncatingRemainder(dividingBy: 360)
            }
        }
        let length = max(0, 360 - largestGap)
        return (arcStart + length / 2, length)
    }

    private static func normalizedPositiveLongitude(_ longitude: Double) -> Double {
        let normalized = longitude.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }

    private static func normalizedLongitude(_ longitude: Double) -> Double {
        let positive = normalizedPositiveLongitude(longitude)
        return positive > 180 ? positive - 360 : positive
    }
}

struct ComparisonMapView: View {
    let result: ComparisonPresentation
    let distanceUnit: DistanceUnit

    @State private var selectedRouteID: String?
    @State private var cameraPosition: MapCameraPosition
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    init(
        result: ComparisonPresentation,
        distanceUnit: DistanceUnit,
        initialSelectedRouteID: String? = nil
    ) {
        self.result = result
        self.distanceUnit = distanceUnit
        _selectedRouteID = State(initialValue: initialSelectedRouteID)
        let viewport = ComparisonMapGeometry.viewport(
            routes: result.overlayRoutes,
            selectedRouteID: initialSelectedRouteID
        )
        _cameraPosition = State(initialValue: .region(viewport.region))
    }

    var body: some View {
        GeometryReader { geometry in
            let frames = ComparisonMapLayout.frames(for: geometry.size)
            VStack(alignment: .leading, spacing: 0) {
                mapHeader
                    .frame(height: frames.header.height)
                comparisonLegend
                    .frame(height: frames.legend.height)
                accessibleRouteList
                    .frame(height: frames.routeList.height)
                Spacer().frame(height: 8)
                switch ComparisonMapLayout.mode(forWidth: geometry.size.width) {
                case .sideBySide:
                    HStack(spacing: 12) {
                        map
                            .frame(
                                width: frames.map.width,
                                height: frames.map.height
                            )
                        routeDetail
                            .frame(
                                width: frames.detail.width,
                                height: frames.detail.height
                            )
                    }
                case .stacked:
                    VStack(spacing: 12) {
                        map.frame(height: frames.map.height)
                        routeDetail.frame(height: frames.detail.height)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minHeight: 650, idealHeight: 720)
        .onChange(of: result.overlayRoutes.map(\.id)) { _, ids in
            if let selectedRouteID, !ids.contains(selectedRouteID) {
                self.selectedRouteID = nil
            }
            fitCamera()
        }
        .onChange(of: selectedRouteID) {
            fitCamera()
        }
    }

    private var mapHeader: some View {
        HStack {
            Text("同行航线地图")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text("\(result.overlayRoutes.count) 条航线")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("同行航线地图")
        .accessibilityValue("\(result.overlayRoutes.count) 条航线")
    }

    private var accessibleRouteList: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(orderedRoutes, id: \.id) { route in
                    ComparisonAccessibleButton(
                        title: route.id,
                        label: "选择航线 \(route.id)",
                        value: route.participation.label,
                        help: routeAccessibilitySummary(route),
                        isSelected: selectedRouteID == route.id
                    ) {
                        selectedRouteID = route.id
                    }
                    .frame(minWidth: 110, minHeight: 28)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("可操作航线列表")
    }

    private var orderedRoutes: [ComparisonOverlayRoute] {
        result.overlayRoutes.sorted {
            if $0.zOrder != $1.zOrder { return $0.zOrder < $1.zOrder }
            return $0.id < $1.id
        }
    }

    private var selectedRoute: ComparisonOverlayRoute? {
        result.overlayRoutes.first { $0.id == selectedRouteID }
    }

    private var map: some View {
        Map(position: $cameraPosition) {
            ForEach(orderedRoutes, id: \.id) { route in
                ForEach(segments(route), id: \.id) { segment in
                        MapPolyline(
                            coordinates: segment.coordinates.map {
                                CLLocationCoordinate2D(
                                    latitude: $0.latitude,
                                    longitude: $0.longitude
                                )
                            }
                        )
                        .stroke(
                            mapCasingColor,
                            style: StrokeStyle(
                                lineWidth: route.isSharedByAll ? 7 : 5.5,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: routeDash(route)
                            )
                        )
                        MapPolyline(
                            coordinates: segment.coordinates.map {
                                CLLocationCoordinate2D(
                                    latitude: $0.latitude,
                                    longitude: $0.longitude
                                )
                            }
                        )
                        .stroke(
                            routeColor(route),
                            style: StrokeStyle(
                                lineWidth: route.isSharedByAll
                                    ? (selectedRouteID == route.id ? 6 : 4)
                                    : (selectedRouteID == route.id ? 4 : 2.5),
                                lineCap: .round,
                                lineJoin: .round,
                                dash: routeDash(route)
                            )
                        )
                }
            }

            ForEach(airports) { airport in
                Annotation(
                    airport.iata,
                    coordinate: CLLocationCoordinate2D(
                        latitude: airport.latitude,
                        longitude: airport.longitude
                    )
                ) {
                    VStack(spacing: 2) {
                        Circle()
                            .fill(.background)
                            .frame(width: 10, height: 10)
                            .overlay {
                                Circle().stroke(.primary, lineWidth: 2)
                            }
                        Text(airport.iata)
                            .font(.caption2.bold())
                            .padding(.horizontal, 4)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "机场 \(airport.iata)，\(airport.city)，\(airport.country)"
                    )
                }
            }

            ForEach(routeMarkers, id: \.route.id) { marker in
                Annotation(
                    marker.route.id,
                    coordinate: CLLocationCoordinate2D(
                        latitude: marker.coordinate.latitude,
                        longitude: marker.coordinate.longitude
                    )
                ) {
                    Button {
                        selectedRouteID = marker.route.id
                    } label: {
                        Image(systemName: routeMarkerIcon(marker.route))
                            .font(.caption.bold())
                            .padding(7)
                            .foregroundStyle(.white)
                            .background(routeColor(marker.route), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择航线 \(marker.route.id)")
                    .accessibilityValue(
                        marker.route.participation.label
                    )
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
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
            .stroke(.quaternary, lineWidth: 1)
            .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var routeDetail: some View {
        if let route = selectedRoute {
            ScrollView {
                PassportSurface(.archiveCard) {
                    VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
                        HStack {
                            RouteBadge(
                                presentation: .init(
                                    departureIATA: route.airportA.iata,
                                    arrivalIATA: route.airportB.iata
                                )
                            )
                            Spacer()
                            Text(route.participation.label)
                                .font(.caption.bold())
                                .foregroundStyle(routeColor(route))
                        }
                        .accessibilityHidden(true)
                        .overlay {
                            ComparisonAccessibilityElement(
                                label: "已选航线 \(route.id)",
                                value: routeAccessibilitySummary(route),
                                help: "所选航线详情"
                            )
                        }
                        Text("总计 \(route.profiles.reduce(0) { $0 + $1.flightCount }) 次")
                            .font(.headline)

                        ForEach(route.profiles, id: \.profileID) { profile in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(profileName(profile.profileID))
                                    .font(.headline)
                                    .foregroundStyle(profileColor(profile.profileID))
                                LabeledContent("次数", value: "\(profile.flightCount)")
                                LabeledContent(
                                    "里程",
                                    value: FlightDisplayFormatting.routeDistance(
                                        kilometers: profile.totalDistanceKilometers,
                                        unit: distanceUnit,
                                        missingFlightCount: profile.missingDistanceFlightCount
                                    )
                                )
                                Text("包含航班")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                ForEach(profile.flights) { flight in
                                    Text(
                                        "\(flight.flightNumber) · "
                                            + ComparisonMapDateFormatter.text(
                                                flight.flightDate
                                            )
                                    )
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 6)
                            .accessibilityHidden(true)
                            .overlay {
                                ComparisonAccessibilityElement(
                                    label: profileName(profile.profileID),
                                    value: profileAccessibilityValue(profile),
                                    help: "该用户在所选航线中的次数、里程和包含航班"
                                )
                            }
                        }
                    }
                    .padding(FlightTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityElement(children: .contain)
        } else {
            ContentUnavailableView(
                "选择一条航线",
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                description: Text("所有人共同航线置顶加粗；部分同行航线使用琥珀色虚线；独有航线使用所属用户颜色。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var comparisonLegend: some View {
        HStack(spacing: FlightTheme.Spacing.md) {
            ForEach(result.legend, id: \.profileID) { item in
                Label {
                    Text(item.profileName)
                        .lineLimit(2)
                } icon: {
                    Circle()
                        .fill(profileColor(item.profileID))
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                }
            }
            Label {
                Text("所有人共同航线")
            } icon: {
                Capsule()
                    .fill(sharedColor)
                    .frame(width: 20, height: 5)
                    .accessibilityHidden(true)
            }
            Label {
                Text(partialLegendLabel)
            } icon: {
                Capsule()
                    .fill(partialRouteColor)
                    .frame(width: 20, height: 5)
                    .accessibilityHidden(true)
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "地图图例，"
                + result.legend.map(\.profileName).joined(separator: "、")
                + "，\(partialLegendLabel)，以及所有人共同航线"
        )
    }

    private var airports: [AirportSnapshot] {
        var byID: [String: AirportSnapshot] = [:]
        for route in result.overlayRoutes {
            for airport in [route.airportA, route.airportB]
            where airport.coordinate.isValid {
                byID[airport.id] = byID[airport.id] ?? airport
            }
        }
        return byID.values.sorted { $0.iata < $1.iata }
    }

    private var routeMarkers: [(
        route: ComparisonOverlayRoute,
        coordinate: FlightCoordinate
    )] {
        orderedRoutes.compactMap { route in
            let points = GreatCircleRouteSampler.sample(
                from: route.airportA.coordinate,
                to: route.airportB.coordinate,
                segmentCount: 32
            )
            guard !points.isEmpty else { return nil }
            return (route, points[points.count / 2])
        }
    }

    private func segments(
        _ route: ComparisonOverlayRoute
    ) -> [ComparisonMapSegment] {
        ComparisonMapGeometry.segments(
            routeID: route.id,
            from: route.airportA.coordinate,
            to: route.airportB.coordinate,
            segmentCount: 96
        )
    }

    private func routeColor(_ route: ComparisonOverlayRoute) -> Color {
        switch route.participation {
        case let .exclusive(profileID):
            profileColor(profileID)
        case .sharedBySome:
            partialRouteColor
        case .sharedByAll:
            sharedColor
        }
    }

    private func routeDash(_ route: ComparisonOverlayRoute) -> [CGFloat] {
        if case .sharedBySome = route.participation {
            return [8, 6]
        }
        return []
    }

    private func routeMarkerIcon(_ route: ComparisonOverlayRoute) -> String {
        switch route.participation {
        case .exclusive: "airplane"
        case .sharedBySome: "person.2"
        case .sharedByAll: "person.2.fill"
        }
    }

    private var partialLegendLabel: String {
        result.overlayRoutes.lazy
            .map(\.participation)
            .first {
                if case .sharedBySome = $0 { return true }
                return false
            }?.label ?? "部分同行航线"
    }

    private var partialRouteColor: Color {
        ComparisonColorPalette.partialRouteToken(
            appearance: colorScheme == .dark ? .dark : .light,
            contrast: accessibilityContrast == .increased
                ? .increased
                : .standard
        ).color
    }

    private var sharedColor: Color {
        FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        ).routeAccent.color
    }

    private var mapCasingColor: Color {
        FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        ).paper.color
    }

    private func profileColor(_ id: UUID) -> Color {
        let color = result.legend.first(where: { $0.profileID == id })?.color
            ?? .fallback
        return ComparisonColorPalette.swiftUIColor(
            color,
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
    }

    private func profileName(_ id: UUID) -> String {
        result.legend.first(where: { $0.profileID == id })?.profileName
            ?? "同行者"
    }

    private func routeAccessibilitySummary(
        _ route: ComparisonOverlayRoute
    ) -> String {
        let total = route.profiles.reduce(0) { $0 + $1.flightCount }
        let profiles = route.profiles.map {
            "\(profileName($0.profileID)) \($0.flightCount) 次"
        }.joined(separator: "，")
        return "\(route.participation.label)，总计 \(total) 次，\(profiles)"
    }

    private func profileAccessibilityValue(
        _ profile: ProfileRouteComparison
    ) -> String {
        let distance = FlightDisplayFormatting.routeDistance(
            kilometers: profile.totalDistanceKilometers,
            unit: distanceUnit,
            missingFlightCount: profile.missingDistanceFlightCount
        )
        let flights = profile.flights.map(\.flightNumber).joined(separator: "、")
        return "次数 \(profile.flightCount)，里程 \(distance)，包含航班 \(flights)"
    }

    private func fitCamera() {
        let viewport = ComparisonMapGeometry.viewport(
            routes: result.overlayRoutes,
            selectedRouteID: selectedRouteID
        )
        cameraPosition = .region(viewport.region)
    }
}

private struct ComparisonAccessibleButton: NSViewRepresentable {
    let title: String
    let label: String
    let value: String
    let help: String
    let isSelected: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: title,
            target: context.coordinator,
            action: #selector(Coordinator.performAction)
        )
        button.isBordered = false
        button.setButtonType(.radio)
        button.contentTintColor = .labelColor
        update(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        update(button, coordinator: context.coordinator)
    }

    private func update(_ button: NSButton, coordinator: Coordinator) {
        coordinator.action = action
        button.title = title
        button.state = isSelected ? .on : .off
        button.font = isSelected ? .boldSystemFont(ofSize: 12) : .systemFont(ofSize: 12)
        button.setAccessibilityLabel(label)
        button.setAccessibilityValue(
            "\(isSelected ? "已选择" : "未选择")，\(value)"
        )
        button.setAccessibilityHelp(help)
        button.setAccessibilityRole(.radioButton)
        button.setAccessibilitySelected(isSelected)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}

private struct ComparisonAccessibilityElement: NSViewRepresentable {
    let label: String
    let value: String
    let help: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        update(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        update(view)
    }

    private func update(_ view: NSView) {
        view.setAccessibilityLabel(label)
        view.setAccessibilityValue(value)
        view.setAccessibilityHelp(help)
    }
}

private enum ComparisonMapDateFormatter {
    static func text(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }
}
