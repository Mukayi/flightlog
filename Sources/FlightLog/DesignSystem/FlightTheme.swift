import SwiftUI

enum FlightTheme {
    enum Appearance: CaseIterable, Sendable {
        case light
        case dark
    }

    enum Contrast: Sendable {
        case standard
        case increased
    }

    enum SemanticColorRole: CaseIterable, Hashable, Sendable {
        case passportCover
        case passportInk
        case paperInk
        case secondaryInk
        case routeAccent
        case paper
        case archiveCard
        case warmGold
        case dataGold
        case goldInk
        case dangerInk
        case successInk
        case divider
        case shadow
    }

    struct ColorToken: Equatable, Sendable {
        let red: Double
        let green: Double
        let blue: Double
        let opacity: Double

        init(
            red: Double,
            green: Double,
            blue: Double,
            opacity: Double = 1
        ) {
            self.red = red
            self.green = green
            self.blue = blue
            self.opacity = opacity
        }

        var color: Color {
            Color(
                .sRGB,
                red: red,
                green: green,
                blue: blue,
                opacity: opacity
            )
        }

        func contrastRatio(with other: ColorToken) -> Double {
            let lighter = max(relativeLuminance, other.relativeLuminance)
            let darker = min(relativeLuminance, other.relativeLuminance)
            return (lighter + 0.05) / (darker + 0.05)
        }

        private var relativeLuminance: Double {
            func linear(_ channel: Double) -> Double {
                channel <= 0.04045
                    ? channel / 12.92
                    : pow((channel + 0.055) / 1.055, 2.4)
            }

            return 0.2126 * linear(red)
                + 0.7152 * linear(green)
                + 0.0722 * linear(blue)
        }

        func blended(over background: ColorToken, opacity: Double) -> ColorToken {
            let alpha = opacity * self.opacity
            let inverseAlpha = 1 - alpha
            return ColorToken(
                red: red * alpha + background.red * inverseAlpha,
                green: green * alpha + background.green * inverseAlpha,
                blue: blue * alpha + background.blue * inverseAlpha,
                opacity: 1
            )
        }
    }

    struct SidebarSelectionPalette: Equatable, Sendable {
        let background: ColorToken
        let foreground: ColorToken
        let icon: ColorToken
        let indicator: ColorToken
    }

    struct Palette: Equatable, Sendable {
        let passportCover: ColorToken
        let passportInk: ColorToken
        let paperInk: ColorToken
        let secondaryInk: ColorToken
        let routeAccent: ColorToken
        let paper: ColorToken
        let archiveCard: ColorToken
        let warmGold: ColorToken
        let dataGold: ColorToken
        let goldInk: ColorToken
        let dangerInk: ColorToken
        let successInk: ColorToken
        let divider: ColorToken
        let shadow: ColorToken
        let sidebarSelection: SidebarSelectionPalette

        subscript(role: SemanticColorRole) -> ColorToken {
            switch role {
            case .passportCover: passportCover
            case .passportInk: passportInk
            case .paperInk: paperInk
            case .secondaryInk: secondaryInk
            case .routeAccent: routeAccent
            case .paper: paper
            case .archiveCard: archiveCard
            case .warmGold: warmGold
            case .dataGold: dataGold
            case .goldInk: goldInk
            case .dangerInk: dangerInk
            case .successInk: successInk
            case .divider: divider
            case .shadow: shadow
            }
        }
    }

    enum ContrastThreshold {
        static let ordinaryText = 4.5
        static let largeText = 3.0
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 14
        static let large: CGFloat = 22
        static let capsule: CGFloat = 999
    }

    enum Shadow {
        static let subtle = ShadowToken(
            colorOpacity: 0.08,
            radius: 8,
            y: 3
        )
        static let elevated = ShadowToken(
            colorOpacity: 0.14,
            radius: 18,
            y: 8
        )
    }

    struct ShadowToken: Equatable, Sendable {
        let colorOpacity: Double
        let radius: CGFloat
        let y: CGFloat
    }

    struct MotionPolicy: Equatable, Sendable {
        let duration: Double?
        let translation: CGFloat
        let repeatCount: Int
        let hoverScale: CGFloat
        let initialScale: CGFloat
    }

    enum Animation {
        static let quick = 0.16
        static let standard = 0.28
        static let deliberate = 0.42
    }

    enum Texture {
        static let maximumSafeOpacity = 0.06
    }

    enum Typography {
        static func serif(
            _ style: Font.TextStyle,
            weight: Font.Weight = .regular
        ) -> Font {
            .system(style, design: .serif, weight: weight)
        }

        static func rounded(
            _ style: Font.TextStyle,
            weight: Font.Weight = .regular
        ) -> Font {
            .system(style, design: .rounded, weight: weight)
        }

        static func monospaced(
            _ style: Font.TextStyle,
            weight: Font.Weight = .regular
        ) -> Font {
            .system(style, design: .monospaced, weight: weight)
        }
    }

    static func palette(
        for appearance: Appearance,
        contrast: Contrast
    ) -> Palette {
        switch (appearance, contrast) {
        case (.light, .standard):
            Palette(
                passportCover: token(10, 35, 61),
                passportInk: token(247, 242, 226),
                paperInk: token(25, 34, 40),
                secondaryInk: token(77, 83, 82),
                routeAccent: token(20, 125, 144),
                paper: token(247, 242, 226),
                archiveCard: token(232, 224, 202),
                warmGold: token(177, 137, 57),
                dataGold: token(130, 88, 18),
                goldInk: token(103, 66, 8),
                dangerInk: token(145, 20, 36),
                successInk: token(20, 105, 68),
                divider: token(173, 166, 145),
                shadow: token(4, 17, 30),
                sidebarSelection: SidebarSelectionPalette(
                    background: token(247, 242, 226),
                    foreground: token(10, 35, 61),
                    icon: token(0, 85, 105),
                    indicator: token(0, 85, 105)
                )
            )
        case (.light, .increased):
            Palette(
                passportCover: token(3, 24, 45),
                passportInk: token(255, 251, 237),
                paperInk: token(0, 8, 14),
                secondaryInk: token(47, 51, 49),
                routeAccent: token(0, 91, 111),
                paper: token(255, 251, 237),
                archiveCard: token(229, 217, 185),
                warmGold: token(142, 98, 17),
                dataGold: token(118, 72, 4),
                goldInk: token(88, 52, 0),
                dangerInk: token(120, 0, 20),
                successInk: token(0, 90, 55),
                divider: token(105, 96, 73),
                shadow: token(0, 8, 17),
                sidebarSelection: SidebarSelectionPalette(
                    background: token(255, 251, 237),
                    foreground: token(3, 24, 45),
                    icon: token(0, 70, 85),
                    indicator: token(0, 70, 85)
                )
            )
        case (.dark, .standard):
            Palette(
                passportCover: token(5, 18, 34),
                passportInk: token(239, 235, 221),
                paperInk: token(239, 235, 221),
                secondaryInk: token(186, 185, 176),
                routeAccent: token(72, 188, 200),
                paper: token(28, 31, 34),
                archiveCard: token(42, 43, 42),
                warmGold: token(211, 174, 91),
                dataGold: token(211, 174, 91),
                goldInk: token(230, 196, 117),
                dangerInk: token(255, 154, 170),
                successInk: token(112, 220, 160),
                divider: token(76, 79, 78),
                shadow: token(0, 4, 10),
                sidebarSelection: SidebarSelectionPalette(
                    background: token(12, 42, 58),
                    foreground: token(239, 235, 221),
                    icon: token(72, 188, 200),
                    indicator: token(72, 188, 200)
                )
            )
        case (.dark, .increased):
            Palette(
                passportCover: token(0, 9, 20),
                passportInk: token(255, 253, 244),
                paperInk: token(255, 253, 244),
                secondaryInk: token(216, 216, 207),
                routeAccent: token(108, 224, 233),
                paper: token(17, 19, 21),
                archiveCard: token(34, 35, 34),
                warmGold: token(242, 203, 112),
                dataGold: token(242, 203, 112),
                goldInk: token(255, 221, 139),
                dangerInk: token(255, 180, 190),
                successInk: token(140, 240, 180),
                divider: token(141, 145, 143),
                shadow: token(0, 0, 0),
                sidebarSelection: SidebarSelectionPalette(
                    background: token(0, 27, 42),
                    foreground: token(255, 253, 244),
                    icon: token(108, 224, 233),
                    indicator: token(108, 224, 233)
                )
            )
        }
    }

    static func palette(
        colorScheme: ColorScheme,
        accessibilityContrast: ColorSchemeContrast
    ) -> Palette {
        palette(
            for: colorScheme == .dark ? .dark : .light,
            contrast: accessibilityContrast == .increased
                ? .increased
                : .standard
        )
    }

    static func animation(
        duration: Double = Animation.standard,
        reduceMotion: Bool
    ) -> SwiftUI.Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: duration)
    }

    static func motion(reduceMotion: Bool) -> MotionPolicy {
        if reduceMotion {
            return MotionPolicy(
                duration: nil,
                translation: 0,
                repeatCount: 0,
                hoverScale: 1,
                initialScale: 1
            )
        }
        return MotionPolicy(
            duration: Animation.standard,
            translation: 4,
            repeatCount: 1,
            hoverScale: 1.006,
            initialScale: 0.94
        )
    }

    private static func token(
        _ red: Double,
        _ green: Double,
        _ blue: Double
    ) -> ColorToken {
        ColorToken(red: red / 255, green: green / 255, blue: blue / 255)
    }
}
