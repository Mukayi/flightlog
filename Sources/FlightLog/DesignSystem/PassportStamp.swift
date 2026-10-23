import SwiftUI

struct PassportStampPresentation: Equatable, Sendable {
    let title: String
    let detail: String

    init(title: String?, detail: String?) {
        self.title = Self.displayValue(title)
        self.detail = Self.displayValue(detail)
    }

    var accessibilityLabel: String {
        "签章，\(title)，\(detail)"
    }

    private static func displayValue(_ value: String?) -> String {
        guard let value else { return "Unknown" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

struct PassportStamp: View {
    let presentation: PassportStampPresentation

    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast
    @FlightLogReduceMotion private var reduceMotion
    @State private var appeared = false

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        let motion = FlightTheme.motion(reduceMotion: reduceMotion)

        VStack(spacing: FlightTheme.Spacing.xxs) {
            Image(systemName: "airplane")
                .font(.headline)
                .accessibilityHidden(true)
            Text(presentation.title)
                .font(FlightTheme.Typography.serif(.headline, weight: .bold))
            Text(presentation.detail)
                .font(.caption)
        }
        .foregroundStyle(palette.paperInk.color)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, FlightTheme.Spacing.lg)
        .padding(.vertical, FlightTheme.Spacing.md)
        .overlay {
            ZStack {
                Capsule()
                    .strokeBorder(
                        palette.paperInk.color.opacity(0.68),
                        style: StrokeStyle(
                            lineWidth: accessibilityContrast == .increased ? 2 : 1.25,
                            dash: [4, 3]
                        )
                    )
                Capsule()
                    .inset(by: 4)
                    .strokeBorder(
                        palette.paperInk.color.opacity(0.32),
                        lineWidth: 0.75
                    )
            }
            .accessibilityHidden(true)
        }
        .rotationEffect(.degrees(-2))
        .scaleEffect(appeared ? 1 : motion.initialScale)
        .opacity(appeared || reduceMotion ? 1 : 0.72)
        .animation(
            motion.duration.map { .easeInOut(duration: $0) },
            value: appeared
        )
        .onAppear { appeared = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

#Preview("Passport stamps") {
    VStack(spacing: 32) {
        PassportStamp(
            presentation: PassportStampPresentation(
                title: "首次跨洲飞行与极长中文纪念签章",
                detail: "上海浦东国际机场至 Unknown"
            )
        )
        PassportStamp(
            presentation: PassportStampPresentation(
                title: nil,
                detail: nil
            )
        )
    }
    .padding(36)
    .frame(width: 420)
}
