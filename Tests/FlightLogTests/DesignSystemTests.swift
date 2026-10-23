import XCTest
@testable import FlightLog

final class DesignSystemTests: XCTestCase {
    func testThemeExposesSemanticRolesAndAdaptivePalettes() {
        XCTAssertEqual(
            Set(FlightTheme.SemanticColorRole.allCases),
            Set([
                .passportCover,
                .passportInk,
                .paperInk,
                .secondaryInk,
                .routeAccent,
                .paper,
                .archiveCard,
                .warmGold,
                .dataGold,
                .goldInk,
                .dangerInk,
                .successInk,
                .divider,
                .shadow,
            ])
        )

        let light = FlightTheme.palette(for: .light, contrast: .standard)
        let dark = FlightTheme.palette(for: .dark, contrast: .standard)
        XCTAssertNotEqual(light.passportCover, dark.passportCover)
        XCTAssertNotEqual(light.paper, dark.paper)
        XCTAssertNotEqual(light.paperInk, dark.paperInk)
    }

    func testDangerInkMeetsTextAndGraphicContrastOnPaperSurfaces() {
        for appearance in FlightTheme.Appearance.allCases {
            for contrast in [FlightTheme.Contrast.standard, .increased] {
                let palette = FlightTheme.palette(
                    for: appearance,
                    contrast: contrast
                )
                for (surface, background) in [
                    ("paper", palette.paper),
                    ("archive", palette.archiveCard),
                ] {
                    XCTAssertGreaterThanOrEqual(
                        palette.dangerInk.contrastRatio(with: background),
                        FlightTheme.ContrastThreshold.ordinaryText,
                        "\(appearance) \(contrast) \(surface) danger text"
                    )
                    XCTAssertGreaterThanOrEqual(
                        palette.dangerInk.contrastRatio(with: background),
                        FlightTheme.ContrastThreshold.largeText,
                        "\(appearance) \(contrast) \(surface) danger graphic"
                    )
                }
                XCTAssertEqual(palette[.dangerInk], palette.dangerInk)
            }
        }
    }

    func testSuccessAndWarningInksMeetStatusContrastOnPaperSurfaces() {
        for appearance in FlightTheme.Appearance.allCases {
            for contrast in [FlightTheme.Contrast.standard, .increased] {
                let palette = FlightTheme.palette(
                    for: appearance,
                    contrast: contrast
                )
                for (surface, background) in [
                    ("paper", palette.paper),
                    ("archive", palette.archiveCard),
                ] {
                    for (status, ink) in [
                        ("success", palette.successInk),
                        ("warning", palette.goldInk),
                    ] {
                        XCTAssertGreaterThanOrEqual(
                            ink.contrastRatio(with: background),
                            FlightTheme.ContrastThreshold.ordinaryText,
                            "\(appearance) \(contrast) \(surface) \(status) text"
                        )
                        XCTAssertGreaterThanOrEqual(
                            ink.contrastRatio(with: background),
                            FlightTheme.ContrastThreshold.largeText,
                            "\(appearance) \(contrast) \(surface) \(status) graphic"
                        )
                    }
                }
                XCTAssertEqual(palette[.successInk], palette.successInk)
            }
        }
    }

    func testIncreasedContrastStrengthensTextAndDividerContrast() {
        for appearance in FlightTheme.Appearance.allCases {
            let standard = FlightTheme.palette(
                for: appearance,
                contrast: .standard
            )
            let increased = FlightTheme.palette(
                for: appearance,
                contrast: .increased
            )

            XCTAssertGreaterThanOrEqual(
                increased.paperInk.contrastRatio(with: increased.paper),
                standard.paperInk.contrastRatio(with: standard.paper)
            )
            XCTAssertGreaterThan(
                increased.divider.contrastRatio(with: increased.paper),
                standard.divider.contrastRatio(with: standard.paper)
            )
        }
    }

    func testSurfaceTextContrastMeetsOrdinaryTextThresholdAcrossAppearanceMatrix() {
        for appearance in FlightTheme.Appearance.allCases {
            for contrast in [FlightTheme.Contrast.standard, .increased] {
                let palette = FlightTheme.palette(
                    for: appearance,
                    contrast: contrast
                )
                let combinations = [
                    ("passport", palette.passportInk, palette.passportCover),
                    ("paper-primary", palette.paperInk, palette.paper),
                    ("paper-secondary", palette.secondaryInk, palette.paper),
                    ("archive-primary", palette.paperInk, palette.archiveCard),
                    ("archive-secondary", palette.secondaryInk, palette.archiveCard),
                ]

                for (surface, ink, background) in combinations {
                    XCTAssertGreaterThanOrEqual(
                        ink.contrastRatio(with: background),
                        FlightTheme.ContrastThreshold.ordinaryText,
                        "\(appearance) \(contrast) \(surface)"
                    )
                    XCTAssertGreaterThanOrEqual(
                        ink.contrastRatio(with: background),
                        FlightTheme.ContrastThreshold.largeText,
                        "\(appearance) \(contrast) \(surface) large text"
                    )
                }
            }
        }
    }

    func testShadowColorIsAThemeSemanticToken() {
        for appearance in FlightTheme.Appearance.allCases {
            for contrast in [FlightTheme.Contrast.standard, .increased] {
                let palette = FlightTheme.palette(for: appearance, contrast: contrast)
                XCTAssertEqual(palette[.shadow], palette.shadow)
                XCTAssertGreaterThan(palette.shadow.opacity, 0)
            }
        }
    }

    func testReduceMotionPolicyDisablesMovementAndRepeatingAnimation() {
        let reduced = FlightTheme.motion(reduceMotion: true)
        XCTAssertEqual(reduced.translation, 0)
        XCTAssertEqual(reduced.repeatCount, 0)
        XCTAssertEqual(reduced.hoverScale, 1)
        XCTAssertEqual(reduced.initialScale, 1)
        XCTAssertNil(reduced.duration)

        let standard = FlightTheme.motion(reduceMotion: false)
        XCTAssertGreaterThan(standard.duration ?? 0, 0)
        XCTAssertGreaterThan(standard.hoverScale, 1)
        XCTAssertLessThan(standard.initialScale, 1)
    }

    func testTextureConfigurationIsProceduralAndUsesSafeOpacity() {
        for style in PassportSurfaceStyle.allCases {
            let texture = style.textureConfiguration
            XCTAssertEqual(texture.pattern, .proceduralDiagonalLines)
            XCTAssertGreaterThan(texture.spacing, 0)
            XCTAssertGreaterThan(texture.lineWidth, 0)
            XCTAssertLessThanOrEqual(
                texture.opacity,
                FlightTheme.Texture.maximumSafeOpacity
            )
        }
    }

    func testThemeLayoutAndMotionTokensRemainOrdered() {
        XCTAssertLessThan(FlightTheme.Spacing.xs, FlightTheme.Spacing.sm)
        XCTAssertLessThan(FlightTheme.Spacing.sm, FlightTheme.Spacing.md)
        XCTAssertLessThan(FlightTheme.Spacing.md, FlightTheme.Spacing.lg)
        XCTAssertLessThan(FlightTheme.CornerRadius.small, FlightTheme.CornerRadius.large)
        XCTAssertLessThan(FlightTheme.Animation.quick, FlightTheme.Animation.standard)
    }

    func testPresentationNormalizesBlankValuesToUnknown() {
        let presentation = FlightPresentation(
            flightNumber: " ",
            date: "",
            airline: nil,
            departure: .init(iata: "", city: "  ", localTime: nil),
            arrival: .init(iata: nil, city: "", localTime: " "),
            duration: nil
        )

        XCTAssertEqual(presentation.flightNumber, "Unknown")
        XCTAssertEqual(presentation.date, "Unknown")
        XCTAssertEqual(presentation.airline, "Unknown")
        XCTAssertEqual(presentation.departure.iata, "Unknown")
        XCTAssertEqual(presentation.departure.city, "Unknown")
        XCTAssertEqual(presentation.departure.localTime, "Unknown")
        XCTAssertEqual(presentation.arrival, .unknown)
        XCTAssertEqual(presentation.duration, "Unknown")
    }

    func testRouteAndStampProvideCompleteAccessibilityLabels() {
        let route = RouteBadgePresentation(
            departureIATA: "PVG",
            arrivalIATA: "LHR"
        )
        XCTAssertEqual(route.accessibilityLabel, "航线，PVG 至 LHR")

        let unknownRoute = RouteBadgePresentation(
            departureIATA: nil,
            arrivalIATA: " "
        )
        XCTAssertEqual(unknownRoute.accessibilityLabel, "航线，Unknown 至 Unknown")

        let stamp = PassportStampPresentation(
            title: "首次跨洲飞行",
            detail: "上海至伦敦"
        )
        XCTAssertEqual(
            stamp.accessibilityLabel,
            "签章，首次跨洲飞行，上海至伦敦"
        )
    }

    func testCompactAndFullDensityExposeStableFieldContracts() {
        XCTAssertEqual(
            FlightCardDensity.compact.visibleFields,
            [
                .flightNumber,
                .date,
                .airline,
                .route,
                .localTimes,
                .duration,
            ]
        )
        XCTAssertEqual(
            FlightCardDensity.full.visibleFields,
            [
                .flightNumber,
                .date,
                .airline,
                .route,
                .cities,
                .localTimes,
                .duration,
            ]
        )
    }

    func testReusableComponentsExposeUnboundedLongTextLayoutContract() {
        for density in [FlightCardDensity.compact, .full] {
            XCTAssertNil(density.layoutContract.fixedContentHeight)
            XCTAssertNil(density.layoutContract.lineLimit)
            XCTAssertTrue(density.layoutContract.allowsVerticalGrowth)
            XCTAssertFalse(density.layoutContract.truncatesLongText)
        }

        let metric = MetricStampPresentation(
            title: String(repeating: "超长中文指标", count: 20),
            value: String(repeating: "Unknown ", count: 20),
            detail: String(repeating: "可换行说明", count: 20),
            systemImage: "clock"
        )
        let timeline = FlightTimelinePresentation(
            flights: [longFlight],
            density: .full
        )
        XCTAssertEqual(metric.layoutContract, .unboundedText)
        XCTAssertEqual(timeline.layoutContract, .unboundedText)
        XCTAssertEqual(metric.title, String(repeating: "超长中文指标", count: 20))
        XCTAssertEqual(longFlight.airline, String(repeating: "超长航空公司", count: 20))
    }

    func testComponentAccessibilityContractsContainCoreFieldsAndExcludeDecorations() {
        let boarding = longFlight.boardingPassAccessibility
        XCTAssertEqual(boarding.label, "登机牌，CA 937")
        for coreField in [
            "2026年8月19日",
            String(repeating: "超长航空公司", count: 20),
            "PVG",
            "上海",
            "08:35",
            "LHR",
            "伦敦",
            "15:50",
            "12 小时 15 分钟",
        ] {
            XCTAssertTrue(boarding.value.contains(coreField), coreField)
        }
        XCTAssertFalse(boarding.value.contains("airplane"))

        let metric = MetricStampPresentation(
            title: "累计飞行时长",
            value: "1,286 小时",
            detail: "已知航班",
            systemImage: "clock"
        ).accessibility
        XCTAssertEqual(metric.label, "累计飞行时长")
        XCTAssertEqual(metric.value, "1,286 小时，已知航班")
        XCTAssertFalse(metric.value.contains("clock"))
    }

    func testTimelineContainerAnnouncesOnlySummaryWhileChildCardKeepsDetails() {
        let timeline = FlightTimelinePresentation(
            flights: [longFlight],
            density: .compact
        ).accessibility

        XCTAssertEqual(timeline.label, "航班时间线")
        XCTAssertEqual(timeline.value, "1 个航班")
        for childDetail in ["CA 937", "PVG", "LHR", "2026年8月19日"] {
            XCTAssertFalse(timeline.value.contains(childDetail), childDetail)
        }

        let child = longFlight.boardingPassAccessibility
        XCTAssertEqual(child.label, "登机牌，CA 937")
        for childDetail in [
            "CA 937",
            "PVG",
            "上海",
            "08:35",
            "LHR",
            "伦敦",
            "15:50",
            "12 小时 15 分钟",
        ] {
            XCTAssertTrue(child.value.contains(childDetail), childDetail)
        }
    }

    func testFlightPresentationIsEquatableAndSendable() {
        let flight = FlightPresentation(
            flightNumber: "CA 937",
            date: "2026年8月19日",
            airline: "中国国际航空",
            departure: .init(
                iata: "PVG",
                city: "上海",
                localTime: "08:35"
            ),
            arrival: .init(
                iata: "LHR",
                city: "伦敦",
                localTime: "15:50"
            ),
            duration: "12 小时 15 分钟"
        )

        assertSendable(flight)
        XCTAssertEqual(flight, flight)
        XCTAssertEqual(
            flight.accessibilityLabel,
            "CA 937，2026年8月19日，中国国际航空，PVG 上海 08:35 至 LHR 伦敦 15:50，12 小时 15 分钟"
        )
    }

    private var longFlight: FlightPresentation {
        FlightPresentation(
            flightNumber: "CA 937",
            date: "2026年8月19日",
            airline: String(repeating: "超长航空公司", count: 20),
            departure: .init(iata: "PVG", city: "上海", localTime: "08:35"),
            arrival: .init(iata: "LHR", city: "伦敦", localTime: "15:50"),
            duration: "12 小时 15 分钟"
        )
    }

    private func assertSendable<T: Sendable>(_: T) {}
}
