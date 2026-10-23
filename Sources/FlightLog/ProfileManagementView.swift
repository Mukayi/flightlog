import SwiftData
import SwiftUI

struct ProfileColorDot: View {
    let rawValue: String
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    var body: some View {
        Circle()
            .fill(
                ComparisonColorPalette.swiftUIColor(
                    ProfileComparisonColor(rawValue: rawValue) ?? .fallback,
                    colorScheme: colorScheme,
                    accessibilityContrast: accessibilityContrast
                )
            )
            .frame(width: 10, height: 10)
            .overlay {
                Circle().stroke(.primary.opacity(0.22), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

struct ProfileManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var userSession: UserSession
    @Query(sort: \UserProfile.sortOrder)
    private var profiles: [UserProfile]

    @State private var newName = ""
    @State private var newColor = ProfileComparisonColor.fallback
    @State private var editingProfile: UserProfile?
    @State private var deletingProfile: UserProfile?
    @State private var errorMessage: String?
    @StateObject private var mutationGate = ProfileMutationGate()

    private var service: ProfileManagementService {
        ProfileManagementService(container: modelContext.container)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("新建用户") {
                    HStack(alignment: .firstTextBaseline) {
                        TextField(
                            "昵称（1–30 个字符）",
                            text: $newName,
                            prompt: Text("例如：工作出行")
                        )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("新用户昵称")

                        colorPicker(selection: $newColor)

                        Button("新建") {
                            createProfile()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            UserProfileNameValidator.normalize(newName).isEmpty
                                || mutationGate.isSubmitting
                        )
                        .accessibilityLabel(
                            ProfileManagementAccessibility.createLabel
                        )
                        .accessibilityHint(
                            ProfileManagementAccessibility.createHint
                        )
                        if mutationGate.isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("正在保存用户")
                        }
                    }
                }

                Section {
                    ForEach(sortedProfiles) { profile in
                        profileRow(profile)
                    }
                } header: {
                    Text("用户档案")
                } footer: {
                    Text("FlightLog 只保存昵称和显示颜色，不采集其他身份信息。")
                }
            }
            .navigationTitle("管理用户")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    .disabled(mutationGate.isSubmitting)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .sheet(item: $editingProfile) { profile in
            ProfileRenameView(profile: profile)
                .environmentObject(userSession)
        }
        .sheet(item: $deletingProfile) { profile in
            ProfileDeletionView(
                profile: profile,
                profiles: sortedProfiles
            )
            .environmentObject(userSession)
        }
        .alert(
            "无法完成操作",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            mutationGate.cancel()
        }
        .onChange(of: userSession.activeProfileID) {
            if mutationGate.isSubmitting {
                mutationGate.cancel()
            }
        }
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

    private func profileRow(_ profile: UserProfile) -> some View {
        HStack(spacing: 12) {
            ProfileColorDot(rawValue: profile.comparisonColorRawValue)

            Text(profile.displayName)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if profile.id == userSession.activeProfileID {
                Text("当前")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        ProfileManagementAccessibility.currentProfileLabel(
                            profileName: profile.displayName
                        )
                    )
            }

            Spacer(minLength: 12)

            Menu("颜色") {
                ForEach(ProfileComparisonColor.allCases) { color in
                    Button {
                        updateColor(profile, color: color)
                    } label: {
                        Label(
                            color.localizedName,
                            systemImage: color.rawValue
                                == profile.comparisonColorRawValue
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                    }
                }
            }
            .disabled(mutationGate.isSubmitting)
            .accessibilityLabel(
                ProfileManagementAccessibility.colorLabel(
                    profileName: profile.displayName
                )
            )
            .accessibilityHint("选择五种预设显示颜色之一")

            Button("重命名") {
                editingProfile = profile
            }
            .disabled(mutationGate.isSubmitting)
            .accessibilityLabel("重命名\(profile.displayName)")
            .accessibilityHint("打开昵称编辑表单")

            Button("删除", role: .destructive) {
                deletingProfile = profile
            }
            .disabled(profiles.count <= 1 || mutationGate.isSubmitting)
            .accessibilityLabel("删除\(profile.displayName)")
            .accessibilityHint(
                ProfileManagementAccessibility.deleteHint(
                    canDelete: profiles.count > 1
                )
            )
        }
        .padding(.vertical, 4)
    }

    private func colorPicker(
        selection: Binding<ProfileComparisonColor>
    ) -> some View {
        Picker("显示颜色", selection: selection) {
            ForEach(ProfileComparisonColor.allCases) { color in
                Text(color.localizedName).tag(color)
            }
        }
        .frame(width: 112)
    }

    private func createProfile() {
        let submittedName = newName
        let submittedColor = newColor.rawValue
        mutationGate.submit {
            try service.create(
                displayName: submittedName,
                comparisonColorRawValue: submittedColor
            )
        } onSuccess: { result in
            newName = ""
            userSession.activate(result.profileID)
        } onError: { error in
            errorMessage = error.localizedDescription
        }
    }

    private func updateColor(
        _ profile: UserProfile,
        color: ProfileComparisonColor
    ) {
        let profileID = profile.id
        mutationGate.submit {
            try service.setColor(
                profileID: profileID,
                comparisonColorRawValue: color.rawValue
            )
        } onError: { error in
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProfileRenameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let profile: UserProfile

    @State private var name: String
    @State private var errorMessage: String?
    @StateObject private var mutationGate = ProfileMutationGate()

    private var service: ProfileManagementService {
        ProfileManagementService(container: modelContext.container)
    }

    init(profile: UserProfile) {
        self.profile = profile
        _name = State(initialValue: profile.displayName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("重命名用户")
                .font(.title2.bold())
            TextField("昵称（1–30 个字符）", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("用户昵称")
            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(mutationGate.isSubmitting)
                Button("保存") {
                    rename()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(mutationGate.isSubmitting)
                .accessibilityHint("保存规范化后的昵称")
                if mutationGate.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在重命名用户")
                }
            }
        }
        .padding(24)
        .frame(minWidth: 400)
        .alert(
            "无法重命名",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            mutationGate.cancel()
        }
    }

    private func rename() {
        let profileID = profile.id
        let submittedName = name
        mutationGate.submit {
            try service.rename(
                profileID: profileID,
                displayName: submittedName
            )
        } onSuccess: { _ in
            dismiss()
        } onError: { error in
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProfileDeletionView: View {
    private enum FlightHandling: String, CaseIterable, Identifiable {
        case delete
        case transfer

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var userSession: UserSession

    let profile: UserProfile
    let profiles: [UserProfile]

    @State private var handling = FlightHandling.transfer
    @State private var transferTargetID: UUID?
    @State private var showingFinalConfirmation = false
    @State private var errorMessage: String?
    @StateObject private var mutationGate = ProfileMutationGate()

    private var service: ProfileManagementService {
        ProfileManagementService(container: modelContext.container)
    }

    private var alternatives: [UserProfile] {
        profiles.filter { $0.id != profile.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("删除“\(profile.displayName)”")
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text("请选择这个用户名下航班的处理方式。此操作需要再次确认。")
                .foregroundStyle(.secondary)

            Picker("航班处理方式", selection: $handling) {
                Text("连同航班删除").tag(FlightHandling.delete)
                Text("迁移到其他用户").tag(FlightHandling.transfer)
            }
            .pickerStyle(.radioGroup)
            .disabled(mutationGate.isSubmitting)
            .accessibilityLabel(
                ProfileManagementAccessibility.deletionStrategyLabel
            )
            .accessibilityHint("决定现有航班是永久删除还是迁移")

            if handling == .transfer {
                Picker(
                    "迁移目标",
                    selection: Binding(
                        get: {
                            transferTargetID ?? alternatives.first?.id
                                ?? UserProfileDefaults.id
                        },
                        set: { transferTargetID = $0 }
                    )
                ) {
                    ForEach(alternatives) { candidate in
                        Text(candidate.displayName).tag(candidate.id)
                    }
                }
                .disabled(mutationGate.isSubmitting)
                .accessibilityLabel("航班迁移目标用户")
                .accessibilityHint("所有航班将转移到所选用户")
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(mutationGate.isSubmitting)
                Button("继续…", role: .destructive) {
                    showingFinalConfirmation = true
                }
                .disabled(
                    mutationGate.isSubmitting
                        || (handling == .transfer && alternatives.isEmpty)
                )
                .accessibilityHint("打开最终删除确认")
                if mutationGate.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在删除用户")
                }
            }
        }
        .padding(24)
        .frame(minWidth: 460)
        .alert(
            "确认删除用户？",
            isPresented: $showingFinalConfirmation
        ) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                deleteProfile()
            }
            .disabled(mutationGate.isSubmitting)
        } message: {
            Text(finalConfirmationMessage)
        }
        .alert(
            "无法删除",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onDisappear {
            mutationGate.cancel()
        }
        .onChange(of: userSession.activeProfileID) {
            if mutationGate.isSubmitting {
                mutationGate.cancel()
            }
        }
    }

    private var finalConfirmationMessage: String {
        switch handling {
        case .delete:
            return "将永久删除“\(profile.displayName)”及其所有航班记录。"
        case .transfer:
            let targetName = alternatives.first {
                $0.id == (transferTargetID ?? alternatives.first?.id)
            }?.displayName ?? "所选用户"
            return "将“\(profile.displayName)”的所有航班迁移到“\(targetName)”，然后删除该用户。"
        }
    }

    private func deleteProfile() {
        let strategy: ProfileDeletionStrategy
        switch handling {
        case .delete:
            strategy = .deleteFlights
        case .transfer:
            guard let targetID = transferTargetID ?? alternatives.first?.id else {
                errorMessage = ProfileManagementError.invalidTransferTarget
                    .localizedDescription
                return
            }
            strategy = .transferFlights(targetProfileID: targetID)
        }

        let profileID = profile.id
        mutationGate.submit {
            try service.delete(
                profileID: profileID,
                strategy: strategy
            )
        } onSuccess: { result in
            if userSession.activeProfileID == result.deletedProfileID {
                userSession.activate(result.fallbackProfileID)
            }
            dismiss()
        } onError: { error in
            errorMessage = error.localizedDescription
        }
    }
}

