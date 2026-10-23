import SwiftUI

struct FlightTimelinePresentation: Equatable, Sendable {
    let flights: [FlightPresentation]
    let density: FlightCardDensity

    var accessibility: ComponentAccessibility {
        ComponentAccessibility(
            label: "航班时间线",
            value: "\(flights.count) 个航班"
        )
    }

    var layoutContract: ContentLayoutContract {
        .unboundedText
    }
}

struct JourneyTimelinePresentation: Equatable, Sendable {
    let departureLocalTime: String
    let duration: String
    let arrivalLocalTime: String

    init(
        departureLocalTime: String?,
        duration: String?,
        arrivalLocalTime: String?
    ) {
        self.departureLocalTime = Self.displayValue(departureLocalTime)
        self.duration = Self.displayValue(duration)
        self.arrivalLocalTime = Self.displayValue(arrivalLocalTime)
    }

    init(record: FlightRecord) {
        self.init(
            departureLocalTime: HistoricalLocalTime.displayText(
                snapshot: record.departureLocalDateTime,
                absoluteDate: record.departureDate,
                timeZoneID: record.departureTimeZoneID,
                utcOffsetSeconds: record.departureUTCOffsetSeconds
            ),
            duration: FlightDisplayFormatting.duration(
                minutes: FlightMetricsService.standard.durationMinutes(for: record)
            ),
            arrivalLocalTime: HistoricalLocalTime.displayText(
                snapshot: record.arrivalLocalDateTime,
                absoluteDate: record.arrivalDate,
                timeZoneID: record.arrivalTimeZoneID,
                utcOffsetSeconds: record.arrivalUTCOffsetSeconds
            )
        )
    }

    var accessibility: ComponentAccessibility {
        ComponentAccessibility(
            label: "单航班旅程时间线",
            value: "当地起飞 \(departureLocalTime)，飞行时长 \(duration)，当地到达 \(arrivalLocalTime)"
        )
    }

    var layoutContract: ContentLayoutContract {
        .unboundedText
    }

    private static func displayValue(_ value: String?) -> String {
        guard let value else { return "Unknown" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

struct FlightTimeline: View {
    let presentation: FlightTimelinePresentation

    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    init(
        flights: [FlightPresentation],
        density: FlightCardDensity = .compact
    ) {
        presentation = FlightTimelinePresentation(
            flights: flights,
            density: density
        )
    }

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        let accessibility = presentation.accessibility

        LazyVStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
            ForEach(Array(presentation.flights.enumerated()), id: \.offset) {
                index,
                flight in
                HStack(alignment: .top, spacing: FlightTheme.Spacing.md) {
                    timelineMarker(
                        isLast: index
                            == presentation.flights.index(
                                before: presentation.flights.endIndex
                            ),
                        palette: palette
                    )
                    BoardingPassCard(
                        flight: flight,
                        density: presentation.density
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .designSystemContentLayout(presentation.layoutContract)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibility.label)
        .accessibilityValue(accessibility.value)
    }

    private func timelineMarker(
        isLast: Bool,
        palette: FlightTheme.Palette
    ) -> some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(palette.paper.color)
                    .frame(width: 18, height: 18)
                Circle()
                    .fill(palette.routeAccent.color)
                    .frame(width: 8, height: 8)
            }
            if !isLast {
                Rectangle()
                    .fill(palette.divider.color)
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 20)
        .accessibilityHidden(true)
    }
}

struct FlightJourneyTimeline: View {
    let presentation: JourneyTimelinePresentation

    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        let accessibility = presentation.accessibility

        PassportSurface(.paper) {
            ViewThatFits(in: .horizontal) {
                horizontalTimeline(palette: palette)
                verticalTimeline(palette: palette)
            }
            .padding(FlightTheme.Spacing.lg)
        }
        .designSystemContentLayout(presentation.layoutContract)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility.label)
        .accessibilityValue(accessibility.value)
    }

    private func horizontalTimeline(
        palette: FlightTheme.Palette
    ) -> some View {
        HStack(alignment: .center, spacing: FlightTheme.Spacing.sm) {
            milestone(
                title: "当地起飞",
                value: presentation.departureLocalTime,
                alignment: .leading,
                palette: palette
            )
            journeyLine(palette: palette)
            milestone(
                title: "飞行时长",
                value: presentation.duration,
                alignment: .center,
                palette: palette
            )
            journeyLine(palette: palette)
            milestone(
                title: "当地到达",
                value: presentation.arrivalLocalTime,
                alignment: .trailing,
                palette: palette
            )
        }
    }

    private func verticalTimeline(
        palette: FlightTheme.Palette
    ) -> some View {
        VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
            milestone(
                title: "当地起飞",
                value: presentation.departureLocalTime,
                alignment: .leading,
                palette: palette
            )
            milestone(
                title: "飞行时长",
                value: presentation.duration,
                alignment: .leading,
                palette: palette
            )
            milestone(
                title: "当地到达",
                value: presentation.arrivalLocalTime,
                alignment: .leading,
                palette: palette
            )
        }
    }

    private func milestone(
        title: String,
        value: String,
        alignment: HorizontalAlignment,
        palette: FlightTheme.Palette
    ) -> some View {
        VStack(alignment: alignment, spacing: FlightTheme.Spacing.xxs) {
            HStack(spacing: FlightTheme.Spacing.xs) {
                Circle()
                    .fill(palette.routeAccent.color)
                    .frame(width: 9, height: 9)
                    .accessibilityHidden(true)
                Text(title)
                    .font(
                        FlightTheme.Typography.monospaced(
                            .caption,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(palette.routeAccent.color)
            }
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.paperInk.color)
                .multilineTextAlignment(textAlignment(for: alignment))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func journeyLine(
        palette: FlightTheme.Palette
    ) -> some View {
        Rectangle()
            .fill(palette.divider.color)
            .frame(minWidth: 18, maxWidth: .infinity)
            .frame(height: accessibilityContrast == .increased ? 2 : 1)
            .accessibilityHidden(true)
    }

    private func textAlignment(
        for alignment: HorizontalAlignment
    ) -> TextAlignment {
        switch alignment {
        case .trailing: .trailing
        case .center: .center
        default: .leading
        }
    }
}

#Preview("Flight timeline — light") {
    ScrollView {
        FlightTimeline(flights: .timelinePreview, density: .full)
            .padding(32)
    }
    .frame(width: 760, height: 620)
    .preferredColorScheme(.light)
}

#Preview("Flight timeline — dark") {
    ScrollView {
        FlightTimeline(flights: .timelinePreview, density: .compact)
            .padding(32)
    }
    .frame(width: 760, height: 520)
    .preferredColorScheme(.dark)
}

private extension Array where Element == FlightPresentation {
    static let timelinePreview: [FlightPresentation] = [
        FlightPresentation(
            flightNumber: "CA 937",
            date: "2026年8月19日",
            airline: "中国国际航空",
            departure: .init(iata: "PVG", city: "上海", localTime: "08:35"),
            arrival: .init(iata: "LHR", city: "伦敦", localTime: "15:50"),
            duration: "12 小时 15 分钟"
        ),
        FlightPresentation(
            flightNumber: nil,
            date: "2026年9月1日",
            airline: "具有非常非常长中文名称的合作承运航空公司",
            departure: .init(
                iata: "Unknown",
                city: "尚未确认的出发城市",
                localTime: nil
            ),
            arrival: .init(
                iata: "HND",
                city: "东京都大田区",
                localTime: "Unknown"
            ),
            duration: nil
        ),
    ]
}
