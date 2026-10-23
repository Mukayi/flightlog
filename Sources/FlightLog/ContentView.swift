import SwiftData
import SwiftUI

struct ContentView: View {
    @ObservedObject private var commandState: AppCommandState
    @EnvironmentObject private var userSession: UserSession
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast
    @Query(sort: \UserProfile.sortOrder)
    private var profiles: [UserProfile]

    @State private var showingProfileManagement = false

    private let repository: AirportRepository?
    private let repositoryError: String?

    init(
        repository: AirportRepository? = nil,
        commandState: AppCommandState
    ) {
        self.commandState = commandState
        if let repository {
            self.repository = repository
            repositoryError = nil
        } else {
            do {
                self.repository = try AirportRepository()
                repositoryError = nil
            } catch {
                self.repository = nil
                repositoryError = "机场资料加载失败：\(error.localizedDescription)"
            }
        }
    }

    init(repository: AirportRepository? = nil) {
        self.init(
            repository: repository,
            commandState: AppCommandState()
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: AppShellContract.sidebarMinimumWidth,
                    ideal: AppShellContract.sidebarIdealWidth,
                    max: AppShellContract.sidebarMaximumWidth
                )
        } detail: {
            chapter(for: commandState.selection ?? .overview)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(
            minWidth: AppShellContract.minimumWidth,
            minHeight: AppShellContract.minimumHeight
        )
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .onAppear {
            userSession.resolve(profiles: sortedProfiles)
        }
        .onChange(of: profiles.map(\.id)) {
            userSession.resolve(profiles: sortedProfiles)
        }
        .sheet(isPresented: $showingProfileManagement) {
            ProfileManagementView()
                .environmentObject(userSession)
        }
    }

    private var sidebar: some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )

        return VStack(alignment: .leading, spacing: FlightTheme.Spacing.lg) {
            HStack(spacing: FlightTheme.Spacing.sm) {
                PassportBadge()
                Text(AppShellContract.brandText)
                    .font(FlightTheme.Typography.serif(.headline, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(palette.passportInk.color)
            .padding(.horizontal, FlightTheme.Spacing.md)
            .padding(.top, FlightTheme.Spacing.lg)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppShellContract.accessibilitySummary)

            profileSwitcher(palette: palette)
                .padding(.horizontal, FlightTheme.Spacing.md)

            ScrollView {
                VStack(spacing: FlightTheme.Spacing.xs) {
                    ForEach(AppSection.allCases) { section in
                        sidebarButton(section, palette: palette)
                    }
                }
                .padding(.horizontal, FlightTheme.Spacing.sm)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.passportCover.color.ignoresSafeArea())
    }

    private var sortedProfiles: [UserProfile] {
        profiles.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var activeProfile: UserProfile? {
        guard let activeProfileID = userSession.activeProfileID else {
            return nil
        }
        return profiles.first { $0.id == activeProfileID }
    }

    private var activeProfileID: UUID {
        activeProfile?.id ?? UserProfileDefaults.id
    }

    private func profileSwitcher(
        palette: FlightTheme.Palette
    ) -> some View {
        let style = ProfileSwitcherVisualStyle.resolve(palette: palette)

        return Menu {
            Picker(
                AppShellContract.profileSwitcherTitle,
                selection: Binding(
                    get: {
                        activeProfile?.id
                            ?? sortedProfiles.first?.id
                            ?? UserProfileDefaults.id
                    },
                    set: { profileID in
                        userSession.activate(profileID)
                    }
                )
            ) {
                ForEach(sortedProfiles) { profile in
                    Label {
                        Text(profile.displayName)
                    } icon: {
                        ProfileColorDot(
                            rawValue: profile.comparisonColorRawValue
                        )
                    }
                    .tag(profile.id)
                }
            }

            Divider()

            Button(AppShellContract.manageProfilesTitle) {
                showingProfileManagement = true
            }
            .keyboardShortcut(",", modifiers: [.command, .shift])
        } label: {
            HStack(spacing: FlightTheme.Spacing.sm) {
                ProfileColorDot(
                    rawValue: activeProfile?.comparisonColorRawValue
                        ?? UserProfileDefaults.comparisonColorRawValue
                )
                Text(
                    activeProfile?.displayName
                        ?? UserProfileDefaults.displayName
                )
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .padding(.horizontal, FlightTheme.Spacing.sm)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(
                    cornerRadius: FlightTheme.CornerRadius.small,
                    style: .continuous
                )
                .fill(style.background.color)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .profileSwitcherMenuChrome(style: style)
        .accessibilityLabel(
            "当前用户，\(activeProfile?.displayName ?? UserProfileDefaults.displayName)"
        )
        .accessibilityHint(AppShellContract.profileSwitcherAccessibilityHint)
    }

    private func sidebarButton(
        _ section: AppSection,
        palette: FlightTheme.Palette
    ) -> some View {
        let isSelected = commandState.selection == section

        return Button {
            commandState.navigate(to: section)
        } label: {
            HStack(spacing: FlightTheme.Spacing.sm) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        isSelected
                            ? palette.sidebarSelection.indicator.color
                            : Color.clear
                    )
                    .frame(width: 3, height: 24)
                    .accessibilityHidden(true)
                Image(systemName: section.systemImage)
                    .frame(width: 20)
                    .foregroundStyle(
                        isSelected
                            ? palette.sidebarSelection.icon.color
                            : palette.passportInk.color
                    )
                Text(section.title)
                    .fontWeight(isSelected ? .semibold : .regular)
                Spacer(minLength: 0)
            }
            .foregroundStyle(
                isSelected
                    ? palette.sidebarSelection.foreground.color
                    : palette.passportInk.color
            )
            .padding(.horizontal, FlightTheme.Spacing.sm)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(
                    cornerRadius: FlightTheme.CornerRadius.small,
                    style: .continuous
                )
                .fill(
                    isSelected
                        ? palette.sidebarSelection.background.color
                        : Color.clear
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityHint(
            "按 Command \(String(section.keyboardShortcutCharacter)) 打开"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func chapter(for section: AppSection) -> some View {
        let palette = FlightTheme.palette(
            colorScheme: colorScheme,
            accessibilityContrast: accessibilityContrast
        )

        return VStack(spacing: 0) {
            ChapterHeader(
                title: section.title,
                narrative: section.narrative,
                eyebrow: section.eyebrow
            )
            Divider()
                .overlay(palette.divider.color)
                .accessibilityHidden(true)
            detailView(for: section)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(palette.paperInk.color)
        .tint(palette.routeAccent.color)
        .background(palette.paper.color.ignoresSafeArea())
    }

    @ViewBuilder
    private func detailView(for section: AppSection) -> some View {
        Group {
            switch section {
            case .overview:
                OverviewView(
                    profileID: activeProfileID,
                    onAddFlight: {
                        commandState.requestNewFlight()
                    },
                    onOpenFlight: { id in
                        commandState.requestOpenFlight(id: id)
                    },
                    holderDisplayName: activeProfile?.displayName
                        ?? UserProfileDefaults.displayName
                )
            case .flights:
                if let repository {
                    FlightBrowserView(
                        profileID: activeProfileID,
                        repository: repository,
                        commandState: commandState
                    )
                } else {
                    ContentUnavailableView(
                        "无法打开航班管理",
                        systemImage: "exclamationmark.triangle",
                        description: Text(repositoryError ?? "机场资料不可用。")
                    )
                }
            case .map:
                RouteMapView(profileID: activeProfileID)
            case .statistics:
                StatisticsView(profileID: activeProfileID)
            case .settings:
                if let repository {
                    SettingsView(
                        profileID: activeProfileID,
                        profileDisplayName: activeProfile?.displayName
                            ?? UserProfileDefaults.displayName,
                        repository: repository,
                        userSession: userSession
                    )
                } else {
                    ContentUnavailableView(
                        "无法打开设置",
                        systemImage: "exclamationmark.triangle",
                        description: Text(repositoryError ?? "机场资料不可用。")
                    )
                }
            case .comparison:
                ComparisonView(
                    userSession: userSession,
                    commandState: commandState
                )
            }
        }
        .accessibilityIdentifier(
            ProfileSwitchResetPolicy.identity(activeProfileID)
        )
        .id(ProfileSwitchResetPolicy.identity(activeProfileID))
    }
}

#Preview {
    ContentView(repository: AirportRepository(airports: []))
        .modelContainer(
            for: [FlightRecord.self, UserProfile.self],
            inMemory: true
        )
        .environmentObject(UserSession())
        .frame(width: 1_080, height: 720)
}
