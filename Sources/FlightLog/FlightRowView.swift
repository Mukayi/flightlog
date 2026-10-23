import SwiftUI

struct FlightRowView: View {
    let record: FlightRecord
    var isSelected = false

    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast
    @FlightLogReduceMotion private var reduceMotion

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        let layout = FlightRowSelectionLayoutPolicy.resolve(
            isSelected: isSelected,
            reduceMotion: reduceMotion
        )

        BoardingPassCard(
            flight: FlightCardPresentationFactory.make(record),
            density: .compact
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: FlightTheme.CornerRadius.medium,
                style: .continuous
            )
            .strokeBorder(
                palette.routeAccent.color,
                lineWidth: layout.borderWidth
            )
            .accessibilityHidden(true)
        }
        .shadow(
            color: palette.shadow.color.opacity(isSelected ? 0.28 : 0),
            radius: layout.shadowRadius,
            y: isSelected ? 3 : 0
        )
        .offset(x: layout.horizontalOffset)
        .animation(
            layout.animationDuration.map {
                .easeInOut(duration: $0)
            },
            value: isSelected
        )
        .padding(.vertical, FlightTheme.Spacing.xxs)
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(
            isSelected ? .isSelected : []
        )
    }
}
