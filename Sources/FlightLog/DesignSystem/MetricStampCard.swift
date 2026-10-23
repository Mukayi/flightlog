import SwiftUI

struct MetricStampPresentation: Equatable, Sendable {
    let title: String
    let value: String
    let detail: String?
    let systemImage: String

    var accessibilityLabel: String {
        [title, value, detail]
            .compactMap { $0 }
            .joined(separator: "，")
    }

    var accessibility: ComponentAccessibility {
        ComponentAccessibility(
            label: title,
            value: [value, detail]
                .compactMap { $0 }
                .joined(separator: "，")
        )
    }

    var layoutContract: ContentLayoutContract {
        .unboundedText
    }
}

struct MetricStampCard: View {
    let presentation: MetricStampPresentation

    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        let accessibility = presentation.accessibility

        HStack(alignment: .top, spacing: FlightTheme.Spacing.md) {
            Image(systemName: presentation.systemImage)
                .font(.title2)
                .foregroundStyle(palette.warmGold.color)
                .padding(FlightTheme.Spacing.xs)
                .overlay {
                    Circle()
                        .stroke(
                            palette.warmGold.color.opacity(0.62),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                        )
                        .accessibilityHidden(true)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: FlightTheme.Spacing.xxs) {
                Text(presentation.title)
                    .font(FlightTheme.Typography.serif(.subheadline, weight: .semibold))
                    .foregroundStyle(palette.secondaryInk.color)
                Text(presentation.value)
                    .font(FlightTheme.Typography.rounded(.title2, weight: .bold))
                    .foregroundStyle(palette.paperInk.color)
                if let detail = presentation.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryInk.color)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(FlightTheme.Spacing.md)
        .passportSurface(.archiveCard)
        .designSystemContentLayout(presentation.layoutContract)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility.label)
        .accessibilityValue(accessibility.value)
    }
}

#Preview("Metric stamp cards") {
    HStack(alignment: .top) {
        MetricStampCard(
            presentation: MetricStampPresentation(
                title: "累计飞行时长",
                value: "1,286 小时 35 分钟",
                detail: "包含 Unknown 时长的航班不会计入",
                systemImage: "clock"
            )
        )
        MetricStampCard(
            presentation: MetricStampPresentation(
                title: "到访城市（极长中文指标名称）",
                value: "Unknown",
                detail: "尚无足够资料",
                systemImage: "building.2"
            )
        )
    }
    .padding()
    .frame(width: 720)
}
