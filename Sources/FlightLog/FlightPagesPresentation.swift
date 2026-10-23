import Foundation

enum FlightCardPresentationFactory {
    static func make(_ record: FlightRecord) -> FlightPresentation {
        FlightPresentation(
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
}

struct FlightDetailArchiveField: Identifiable, Equatable, Sendable {
    let title: String
    let value: String

    var id: String { title }
}

struct FlightDetailArchiveSection: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let fields: [FlightDetailArchiveField]
}

struct FlightDetailPresentation: Equatable, Sendable {
    let boardingPass: FlightPresentation
    let journey: JourneyTimelinePresentation
    let archiveSections: [FlightDetailArchiveSection]

    init(record: FlightRecord) {
        boardingPass = FlightCardPresentationFactory.make(record)
        journey = JourneyTimelinePresentation(record: record)
        archiveSections = [
            FlightDetailArchiveSection(
                id: "route",
                title: "航线档案",
                fields: [
                    .init(
                        title: "出发机场",
                        value: Self.airportDescription(
                            iata: record.departureAirportIATA,
                            name: record.departureAirportName,
                            city: record.departureCity,
                            country: record.departureCountry
                        )
                    ),
                    .init(
                        title: "出发时区",
                        value: Self.displayValue(record.departureTimeZoneID)
                    ),
                    .init(
                        title: "到达机场",
                        value: Self.airportDescription(
                            iata: record.arrivalAirportIATA,
                            name: record.arrivalAirportName,
                            city: record.arrivalCity,
                            country: record.arrivalCountry
                        )
                    ),
                    .init(
                        title: "到达时区",
                        value: Self.displayValue(record.arrivalTimeZoneID)
                    ),
                ]
            ),
            FlightDetailArchiveSection(
                id: "flight",
                title: "乘机档案",
                fields: [
                    .init(
                        title: "机型",
                        value: Self.displayValue(record.aircraftType)
                    ),
                    .init(
                        title: "舱位",
                        value: Self.displayValue(record.cabinClass)
                    ),
                    .init(
                        title: "座位",
                        value: Self.displayValue(record.seat)
                    ),
                    .init(
                        title: "备注",
                        value: Self.displayValue(record.notes)
                    ),
                ]
            ),
            FlightDetailArchiveSection(
                id: "provenance",
                title: "归档信息",
                fields: [
                    .init(title: "数据来源", value: "本地航班记录"),
                    .init(
                        title: "更新时间",
                        value: Self.updatedText(record.updatedAt)
                    ),
                ]
            ),
        ]
    }

    private static func airportDescription(
        iata: String,
        name: String,
        city: String,
        country: String
    ) -> String {
        let identity = [displayValue(iata), displayValue(name)]
            .joined(separator: " · ")
        let location = [displayValue(city), displayValue(country)]
            .joined(separator: "，")
        return "\(identity)\n\(location)"
    }

    private static func displayValue(_ value: String?) -> String {
        guard let value else { return "Unknown" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    private static func updatedText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
}

struct FlightRowSelectionLayout: Equatable, Sendable {
    let horizontalOffset: CGFloat
    let borderWidth: CGFloat
    let shadowRadius: CGFloat
    let animationDuration: Double?
}

enum FlightRowSelectionLayoutPolicy {
    static func resolve(
        isSelected: Bool,
        reduceMotion: Bool
    ) -> FlightRowSelectionLayout {
        guard isSelected else {
            return FlightRowSelectionLayout(
                horizontalOffset: 0,
                borderWidth: 0,
                shadowRadius: 0,
                animationDuration: reduceMotion
                    ? nil
                    : FlightTheme.Animation.quick
            )
        }
        return FlightRowSelectionLayout(
            horizontalOffset: reduceMotion ? 0 : 7,
            borderWidth: 1.5,
            shadowRadius: 7,
            animationDuration: reduceMotion
                ? nil
                : FlightTheme.Animation.quick
        )
    }
}

enum FlightBrowserPresentation {
    static let searchPrompt = "支持中文，搜索航班、航司、机场或城市"
    static let emptyRecordsTitle = "创建第一枚旅程签章"
    static let noMatchesTitle = "没有匹配的航班"
}
