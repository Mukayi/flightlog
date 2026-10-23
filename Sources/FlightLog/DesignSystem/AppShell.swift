import SwiftUI

enum AppShellContract {
    static let brandText = "FlightLog 飞行档案"
    static let accessibilitySummary = "FlightLog 飞行档案，六个章节的飞行记录应用"
    static let profileSwitcherTitle = "当前用户"
    static let manageProfilesTitle = "管理用户…"
    static let profileSwitcherAccessibilityHint = "打开用户切换与管理菜单"
    static let usesNativeProfileMenu = true
    static let showsProfileFlightCount = false
    static let profileSwitcherUsesExplicitTint = true
    static let minimumWidth: CGFloat = 720
    static let minimumHeight: CGFloat = 520
    static let sidebarMinimumWidth: CGFloat = 176
    static let sidebarIdealWidth: CGFloat = 208
    static let sidebarMaximumWidth: CGFloat = 232
}

enum ProfileSwitcherLayoutContract {
    static let sidebarHorizontalInset = FlightTheme.Spacing.md
    static let brandTopInset = FlightTheme.Spacing.lg
    static let brandBlockHeight: CGFloat = 40
    static let spacingBelowBrand = FlightTheme.Spacing.lg
    static let labelHorizontalInset = FlightTheme.Spacing.sm
    static let labelVerticalInset: CGFloat = 9
    static let labelContentHeight: CGFloat = 22

    static func frame(in windowSize: CGSize) -> CGRect {
        let width = AppShellContract.sidebarIdealWidth
        let y = brandTopInset + brandBlockHeight + spacingBelowBrand
        let height = labelVerticalInset * 2 + labelContentHeight
        return CGRect(x: 0, y: y, width: width, height: height)
    }

    static func labelSamplingRect(in windowSize: CGSize) -> CGRect {
        frame(in: windowSize).insetBy(
            dx: sidebarHorizontalInset + labelHorizontalInset,
            dy: labelVerticalInset
        )
    }

    static func bitmapSamplingRanges(
        in bitmap: NSBitmapImageRep,
        logicalWindowSize: CGSize
    ) -> (x: ClosedRange<Int>, y: ClosedRange<Int>) {
        let rect = labelSamplingRect(in: logicalWindowSize)
        let scaleX = CGFloat(bitmap.pixelsWide) / logicalWindowSize.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / logicalWindowSize.height
        let minimumX = max(0, Int((rect.minX * scaleX).rounded(.down)))
        let maximumX = min(
            bitmap.pixelsWide - 1,
            Int((rect.maxX * scaleX).rounded(.up))
        )
        let minimumY = max(
            0,
            bitmap.pixelsHigh - Int((rect.maxY * scaleY).rounded(.up))
        )
        let maximumY = min(
            bitmap.pixelsHigh - 1,
            bitmap.pixelsHigh - Int((rect.minY * scaleY).rounded(.down))
        )
        return (minimumX...maximumX, minimumY...maximumY)
    }
}

struct ProfileSwitcherVisualStyle: Equatable, Sendable {
    let foreground: FlightTheme.ColorToken
    let background: FlightTheme.ColorToken

    static func resolve(
        palette: FlightTheme.Palette
    ) -> ProfileSwitcherVisualStyle {
        ProfileSwitcherVisualStyle(
            foreground: palette.passportInk,
            background: palette.passportInk.blended(
                over: palette.passportCover,
                opacity: 0.08
            )
        )
    }
}

struct ProfileSwitcherMenuChromeModifier: ViewModifier {
    let style: ProfileSwitcherVisualStyle

    func body(content: Content) -> some View {
        Group {
            if AppShellContract.profileSwitcherUsesExplicitTint {
                content
                    .foregroundStyle(style.foreground.color)
                    .tint(style.foreground.color)
            } else {
                content.foregroundStyle(style.foreground.color)
            }
        }
    }
}

extension View {
    func profileSwitcherMenuChrome(
        style: ProfileSwitcherVisualStyle
    ) -> some View {
        modifier(ProfileSwitcherMenuChromeModifier(style: style))
    }
}

enum AppLayoutContract {
    static let chapterHeaderHeightBudget: CGFloat = 112
    static let routeFilterHeightBudget: CGFloat = 54
    static let dividerHeightBudget: CGFloat = 2

    static var routeMapReservedHeight: CGFloat {
        chapterHeaderHeightBudget
            + routeFilterHeightBudget
            + dividerHeightBudget
    }

    static func routeMapContentHeight(windowHeight: CGFloat) -> CGFloat {
        max(0, windowHeight - routeMapReservedHeight)
    }
}

struct ChapterHeaderLayoutContract: Equatable, Sendable {
    let fixedHeight: CGFloat?
    let titleLineLimit: Int?
    let narrativeLineLimit: Int?
    let allowsVerticalGrowth: Bool

    static let standard = ChapterHeaderLayoutContract(
        fixedHeight: nil,
        titleLineLimit: nil,
        narrativeLineLimit: nil,
        allowsVerticalGrowth: true
    )
}

struct ChapterHeader<Action: View>: View {
    let title: String
    let narrative: String
    let eyebrow: String?
    @ViewBuilder let action: Action

    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    init(
        title: String,
        narrative: String,
        eyebrow: String? = nil,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.narrative = narrative
        self.eyebrow = eyebrow
        self.action = action()
    }

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: FlightTheme.Spacing.lg) {
                heading(palette)
                Spacer(minLength: FlightTheme.Spacing.md)
                action
            }
            VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
                heading(palette)
                action
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FlightTheme.Spacing.lg)
        .padding(.vertical, FlightTheme.Spacing.md)
        .background(palette.paper.color)
    }

    private func heading(_ palette: FlightTheme.Palette) -> some View {
        VStack(alignment: .leading, spacing: FlightTheme.Spacing.xxs) {
            if let eyebrow {
                Text(eyebrow)
                    .font(FlightTheme.Typography.monospaced(.caption, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(palette.routeAccent.color)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(FlightTheme.Typography.serif(.title, weight: .bold))
                .foregroundStyle(palette.paperInk.color)
                .fixedSize(horizontal: false, vertical: true)
            Text(narrative)
                .font(.callout)
                .foregroundStyle(palette.secondaryInk.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(narrative)")
    }
}

extension ChapterHeader where Action == EmptyView {
    init(
        title: String,
        narrative: String,
        eyebrow: String? = nil
    ) {
        self.init(
            title: title,
            narrative: narrative,
            eyebrow: eyebrow
        ) {
            EmptyView()
        }
    }
}

struct PassportBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    var body: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )

        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(palette.passportInk.color, lineWidth: 1.3)
            Circle()
                .stroke(palette.routeAccent.color, lineWidth: 1.2)
                .frame(width: 23, height: 23)
            Path { path in
                path.move(to: CGPoint(x: 11, y: 20))
                path.addCurve(
                    to: CGPoint(x: 29, y: 20),
                    control1: CGPoint(x: 16, y: 14),
                    control2: CGPoint(x: 24, y: 14)
                )
                path.move(to: CGPoint(x: 11, y: 20))
                path.addCurve(
                    to: CGPoint(x: 29, y: 20),
                    control1: CGPoint(x: 16, y: 26),
                    control2: CGPoint(x: 24, y: 26)
                )
            }
            .stroke(palette.passportInk.color, lineWidth: 0.9)
            Image(systemName: "airplane")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(palette.passportInk.color)
                .rotationEffect(.degrees(-18))
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}
