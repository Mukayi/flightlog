import SwiftData
import SwiftUI

struct FlightEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let ownerProfileID: UUID
    let repository: AirportRepository
    let record: FlightRecord?
    let recordID: UUID?
    let openedUpdatedAt: Date?
    private let metrics = FlightMetricsService.standard

    @State private var draft: FlightDraft
    @State private var showDuplicateConfirmation = false
    @State private var duplicateCount = 0
    @State private var saveError: String?
    @State private var isLookingUp = false
    @State private var lookupResults: [FlightLookupResult] = []
    @State private var lookupError: String?
    @State private var lookupStatus: String?
    @State private var showLookupOverwriteConfirmation = false
    @State private var lookupCoordinator: FlightLookupCoordinator
    @State private var lookupTask: Task<Void, Never>?

    init(
        ownerProfileID: UUID,
        repository: AirportRepository,
        record: FlightRecord?
    ) {
        self.ownerProfileID = ownerProfileID
        self.repository = repository
        self.record = record
        recordID = record?.id
        openedUpdatedAt = record?.updatedAt

        let initialDraft: FlightDraft
        if let record {
            initialDraft = FlightDraft(
                record: record,
                repository: repository
            )
        } else {
            let now = Date()
            let wallClockNow = (
                try? LocalDateTimeConverter.wallClockDate(
                    from: now,
                    timeZoneID: TimeZone.current.identifier
                )
            ) ?? now
            initialDraft = FlightDraft(
                flightDate: wallClockNow,
                departureLocalDate: wallClockNow,
                arrivalLocalDate: wallClockNow.addingTimeInterval(7_200)
            )
        }
        _draft = State(initialValue: initialDraft)
        _lookupCoordinator = State(
            initialValue: FlightLookupCoordinator(
                draft: initialDraft,
                repository: repository,
                isEditing: record != nil,
                keyStore: KeychainStore(),
                client: AeroDataBoxClient()
            )
        )
    }

    var body: some View {
        let validation = FlightValidator(repository: repository).validate(draft)
        let estimatedDistance = estimatedDistance(for: validation)
        let estimatedDuration = estimatedDuration(for: validation)
        return NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: FlightTheme.Spacing.lg) {
                    ChapterHeader(
                        title: record == nil ? "签发新航班页" : "修订航班页",
                        narrative: "依次核对航班身份、航线时间与旅行备注；所有字段会在保存前再次校验。",
                        eyebrow: "FLIGHT EDITOR"
                    )

                    editorSection(.identity) {
                        identityFields(validation: validation)
                    }
                    editorSection(.routeAndTime) {
                        routeAndTimeFields(
                            validation: validation,
                            estimatedDistance: estimatedDistance,
                            estimatedDuration: estimatedDuration
                        )
                    }
                    editorSection(.travelNotes) {
                        travelNotesFields(validation: validation)
                    }
                }
                .padding(FlightTheme.Spacing.lg)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(record == nil ? "新增航班" : "编辑航班")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        cancelInFlightLookup()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        requestSave()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(
            minWidth: 720,
            idealWidth: 780,
            minHeight: 520,
            idealHeight: 720
        )
        .alert(
            "可能存在重复航班",
            isPresented: $showDuplicateConfirmation
        ) {
            Button("取消", role: .cancel) {}
            Button("仍然保存") {
                persist(allowDuplicate: true)
            }
        } message: {
            Text(
                "找到 \(duplicateCount) 条相同航班号、飞行日期和航线的记录。是否继续保存？"
            )
        }
        .alert(
            "无法保存",
            isPresented: Binding(
                get: { saveError != nil },
                set: { isPresented in
                    if !isPresented {
                        saveError = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(saveError ?? "发生未知错误。")
        }
        .sheet(
            isPresented: Binding(
                get: { !lookupResults.isEmpty },
                set: { if !$0 { cancelLookup() } }
            )
        ) {
            FlightLookupSelectionSheet(
                results: lookupResults,
                onCancel: cancelLookup,
                onSelect: selectLookupResult
            )
        }
        .alert(
            "覆盖当前记录字段？",
            isPresented: $showLookupOverwriteConfirmation
        ) {
            Button("取消", role: .cancel) {
                lookupCoordinator.cancel()
            }
            Button("确认覆盖") {
                lookupCoordinator.confirmOverwrite(currentDraft: draft)
                handleCoordinatorState()
            }
        } message: {
            Text("联网结果将覆盖可映射的航班号、机场、航司、机型和当地时间；备注、舱位和座位不受影响。保存时仍会经过现有校验。")
        }
        .alert(
            "联网查询失败",
            isPresented: Binding(
                get: { lookupError != nil },
                set: { if !$0 { lookupError = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(lookupError ?? "发生未知错误。")
        }
        .onDisappear {
            cancelInFlightLookup()
        }
    }

    private func editorSection<Content: View>(
        _ presentation: FlightEditorSectionPresentation,
        @ViewBuilder content: () -> Content
    ) -> some View {
        PassportSurface(.paper) {
            VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: FlightTheme.Spacing.xxs) {
                    Text(presentation.eyebrow)
                        .font(
                            FlightTheme.Typography.monospaced(
                                .caption,
                                weight: .semibold
                            )
                        )
                        .tracking(1)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(presentation.title)
                        .font(
                            FlightTheme.Typography.serif(
                                .title2,
                                weight: .bold
                            )
                        )
                        .accessibilityAddTraits(.isHeader)
                    Text(presentation.narrative)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                content()
            }
            .padding(FlightTheme.Spacing.lg)
        }
        .accessibilityElement(children: .contain)
    }

    private func identityFields(
        validation: FlightValidationResult
    ) -> some View {
        VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
            DatePicker(
                "飞行日期",
                selection: Binding(
                    get: {
                        FlightDateNormalization.canonicalDate(
                            draft.departureLocalDate
                        )
                    },
                    set: { draft.setFlightDate($0) }
                ),
                displayedComponents: .date
            )
            .environment(\.timeZone, Self.utcTimeZone)
            .frame(maxWidth: 360)
            .disabled(isLookingUp)
            .accessibilityHint("联网查询将按此当地起飞日期匹配航班")
            Text("修改日期会同步移动当地起飞和到达日期，并保留原来的时间。")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("航班号") {
                TextField("例如 CA123", text: $draft.flightNumber)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                    .disabled(isLookingUp)
            }
            FieldErrorView(error: validation.errors[.flightNumber])

            HStack(spacing: FlightTheme.Spacing.sm) {
                Button {
                    performLookup()
                } label: {
                    Label("联网查询", systemImage: "network")
                }
                .disabled(
                    isLookingUp
                        || draft.normalizedFlightNumber.isEmpty
                )
                if isLookingUp {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在查询…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let lookupStatus {
                Label(lookupStatus, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("联网查询按航班号和当地起飞日期匹配。")
                .font(.caption)
                .foregroundStyle(.secondary)

            if
                !draft.flightNumber.isEmpty,
                draft.flightNumber != draft.normalizedFlightNumber
            {
                Text("保存后将标准化为 \(draft.normalizedFlightNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            LabeledContent("航司代码") {
                TextField("可选", text: $draft.airlineCode)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
            }
            FieldErrorView(error: validation.errors[.airlineCode])

            LabeledContent("航司名称") {
                TextField("可选", text: $draft.airlineName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
            }
            FieldErrorView(error: validation.errors[.airlineName])
        }
    }

    private func routeAndTimeFields(
        validation: FlightValidationResult,
        estimatedDistance: Double?,
        estimatedDuration: Int?
    ) -> some View {
        VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
            Text("起飞")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            AirportSearchField(
                title: "出发机场",
                selection: $draft.departureAirport,
                repository: repository,
                error: validation.errors[.departureAirport]
            )
            DatePicker(
                "当地起飞时间",
                selection: $draft.departureLocalDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .environment(\.timeZone, Self.utcTimeZone)
            .disabled(isLookingUp)
            FieldErrorView(error: validation.errors[.departureLocalDate])
            ambiguityPicker(
                choices: draft.departureAmbiguityChoices,
                selection: $draft.departureLocalTimeOccurrence
            )
            timeZoneHint(for: draft.departureAirport)

            Divider()

            Text("到达")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            AirportSearchField(
                title: "到达机场",
                selection: $draft.arrivalAirport,
                repository: repository,
                error: validation.errors[.arrivalAirport]
            )
            DatePicker(
                "当地到达时间",
                selection: $draft.arrivalLocalDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .environment(\.timeZone, Self.utcTimeZone)
            FieldErrorView(error: validation.errors[.arrivalLocalDate])
            ambiguityPicker(
                choices: draft.arrivalAmbiguityChoices,
                selection: $draft.arrivalLocalTimeOccurrence
            )
            timeZoneHint(for: draft.arrivalAirport)

            Divider()

            if let estimatedDistance {
                LabeledContent("预计大圆距离") {
                    Text(
                        "\(metrics.formattedDistance(kilometers: estimatedDistance, unit: .kilometers)) · \(metrics.formattedDistance(kilometers: estimatedDistance, unit: .miles))"
                    )
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.trailing)
                }
            } else if
                validation.departureAirport != nil,
                validation.arrivalAirport != nil
            {
                Text("机场坐标无效，无法计算预计距离。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let estimatedDuration {
                LabeledContent("预计飞行时长") {
                    Text(
                        FlightDisplayFormatting.duration(
                            minutes: estimatedDuration
                        )
                    )
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func ambiguityPicker(
        choices: [LocalWallClockOccurrence],
        selection: Binding<LocalWallClockOccurrence>
    ) -> some View {
        if !choices.isEmpty {
            Picker("重复时间", selection: selection) {
                ForEach(choices, id: \.self) { occurrence in
                    Text(occurrence.title).tag(occurrence)
                }
            }
            .pickerStyle(.segmented)
            Text(FlightEditorPresentationCopy.dstExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func travelNotesFields(
        validation: FlightValidationResult
    ) -> some View {
        VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
            LabeledContent("机型") {
                TextField("可选", text: $draft.aircraftType)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
            }
            FieldErrorView(error: validation.errors[.aircraftType])

            LabeledContent("舱位") {
                TextField("可选", text: $draft.cabinClass)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
            }
            FieldErrorView(error: validation.errors[.cabinClass])

            LabeledContent("座位") {
                TextField("可选", text: $draft.seat)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
            }
            FieldErrorView(error: validation.errors[.seat])

            VStack(alignment: .leading, spacing: FlightTheme.Spacing.xs) {
                Text("备注")
                    .font(.headline)
                TextEditor(text: $draft.notes)
                    .font(.body)
                    .frame(minHeight: 110)
                    .padding(FlightTheme.Spacing.xs)
                    .background(
                        .background,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary)
                    }
                    .accessibilityLabel("备注")
                FieldErrorView(error: validation.errors[.notes])
            }
        }
    }

    @ViewBuilder
    private func timeZoneHint(for airport: Airport?) -> some View {
        if let airport {
            Text("按 \(airport.timeZoneID) 当地时间录入")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func requestSave() {
        let validation = FlightValidator(repository: repository).validate(draft)
        guard validation.isValid else {
            saveError = FlightEditorPresentationCopy.validationAction
            return
        }

        persist(allowDuplicate: false)
    }

    private func performLookup() {
        cancelInFlightLookup()
        lookupStatus = nil
        lookupError = nil
        isLookingUp = true
        lookupCoordinator.replaceDraft(draft)
        lookupTask = Task {
            defer {
                isLookingUp = false
                lookupTask = nil
            }
            await lookupCoordinator.query(currentDraft: { draft })
            guard !Task.isCancelled else { return }
            handleCoordinatorState()
        }
    }

    private func selectLookupResult(_ result: FlightLookupResult) {
        lookupResults = []
        lookupCoordinator.selectCandidate(result, currentDraft: draft)
        if case .awaitingOverwriteConfirmation = lookupCoordinator.state {
            showLookupOverwriteConfirmation = true
        } else {
            handleCoordinatorState()
        }
    }

    private func cancelLookup() {
        cancelInFlightLookup()
    }

    private func cancelInFlightLookup() {
        lookupTask?.cancel()
        lookupTask = nil
        lookupCoordinator.cancel()
        isLookingUp = false
        lookupResults = []
    }

    private func handleCoordinatorState() {
        switch lookupCoordinator.state {
        case .idle, .querying:
            break
        case .awaitingCandidateSelection(let results):
            lookupResults = results
        case .awaitingOverwriteConfirmation:
            showLookupOverwriteConfirmation = true
        case .applied(let report):
            draft = lookupCoordinator.draft
            lookupStatus = "已填充：\(report.filledFields.joined(separator: "、"))。请确认后再保存。"
        case .failed(let message):
            lookupError = message
        }
    }

    private func estimatedDistance(
        for validation: FlightValidationResult
    ) -> Double? {
        guard
            let departureAirport = validation.departureAirport,
            let arrivalAirport = validation.arrivalAirport
        else {
            return nil
        }
        return metrics.distanceKilometers(
            from: departureAirport,
            to: arrivalAirport
        )
    }

    private func estimatedDuration(
        for validation: FlightValidationResult
    ) -> Int? {
        guard
            let departureDate = validation.departureDate,
            let arrivalDate = validation.arrivalDate
        else {
            return nil
        }
        return metrics.durationMinutes(
            departureDate: departureDate,
            arrivalDate: arrivalDate
        )
    }

    private func persist(allowDuplicate: Bool) {
        do {
            let outcome = try FlightEditorSaveService.save(
                draft: draft,
                editingID: recordID,
                openedUpdatedAt: openedUpdatedAt,
                ownerProfileID: ownerProfileID,
                repository: repository,
                in: modelContext,
                allowDuplicate: allowDuplicate
            )
            switch outcome {
            case .saved:
                dismiss()
            case .requiresDuplicateConfirmation(let count):
                duplicateCount = count
                showDuplicateConfirmation = true
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private static let utcTimeZone = TimeZone(secondsFromGMT: 0)!
}

private struct FlightLookupSelectionSheet: View {
    let results: [FlightLookupResult]
    let onCancel: () -> Void
    let onSelect: (FlightLookupResult) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: FlightTheme.Spacing.lg) {
                    ForEach(results) { result in
                        let preview =
                            FlightEditorLookupBoardingPassPresentation.make(
                                result: result,
                                candidateCount: results.count
                            )
                        VStack(
                            alignment: .leading,
                            spacing: FlightTheme.Spacing.sm
                        ) {
                            BoardingPassCard(
                                flight: preview.flight,
                                density: .full
                            )
                            HStack {
                                Text(
                                    results.count == 1
                                        ? "请核对联网结果后再填充。"
                                        : "核对后选择与行程相符的航班。"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: FlightTheme.Spacing.md)
                                Button(preview.actionTitle) {
                                    onSelect(result)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }
                .padding(FlightTheme.Spacing.lg)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(results.count == 1 ? "确认查询结果" : "选择查询结果")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
            }
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 420)
    }
}

private struct AirportSearchField: View {
    let title: String
    @Binding var selection: Airport?
    let repository: AirportRepository
    let error: String?

    @State private var isSelecting = false
    @State private var query = ""
    @FocusState private var queryIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            LabeledContent(title) {
                Button {
                    query = selection?.iata ?? ""
                    isSelecting = true
                } label: {
                    HStack {
                        Text(selectionText)
                        Spacer()
                        Image(systemName: "magnifyingglass")
                    }
                    .frame(maxWidth: 320)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("\(title)：\(selectionText)")
                .accessibilityHint("打开机场搜索")
                .popover(isPresented: $isSelecting, arrowEdge: .trailing) {
                    selectionPopover
                }
            }

            if let selection {
                Text(
                    "\(selection.name) · \(selection.city)，\(selection.country)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            FieldErrorView(error: error)
        }
    }

    private var selectionText: String {
        guard let selection else {
            return "搜索并选择机场"
        }
        return "\(selection.iata) · \(selection.city)"
    }

    private var matches: [Airport] {
        repository.search(query, limit: 50)
    }

    private var selectionPopover: some View {
        VStack(spacing: 12) {
            TextField(AirportSearchPresentation.prompt, text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($queryIsFocused)

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "搜索机场",
                    systemImage: "magnifyingglass",
                    description: Text(
                        "支持中文、IATA/ICAO、机场或城市。"
                    )
                )
            } else if matches.isEmpty {
                ContentUnavailableView(
                    "没有找到机场",
                    systemImage: "magnifyingglass",
                    description: Text("没有与“\(query)”匹配的机场。")
                )
            } else {
                List(matches) { airport in
                    Button {
                        selection = airport
                        isSelecting = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(airport.iata)
                                    .font(.headline)
                                if !airport.icao.isEmpty {
                                    Text(airport.icao)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(airport.timeZoneID)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            if let aliases = AirportSearchPresentation
                                .chineseAliasText(for: airport) {
                                Text(aliases)
                                    .foregroundStyle(.primary)
                            }
                            Text(airport.name)
                            Text("\(airport.city)，\(airport.country)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
            }

            HStack {
                if selection != nil {
                    Button("清除选择", role: .destructive) {
                        selection = nil
                        isSelecting = false
                    }
                }
                Spacer()
                Button("关闭") {
                    isSelecting = false
                }
            }
        }
        .padding(16)
        .frame(width: 520, height: 430)
        .onAppear {
            queryIsFocused = true
        }
    }
}

private struct FieldErrorView: View {
    let error: String?
    @Environment(\.colorScheme) private var colorScheme
    @FlightLogAccessibilityContrast private var accessibilityContrast

    var body: some View {
        if let error {
            let palette = FlightTheme.palette(
                colorScheme: colorScheme,
                accessibilityContrast: accessibilityContrast
            )
            Label(error, systemImage: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(palette.dangerInk.color)
                .accessibilityLabel("错误：\(error)")
        }
    }
}
