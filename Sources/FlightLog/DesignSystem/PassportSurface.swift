import SwiftUI

enum PassportTexturePattern: Equatable, Sendable {
    case proceduralDiagonalLines
}

struct PassportTextureConfiguration: Equatable, Sendable {
    let pattern: PassportTexturePattern
    let spacing: CGFloat
    let lineWidth: CGFloat
    let opacity: Double
}

enum PassportSurfaceStyle: CaseIterable, Equatable, Sendable {
    case cover
    case paper
    case archiveCard

    var textureConfiguration: PassportTextureConfiguration {
        switch self {
        case .cover:
            PassportTextureConfiguration(
                pattern: .proceduralDiagonalLines,
                spacing: 10,
                lineWidth: 0.5,
                opacity: 0.055
            )
        case .paper, .archiveCard:
            PassportTextureConfiguration(
                pattern: .proceduralDiagonalLines,
                spacing: 14,
                lineWidth: 0.5,
                opacity: 0.035
            )
        }
    }
}

struct PassportSurface<Content: View>: View {
    let style: PassportSurfaceStyle
    @ViewBuilder let content: Content

    init(
        _ style: PassportSurfaceStyle,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        content.passportSurface(style)
    }
}

extension View {
    func passportSurface(
        _ style: PassportSurfaceStyle
    ) -> some View {
        modifier(PassportSurfaceModifier(style: style))
    }
}

private struct PassportSurfaceModifier: ViewModifier {
    let style: PassportSurfaceStyle

    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    func body(content: Content) -> some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )
        let radius = cornerRadius
        let texture = style.textureConfiguration

        content
            .foregroundStyle(contentInk(palette).color)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(gradient(palette))
                    .overlay {
                        PassportTexture(
                            color: textureColor(palette).opacity(texture.opacity),
                            configuration: texture
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: radius,
                                style: .continuous
                            )
                        )
                        .accessibilityHidden(true)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        borderColor(palette),
                        lineWidth: accessibilityContrast == .increased ? 1.5 : 0.75
                    )
                    .accessibilityHidden(true)
            }
            .clipShape(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .shadow(
                color: palette.shadow.color.opacity(shadow.colorOpacity),
                radius: shadow.radius,
                y: shadow.y
            )
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .cover: FlightTheme.CornerRadius.large
        case .paper: FlightTheme.CornerRadius.medium
        case .archiveCard: FlightTheme.CornerRadius.small
        }
    }

    private var shadow: FlightTheme.ShadowToken {
        switch style {
        case .cover: FlightTheme.Shadow.elevated
        case .paper, .archiveCard: FlightTheme.Shadow.subtle
        }
    }

    private func gradient(_ palette: FlightTheme.Palette) -> LinearGradient {
        switch style {
        case .cover:
            LinearGradient(
                colors: [
                    palette.passportCover.color,
                    palette.passportCover.color.mix(
                        with: palette.shadow.color,
                        by: 0.18
                    ),
                    palette.passportCover.color.opacity(0.94),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .paper:
            LinearGradient(
                colors: [
                    palette.paper.color,
                    palette.paper.color.mix(
                        with: palette.archiveCard.color,
                        by: 0.12
                    ),
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
        case .archiveCard:
            LinearGradient(
                colors: [
                    palette.archiveCard.color,
                    palette.paper.color.mix(
                        with: palette.archiveCard.color,
                        by: 0.42
                    ),
                ],
                startPoint: .topLeading,
                endPoint: .bottom
            )
        }
    }

    private func textureColor(_ palette: FlightTheme.Palette) -> Color {
        switch style {
        case .cover: palette.warmGold.color
        case .paper, .archiveCard: palette.paperInk.color
        }
    }

    private func borderColor(_ palette: FlightTheme.Palette) -> Color {
        switch style {
        case .cover: palette.warmGold.color.opacity(0.42)
        case .paper, .archiveCard: palette.divider.color.opacity(0.7)
        }
    }

    private func contentInk(
        _ palette: FlightTheme.Palette
    ) -> FlightTheme.ColorToken {
        style == .cover ? palette.passportInk : palette.paperInk
    }
}

private struct PassportTexture: View {
    let color: Color
    let configuration: PassportTextureConfiguration

    var body: some View {
        Canvas { context, size in
            var path = Path()
            switch configuration.pattern {
            case .proceduralDiagonalLines:
                var x: CGFloat = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(
                        to: CGPoint(x: x + size.height, y: size.height)
                    )
                    x += configuration.spacing
                }
            }
            context.stroke(
                path,
                with: .color(color),
                lineWidth: configuration.lineWidth
            )
        }
        .allowsHitTesting(false)
    }
}

#Preview("Passport surfaces") {
    VStack(spacing: 20) {
        PassportSurface(.cover) {
            Text("FLIGHT PASSPORT")
                .font(FlightTheme.Typography.serif(.title, weight: .bold))
                .padding(36)
        }
        PassportSurface(.paper) {
            Text("象牙纸张 · 长中文内容可自然换行")
                .padding(24)
        }
        PassportSurface(.archiveCard) {
            Text("ARCHIVE / 2026")
                .padding(20)
        }
    }
    .padding(32)
    .frame(width: 480)
}
