import SwiftUI

struct RouteBadgePresentation: Equatable, Sendable {
    let departureIATA: String
    let arrivalIATA: String

    init(departureIATA: String?, arrivalIATA: String?) {
        self.departureIATA = Self.displayValue(departureIATA)
        self.arrivalIATA = Self.displayValue(arrivalIATA)
    }

    var accessibilityLabel: String {
        "航线，\(departureIATA) 至 \(arrivalIATA)"
    }

    private static func displayValue(_ value: String?) -> String {
        guard let value else { return "Unknown" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed.uppercased()
    }
}

struct RouteBadge: View {
    let presentation: RouteBadgePresentation

    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )

        HStack(spacing: FlightTheme.Spacing.sm) {
            airportCode(presentation.departureIATA, palette: palette)

            HStack(spacing: FlightTheme.Spacing.xxs) {
                Circle()
                    .frame(width: 4, height: 4)
                Rectangle()
                    .frame(minWidth: 16, maxWidth: 48, maxHeight: 1)
                Image(systemName: "airplane")
            }
            .foregroundStyle(palette.routeAccent.color)
            .accessibilityHidden(true)

            airportCode(presentation.arrivalIATA, palette: palette)
        }
        .padding(.horizontal, FlightTheme.Spacing.md)
        .padding(.vertical, FlightTheme.Spacing.xs)
        .background(
            palette.routeAccent.color.opacity(
                accessibilityContrast == .increased ? 0.2 : 0.11
            ),
            in: Capsule()
        )
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func airportCode(
        _ code: String,
        palette: FlightTheme.Palette
    ) -> some View {
        Text(code)
            .font(FlightTheme.Typography.monospaced(.headline, weight: .bold))
            .foregroundStyle(palette.paperInk.color)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Route badges") {
    VStack(spacing: 20) {
        RouteBadge(
            presentation: RouteBadgePresentation(
                departureIATA: "PVG",
                arrivalIATA: "LHR"
            )
        )
        RouteBadge(
            presentation: RouteBadgePresentation(
                departureIATA: "非常长的中文机场名称",
                arrivalIATA: nil
            )
        )
    }
    .padding()
    .frame(width: 420)
}
