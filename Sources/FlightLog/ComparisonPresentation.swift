import Foundation
import SwiftUI

struct ComparisonEndpointSnapshot: Equatable, Sendable {
    let iata: String
    let name: String
    let city: String
    let country: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let timeZoneID: String

    var airport: Airport {
        Airport(
            iata: iata,
            icao: "",
            name: name,
            city: city,
            country: country,
            countryCode: countryCode,
            latitude: latitude,
            longitude: longitude,
            timeZoneID: timeZoneID
        )
    }
}

struct ComparisonRecordSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let ownerProfileID: UUID?
    let flightNumber: String
    let airlineCode: String
    let airlineName: String
    let flightDate: Date
    let departure: ComparisonEndpointSnapshot
    let arrival: ComparisonEndpointSnapshot
    let departureDate: Date
    let arrivalDate: Date
    let departureLocalDateTime: String?
    let arrivalLocalDateTime: String?

    init(
        id: UUID,
        ownerProfileID: UUID?,
        flightNumber: String,
        airlineCode: String,
        airlineName: String,
        flightDate: Date,
        departure: ComparisonEndpointSnapshot,
        arrival: ComparisonEndpointSnapshot,
        departureDate: Date,
        arrivalDate: Date,
        departureLocalDateTime: String?,
        arrivalLocalDateTime: String?
    ) {
        self.id = id
        self.ownerProfileID = ownerProfileID
        self.flightNumber = flightNumber
        self.airlineCode = airlineCode
        self.airlineName = airlineName
        self.flightDate = flightDate
        self.departure = departure
        self.arrival = arrival
        self.departureDate = departureDate
        self.arrivalDate = arrivalDate
        self.departureLocalDateTime = departureLocalDateTime
        self.arrivalLocalDateTime = arrivalLocalDateTime
    }

    init(_ record: FlightRecord) {
        self.init(
            id: record.id,
            ownerProfileID: record.ownerProfileID,
            flightNumber: record.flightNumber,
            airlineCode: record.airlineCode,
            airlineName: record.airlineName,
            flightDate: record.flightDate,
            departure: ComparisonEndpointSnapshot(
                iata: record.departureAirportIATA,
                name: record.departureAirportName,
                city: record.departureCity,
                country: record.departureCountry,
                countryCode: record.departureCountryCode,
                latitude: record.departureLatitude,
                longitude: record.departureLongitude,
                timeZoneID: record.departureTimeZoneID
            ),
            arrival: ComparisonEndpointSnapshot(
                iata: record.arrivalAirportIATA,
                name: record.arrivalAirportName,
                city: record.arrivalCity,
                country: record.arrivalCountry,
                countryCode: record.arrivalCountryCode,
                latitude: record.arrivalLatitude,
                longitude: record.arrivalLongitude,
                timeZoneID: record.arrivalTimeZoneID
            ),
            departureDate: record.departureDate,
            arrivalDate: record.arrivalDate,
            departureLocalDateTime: record.departureLocalDateTime,
            arrivalLocalDateTime: record.arrivalLocalDateTime
        )
    }

    var flightPresentation: FlightPresentation {
        let record = materialized()
        return FlightCardPresentationFactory.make(record)
    }

    func materialized() -> FlightRecord {
        let record = FlightRecord(
            id: id,
            flightNumber: flightNumber,
            airlineCode: airlineCode,
            airlineName: airlineName,
            flightDate: flightDate,
            departureAirport: departure.airport,
            arrivalAirport: arrival.airport,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            ownerProfileID: ownerProfileID ?? UserProfileDefaults.id
        )
        record.departureLocalDateTime = departureLocalDateTime
        record.arrivalLocalDateTime = arrivalLocalDateTime
        return record
    }
}

struct ProfileSnapshotDataset: Equatable, Sendable {
    let profileID: UUID
    let name: String
    let color: ProfileComparisonColor
    let records: [ComparisonRecordSnapshot]
}

enum ComparisonInvalidation {
    static func fingerprint(
        profiles: [UserProfile],
        records: [FlightRecord]
    ) -> FlightDatasetFingerprint {
        FlightDatasetFingerprint(
            profiles: profiles.map(UserProfileBackupDTO.init),
            recordSnapshots: records.map(FlightRecordBackupDTO.init)
        )
    }
}

enum ComparisonSelection {
    static let minimumCount = 2
    static let maximumCount = 4

    static func reconciled(
        saved: [UUID],
        available: [UUID],
        active: UUID?
    ) -> [UUID] {
        let availableSet = Set(available)
        var selected: [UUID] = []
        for id in saved where availableSet.contains(id) && !selected.contains(id) {
            selected.append(id)
            if selected.count == maximumCount { break }
        }
        if available.count < minimumCount {
            return Array(available.prefix(1))
        }
        if selected.count < minimumCount {
            let isDefaultSelection = selected.isEmpty
            if
                let active,
                availableSet.contains(active),
                !selected.contains(active)
            {
                selected.append(active)
                if
                    isDefaultSelection,
                    let index = available.firstIndex(of: active)
                {
                    let following = available.dropFirst(index + 1)
                        + available.prefix(index)
                    for id in following where !selected.contains(id) {
                        selected.append(id)
                        if selected.count == minimumCount { break }
                    }
                }
            }
            for id in available where selected.count < minimumCount
                && !selected.contains(id) {
                selected.append(id)
            }
        }
        return selected
    }
}

enum ComparisonUIPresentation {
    static let emptyIntersectionCopy = "这几位同行者暂时没有严格匹配的共同记录，新的旅程会从这里开始汇合。"
    static let strictMatchingCopy = "共同航班按同方向航班号、当地出发日期及两端机场严格匹配；共同航线不区分方向；地点按规范机场、城市和国家标识匹配。"
    static let lessThanTwoProfilesTitle = "添加另一位同行者"

    static func displayName(
        _ name: String,
        maximumCharacters: Int = 18
    ) -> String {
        let normalized = UserProfileNameValidator.normalize(name)
        guard normalized.count > maximumCharacters else {
            return normalized.isEmpty ? "未命名同行者" : normalized
        }
        return String(normalized.prefix(maximumCharacters - 1)) + "…"
    }

    static func metricValue(
        metric: StatisticsTrendMetric,
        flightCount: Int,
        distanceKilometers: Double?,
        durationMinutes: Int?,
        distanceUnit: DistanceUnit
    ) -> Double? {
        metric.value(
            flightCount: flightCount,
            distanceKilometers: distanceKilometers,
            durationMinutes: durationMinutes,
            distanceUnit: distanceUnit
        )
    }

    static func tooltip(
        year: Int,
        profileName: String,
        metric: StatisticsTrendMetric,
        value: Double,
        distanceUnit: DistanceUnit
    ) -> String {
        let valueText = StatisticsPresentation.valueText(
            value,
            metric: metric,
            distanceUnit: distanceUnit
        )
        return "\(year) 年 · \(profileName) · \(valueText)"
    }
}

enum ComparisonRouteParticipation: Equatable, Sendable {
    case exclusive(profileID: UUID)
    case sharedBySome(participantCount: Int, selectedProfileCount: Int)
    case sharedByAll(selectedProfileCount: Int)

    static func classify(
        participantIDs: [UUID],
        selectedProfileCount: Int
    ) -> Self {
        if participantIDs.count == 1 {
            return .exclusive(
                profileID: participantIDs[0]
            )
        }
        if participantIDs.count == selectedProfileCount {
            return .sharedByAll(selectedProfileCount: selectedProfileCount)
        }
        return .sharedBySome(
            participantCount: participantIDs.count,
            selectedProfileCount: selectedProfileCount
        )
    }

    var label: String {
        switch self {
        case .exclusive:
            "独有航线"
        case let .sharedBySome(participantCount, selectedProfileCount):
            "部分同行航线 \(participantCount)/\(selectedProfileCount)"
        case .sharedByAll:
            "所有人共同航线"
        }
    }

    var zOrder: Int {
        switch self {
        case .exclusive: 0
        case .sharedBySome: 50
        case .sharedByAll: 100
        }
    }
}

struct ComparisonMapRoutePresentation: Equatable, Identifiable, Sendable {
    let id: String
    let participantIDs: [UUID]
    let selectedProfileCount: Int

    var participation: ComparisonRouteParticipation {
        .classify(
            participantIDs: participantIDs,
            selectedProfileCount: selectedProfileCount
        )
    }

    var zOrder: Int { participation.zOrder }
}

enum ComparisonMapPolicy {
    static func ordered(
        _ routes: [ComparisonMapRoutePresentation]
    ) -> [ComparisonMapRoutePresentation] {
        routes.sorted {
            if $0.zOrder != $1.zOrder { return $0.zOrder < $1.zOrder }
            return $0.id < $1.id
        }
    }

    static func role(
        for route: ComparisonMapRoutePresentation
    ) -> ComparisonRouteParticipation {
        route.participation
    }

    static func legend(
        profiles: [ComparisonLegendItem]
    ) -> [ComparisonLegendItem] {
        profiles
    }
}

enum ComparisonToolbarLayout {
    enum Mode: Equatable, Sendable {
        case compact
        case regular
    }

    enum Control: Equatable, Sendable {
        case profiles
        case year
        case metric
        case distanceUnit
        case limit
    }

    struct ControlFrame: Equatable, Sendable {
        let control: Control
        let frame: CGRect
    }

    static let compactHeight: CGFloat = 128

    static func mode(forWidth width: CGFloat) -> Mode {
        width < 900 ? .compact : .regular
    }

    static func controlFrames(forWidth width: CGFloat) -> [ControlFrame] {
        let contentWidth = max(0, width - 32)
        return [
            ControlFrame(
                control: .profiles,
                frame: CGRect(x: 16, y: 8, width: contentWidth, height: 32)
            ),
            ControlFrame(
                control: .year,
                frame: CGRect(x: 16, y: 48, width: 152, height: 32)
            ),
            ControlFrame(
                control: .metric,
                frame: CGRect(
                    x: 176,
                    y: 48,
                    width: min(336, max(0, width - 352)),
                    height: 32
                )
            ),
            ControlFrame(
                control: .distanceUnit,
                frame: CGRect(
                    x: max(16, width - 168),
                    y: 48,
                    width: 152,
                    height: 32
                )
            ),
            ControlFrame(
                control: .limit,
                frame: CGRect(x: 16, y: 88, width: 220, height: 28)
            ),
        ]
    }
}

enum ComparisonAccessibilityContract {
    static let profilesLabel = "选择对比用户"
    static let profilesHint = "打开菜单，选择最少两位、最多四位同行者"
    static let yearLabel = "对比年份"
    static let yearHint = "筛选所有对比模块使用的年份"
    static let metricLabel = "对比趋势指标"
    static let metricHint = "切换航班次数、有效距离或有效时长"
    static let distanceUnitLabel = "对比距离单位"
    static let distanceUnitHint = "切换公里或英里"

    static let primaryControlLabels = [
        profilesLabel,
        yearLabel,
    ]
    static let primaryControlOptionLabels = [
        "航班次数", "有效距离", "有效时长", "km", "mi",
    ]
    static let primaryControlHints = [
        profilesHint,
        yearHint,
        metricHint,
        distanceUnitHint,
    ]
}

@MainActor
enum ComparisonFlightOpening {
    static func open(
        recordID: UUID,
        ownerProfileID: UUID,
        userSession: UserSession,
        commandState: AppCommandState
    ) {
        userSession.activate(ownerProfileID)
        commandState.requestOpenFlight(id: recordID)
    }
}

@MainActor
final class ComparisonGenerationGate {
    private var sequence: UInt = 0
    private var active: UInt?

    func begin() -> UInt {
        sequence &+= 1
        active = sequence
        return sequence
    }

    func accept(_ generation: UInt) -> Bool {
        active == generation
    }

    func cancel() {
        active = nil
    }
}

actor ComparisonWorkerProbe {
    struct Snapshot: Equatable, Sendable {
        let activeCount: Int
        let maximumActiveCount: Int
        let startedCount: Int
        let finishedCount: Int
    }

    private var activeCount = 0
    private var maximumActiveCount = 0
    private var startedCount = 0
    private var finishedCount = 0

    func workerStarted() {
        activeCount += 1
        startedCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
    }

    func workerFinished() {
        activeCount -= 1
        finishedCount += 1
    }

    func snapshot() -> Snapshot {
        Snapshot(
            activeCount: activeCount,
            maximumActiveCount: maximumActiveCount,
            startedCount: startedCount,
            finishedCount: finishedCount
        )
    }
}

actor ComparisonWorkerLane<Value: Sendable> {
    private let probe: ComparisonWorkerProbe?
    private var sequence: UInt = 0
    private var worker: Task<Value, Error>?

    init(probe: ComparisonWorkerProbe? = nil) {
        self.probe = probe
    }

    func run(
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        sequence &+= 1
        let request = sequence
        let previous = worker
        previous?.cancel()
        if let previous {
            _ = await previous.result
        }
        try Task.checkCancellation()
        guard request == sequence else {
            throw CancellationError()
        }

        let probe = self.probe
        let current = Task.detached(priority: .userInitiated) {
            await probe?.workerStarted()
            do {
                let value = try await operation()
                await probe?.workerFinished()
                return value
            } catch {
                await probe?.workerFinished()
                throw error
            }
        }
        worker = current
        do {
            let value = try await withTaskCancellationHandler {
                try await current.value
            } onCancel: {
                current.cancel()
            }
            if request == sequence {
                worker = nil
            }
            return value
        } catch {
            if request == sequence {
                worker = nil
            }
            throw error
        }
    }

    func cancel() {
        sequence &+= 1
        worker?.cancel()
    }
}

enum ComparisonColorPalette {
    static func partialRouteToken(
        appearance: FlightTheme.Appearance,
        contrast: FlightTheme.Contrast
    ) -> FlightTheme.ColorToken {
        switch (appearance, contrast) {
        case (.light, .standard):
            rgb((154, 90, 0))
        case (.light, .increased):
            rgb((116, 64, 0))
        case (.dark, .standard):
            rgb((245, 184, 90))
        case (.dark, .increased):
            rgb((255, 208, 131))
        }
    }

    static func token(
        _ color: ProfileComparisonColor,
        appearance: FlightTheme.Appearance,
        contrast: FlightTheme.Contrast
    ) -> FlightTheme.ColorToken {
        let increased = contrast == .increased
        return switch (appearance, color) {
        case (.light, .blue):
            rgb(increased ? (0, 66, 126) : (0, 82, 145))
        case (.light, .orange):
            rgb(increased ? (128, 55, 0) : (151, 66, 0))
        case (.light, .green):
            rgb(increased ? (0, 82, 45) : (0, 101, 58))
        case (.light, .purple):
            rgb(increased ? (92, 47, 132) : (109, 58, 151))
        case (.light, .pink):
            rgb(increased ? (128, 28, 70) : (151, 40, 82))
        case (.dark, .blue):
            rgb(increased ? (123, 197, 255) : (91, 177, 242))
        case (.dark, .orange):
            rgb(increased ? (255, 193, 122) : (239, 165, 90))
        case (.dark, .green):
            rgb(increased ? (117, 224, 157) : (84, 196, 126))
        case (.dark, .purple):
            rgb(increased ? (214, 170, 255) : (189, 144, 232))
        case (.dark, .pink):
            rgb(increased ? (255, 173, 204) : (239, 143, 179))
        }
    }

    static func swiftUIColor(
        _ color: ProfileComparisonColor,
        colorScheme: ColorScheme,
        accessibilityContrast: ColorSchemeContrast
    ) -> Color {
        token(
            color,
            appearance: colorScheme == .dark ? .dark : .light,
            contrast: accessibilityContrast == .increased
                ? .increased
                : .standard
        ).color
    }

    private static func rgb(
        _ channels: (Double, Double, Double)
    ) -> FlightTheme.ColorToken {
        FlightTheme.ColorToken(
            red: channels.0 / 255,
            green: channels.1 / 255,
            blue: channels.2 / 255
        )
    }
}
