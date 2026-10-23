import SwiftUI

struct ComponentAccessibility: Equatable, Sendable {
    let label: String
    let value: String
}

struct ContentLayoutContract: Equatable, Sendable {
    let fixedContentHeight: CGFloat?
    let lineLimit: Int?
    let allowsVerticalGrowth: Bool
    let truncatesLongText: Bool

    static let unboundedText = ContentLayoutContract(
        fixedContentHeight: nil,
        lineLimit: nil,
        allowsVerticalGrowth: true,
        truncatesLongText: false
    )
}

extension View {
    func designSystemContentLayout(
        _ contract: ContentLayoutContract
    ) -> some View {
        lineLimit(contract.lineLimit)
            .fixedSize(
                horizontal: false,
                vertical: contract.allowsVerticalGrowth
            )
            .frame(height: contract.fixedContentHeight)
    }
}

struct FlightEndpointPresentation: Equatable, Sendable {
    let iata: String
    let city: String
    let localTime: String

    init(iata: String?, city: String?, localTime: String?) {
        self.iata = Self.displayValue(iata)
        self.city = Self.displayValue(city)
        self.localTime = Self.displayValue(localTime)
    }

    static let unknown = FlightEndpointPresentation(
        iata: nil,
        city: nil,
        localTime: nil
    )

    private static func displayValue(_ value: String?) -> String {
        guard let value else { return "Unknown" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

struct FlightPresentation: Equatable, Sendable {
    let flightNumber: String
    let date: String
    let airline: String
    let departure: FlightEndpointPresentation
    let arrival: FlightEndpointPresentation
    let duration: String

    init(
        flightNumber: String?,
        date: String?,
        airline: String?,
        departure: FlightEndpointPresentation,
        arrival: FlightEndpointPresentation,
        duration: String?
    ) {
        self.flightNumber = Self.displayValue(flightNumber)
        self.date = Self.displayValue(date)
        self.airline = Self.displayValue(airline)
        self.departure = departure
        self.arrival = arrival
        self.duration = Self.displayValue(duration)
    }

    var accessibilityLabel: String {
        [
            flightNumber,
            date,
            airline,
            "\(departure.iata) \(departure.city) \(departure.localTime) 至 "
                + "\(arrival.iata) \(arrival.city) \(arrival.localTime)",
            duration,
        ].joined(separator: "，")
    }

    var boardingPassAccessibility: ComponentAccessibility {
        ComponentAccessibility(
            label: "登机牌，\(flightNumber)",
            value: accessibilityLabel
        )
    }

    private static func displayValue(_ value: String?) -> String {
        guard let value else { return "Unknown" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

enum FlightPresentationField: Equatable, Sendable {
    case flightNumber
    case date
    case airline
    case route
    case cities
    case localTimes
    case duration
}

enum FlightCardDensity: Equatable, Sendable {
    case compact
    case full

    var visibleFields: [FlightPresentationField] {
        switch self {
        case .compact:
            [
                .flightNumber,
                .date,
                .airline,
                .route,
                .localTimes,
                .duration,
            ]
        case .full:
            [
                .flightNumber,
                .date,
                .airline,
                .route,
                .cities,
                .localTimes,
                .duration,
            ]
        }
    }

    var layoutContract: ContentLayoutContract {
        .unboundedText
    }
}

struct BoardingPassCard: View {
    let flight: FlightPresentation
    var density: FlightCardDensity = .full

    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast
    @FlightLogReduceMotion private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        let motion = FlightTheme.motion(reduceMotion: reduceMotion)
        let accessibility = flight.boardingPassAccessibility

        VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
            header(palette: palette)

            RouteBadge(
                presentation: RouteBadgePresentation(
                    departureIATA: flight.departure.iata,
                    arrivalIATA: flight.arrival.iata
                )
            )

            endpointDetails(palette: palette)
        }
        .padding(density == .compact ? FlightTheme.Spacing.md : FlightTheme.Spacing.lg)
        .passportSurface(.paper)
        .designSystemContentLayout(density.layoutContract)
        .scaleEffect(isHovered ? motion.hoverScale : 1)
        .animation(
            motion.duration.map { .easeInOut(duration: $0) },
            value: isHovered
        )
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility.label)
        .accessibilityValue(accessibility.value)
    }

    private func header(palette: FlightTheme.Palette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FlightTheme.Spacing.sm) {
            Text(flight.flightNumber)
                .font(
                    FlightTheme.Typography.monospaced(
                        density == .compact ? .headline : .title2,
                        weight: .bold
                    )
                )
                .foregroundStyle(palette.paperInk.color)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: FlightTheme.Spacing.xs)

            VStack(alignment: .trailing, spacing: FlightTheme.Spacing.xxs) {
                Text(flight.date)
                Text(flight.airline)
            }
            .font(.subheadline)
            .foregroundStyle(palette.secondaryInk.color)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func endpointDetails(
        palette: FlightTheme.Palette
    ) -> some View {
        HStack(alignment: .top, spacing: FlightTheme.Spacing.md) {
            endpoint(flight.departure, alignment: .leading, palette: palette)

            Spacer(minLength: FlightTheme.Spacing.sm)

            Text(flight.duration)
                .font(FlightTheme.Typography.rounded(.caption, weight: .semibold))
                .foregroundStyle(palette.secondaryInk.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: FlightTheme.Spacing.sm)

            endpoint(flight.arrival, alignment: .trailing, palette: palette)
        }
    }

    private func endpoint(
        _ endpoint: FlightEndpointPresentation,
        alignment: HorizontalAlignment,
        palette: FlightTheme.Palette
    ) -> some View {
        VStack(alignment: alignment, spacing: FlightTheme.Spacing.xxs) {
            if density == .full {
                Text(endpoint.city)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondaryInk.color)
                    .multilineTextAlignment(
                        alignment == .leading ? .leading : .trailing
                    )
            }
            Text(endpoint.localTime)
                .font(FlightTheme.Typography.monospaced(.body, weight: .semibold))
                .foregroundStyle(palette.paperInk.color)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Boarding passes — light") {
    VStack {
        BoardingPassCard(flight: .previewLongText, density: .full)
        BoardingPassCard(flight: .previewLongText, density: .compact)
    }
    .padding()
    .frame(width: 680)
    .preferredColorScheme(.light)
}

#Preview("Boarding passes — dark") {
    VStack {
        BoardingPassCard(flight: .previewLongText, density: .full)
        BoardingPassCard(flight: .previewLongText, density: .compact)
    }
    .padding()
    .frame(width: 680)
    .preferredColorScheme(.dark)
}

private extension FlightPresentation {
    static let previewLongText = FlightPresentation(
        flightNumber: "CA 937 / Very Long Codeshare Number",
        date: "2026年8月19日",
        airline: "中国国际航空与合作承运航空公司（超长名称）",
        departure: .init(
            iata: "PVG",
            city: "上海市浦东新区",
            localTime: "08:35"
        ),
        arrival: .init(
            iata: "Unknown",
            city: "Unknown / 尚未确认的超长目的地城市",
            localTime: "Unknown"
        ),
        duration: "12 小时 15 分钟"
    )
}
