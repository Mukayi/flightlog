import SwiftData
import SwiftUI

struct FlightBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Query
    private var records: [FlightRecord]

    let profileID: UUID
    private let mountID = UUID()
    let repository: AirportRepository
    @ObservedObject var commandState: AppCommandState

    @State private var selectedID: UUID?
    @State private var searchText = ""
    @State private var sortOrder: FlightSortOrder = .dateDescending
    @State private var filter = FlightListFilter()
    @State private var showingEditor = false
    @State private var editorRecord: FlightRecord?
    @State private var deletionRecord: FlightRecord?
    @State private var showingDeleteConfirmation = false
    @State private var persistenceError: String?
    @FocusState private var searchIsFocused: Bool

    init(
        profileID: UUID = UserProfileDefaults.id,
        repository: AirportRepository,
        commandState: AppCommandState
    ) {
        self.profileID = profileID
        self.repository = repository
        self.commandState = commandState
        let ownerID: UUID? = profileID
        _records = Query(
            filter: #Predicate { $0.ownerProfileID == ownerID },
            sort: \.flightDate,
            order: .reverse
        )
    }

    var body: some View {
        NavigationSplitView {
            listPane
                .navigationSplitViewColumnWidth(min: 320, ideal: 390)
        } detail: {
            if let selectedRecord {
                FlightDetailView(
                    record: selectedRecord,
                    onEdit: {
                        editorRecord = selectedRecord
                        showingEditor = true
                    },
                    onDelete: {
                        deletionRecord = selectedRecord
                        showingDeleteConfirmation = true
                    }
                )
            } else {
                ContentUnavailableView(
                    "选择一条航班",
                    systemImage: "airplane",
                    description: Text("从列表中选择航班以查看详情。")
                )
            }
        }
        .onChange(of: filteredRecordIDs) { _, visibleIDs in
            selectedID = FlightListSelection.reconciled(
                selectedID: selectedID,
                visibleIDs: visibleIDs
            )
        }
        .onChange(of: profileID) {
            resetProfileState()
        }
        .onAppear {
            reportProfileScope()
            handleCommandRequests()
        }
        .onChange(of: records.map(\.id)) {
            reportProfileScope()
        }
        .onChange(of: commandState.newFlightRequest) {
            handleCommandRequests()
        }
        .onChange(of: commandState.focusSearchRequest) {
            handleCommandRequests()
        }
        .onChange(of: commandState.openFlightRequest) {
            handleCommandRequests()
        }
        .onChange(of: showingEditor) { _, isPresented in
            if !isPresented {
                handleCommandRequests()
            }
        }
        .sheet(isPresented: $showingEditor) {
            FlightEditorView(
                ownerProfileID: profileID,
                repository: repository,
                record: editorRecord
            )
        }
        .alert(
            "删除航班？",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("取消", role: .cancel) {
                deletionRecord = nil
            }
            Button("删除", role: .destructive) {
                deletePendingRecord()
            }
        } message: {
            if let deletionRecord {
                Text(
                    "将永久删除 \(deletionRecord.flightNumber)（\(deletionRecord.departureAirportIATA) → \(deletionRecord.arrivalAirportIATA)）。"
                )
            }
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { persistenceError != nil },
                set: { isPresented in
                    if !isPresented {
                        persistenceError = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(persistenceError ?? "发生未知错误。")
        }
    }

    @ViewBuilder
    private var listPane: some View {
        Group {
            if filteredRecords.isEmpty {
                ContentUnavailableView {
                    Label(
                        records.isEmpty
                            ? FlightBrowserPresentation.emptyRecordsTitle
                            : FlightBrowserPresentation.noMatchesTitle,
                        systemImage: records.isEmpty
                            ? "airplane.circle"
                            : "magnifyingglass"
                    )
                } description: {
                    Text(
                        records.isEmpty
                            ? "录入首段航班，让旅程在飞行档案中留下第一枚签章。"
                            : "请调整搜索词或筛选条件。"
                    )
                } actions: {
                    if emptyRecovery == .addFlight {
                        Button("新增航班", systemImage: "plus") {
                            performEmptyRecovery()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button(
                            emptyRecoveryTitle,
                            systemImage: "arrow.counterclockwise"
                        ) {
                            performEmptyRecovery()
                        }
                    }
                }
            } else {
                List(filteredRecords, selection: $selectedID) { record in
                    FlightRowView(
                        record: record,
                        isSelected: selectedID == record.id
                    )
                        .tag(record.id)
                        .contextMenu {
                            Button("编辑") {
                                editorRecord = record
                                showingEditor = true
                            }
                            Button("删除", role: .destructive) {
                                deletionRecord = record
                                showingDeleteConfirmation = true
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: FlightBrowserPresentation.searchPrompt
        )
        .searchFocused($searchIsFocused)
        .toolbar {
            ToolbarItemGroup {
                sortMenu
                filterMenu
                Button("新增航班", systemImage: "plus") {
                    presentNewFlight()
                }
                .help("新增航班（Command-N）")
            }
        }
    }

    private var filteredRecords: [FlightRecord] {
        FlightListQuery.apply(
            to: records,
            searchText: searchText,
            sortOrder: sortOrder,
            filter: filter
        )
    }

    private var filteredRecordIDs: [UUID] {
        filteredRecords.map(\.id)
    }

    private var selectedRecord: FlightRecord? {
        guard let selectedID else { return nil }
        return records.first { $0.id == selectedID }
    }

    private var emptyRecovery: FlightListEmptyRecovery {
        FlightListEmptyRecovery.resolve(
            hasRecords: !records.isEmpty,
            searchText: searchText,
            filterIsActive: filter.isActive
        )
    }

    private var emptyRecoveryTitle: String {
        switch emptyRecovery {
        case .addFlight:
            "新增航班"
        case .clearSearch:
            "清除搜索"
        case .clearFilters:
            "清除筛选"
        case .clearSearchAndFilters:
            "清除搜索和筛选"
        }
    }

    private var years: [Int] {
        Array(
            Set(
                records.map {
                    Self.utcCalendar.component(.year, from: $0.flightDate)
                }
            )
        )
        .sorted(by: >)
    }

    private var airlineOptions: [String] {
        Array(
            Set(
                records.compactMap { record in
                    if !record.airlineCode.isEmpty {
                        return record.airlineCode
                    }
                    if !record.airlineName.isEmpty {
                        return record.airlineName
                    }
                    return nil
                }
            )
        )
        .sorted()
    }

    private var airportOptions: [String] {
        Array(
            Set(
                records.flatMap {
                    [
                        $0.departureAirportIATA,
                        $0.arrivalAirportIATA,
                    ]
                }
            )
        )
        .sorted()
    }

    private var sortMenu: some View {
        Menu {
            Picker("排序方式", selection: $sortOrder) {
                ForEach(FlightSortOrder.allCases) { order in
                    Text(order.title)
                        .tag(order)
                }
            }
        } label: {
            Label("排序", systemImage: "arrow.up.arrow.down")
        }
        .help("更改航班排序")
    }

    private var filterMenu: some View {
        Menu {
            Menu("年份") {
                Button(filter.year == nil ? "✓ 全部年份" : "全部年份") {
                    filter.year = nil
                }
                ForEach(years, id: \.self) { year in
                    Button(
                        filter.year == year
                            ? "✓ \(year) 年"
                            : "\(year) 年"
                    ) {
                        filter.year = year
                    }
                }
            }

            Menu("航司") {
                Button(filter.airline == nil ? "✓ 全部航司" : "全部航司") {
                    filter.airline = nil
                }
                ForEach(airlineOptions, id: \.self) { airline in
                    Button(
                        filter.airline == airline
                            ? "✓ \(airline)"
                            : airline
                    ) {
                        filter.airline = airline
                    }
                }
            }

            Menu("机场") {
                Button(filter.airportIATA == nil ? "✓ 全部机场" : "全部机场") {
                    filter.airportIATA = nil
                }
                ForEach(airportOptions, id: \.self) { airport in
                    Button(
                        filter.airportIATA == airport
                            ? "✓ \(airport)"
                            : airport
                    ) {
                        filter.airportIATA = airport
                    }
                }
            }

            if filter.isActive {
                Divider()
                Button("清除全部筛选", role: .destructive) {
                    filter = FlightListFilter()
                }
            }
        } label: {
            Label(
                filter.isActive ? "筛选已启用" : "筛选",
                systemImage: filter.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
        .help("按年份、航司或机场筛选")
    }

    private func presentNewFlight() {
        editorRecord = nil
        showingEditor = true
    }

    private func performEmptyRecovery() {
        switch emptyRecovery {
        case .addFlight:
            presentNewFlight()
        case .clearSearch:
            searchText = ""
            searchIsFocused = true
        case .clearFilters:
            filter = FlightListFilter()
        case .clearSearchAndFilters:
            searchText = ""
            filter = FlightListFilter()
            searchIsFocused = true
        }
    }

    private func handleCommandRequests() {
        if commandState.takeNewFlightRequest() {
            presentNewFlight()
        }
        guard !showingEditor else {
            return
        }
        if let requestedID = commandState.takeOpenFlightRequest() {
            applyOpenFlightRequest(requestedID)
        }
        if commandState.takeFocusSearchRequest() {
            searchIsFocused = true
        }
    }

    private func applyOpenFlightRequest(_ requestedID: UUID) {
        guard
            let resolution = FlightOpenRequestResolution.resolve(
                requestedID: requestedID,
                records: records,
                searchText: searchText,
                sortOrder: sortOrder,
                filter: filter
            )
        else {
            return
        }
        searchText = resolution.searchText
        filter = resolution.filter
        selectedID = resolution.selectedID
    }

    private func deletePendingRecord() {
        guard
            let deletionRecord,
            deletionRecord.ownerProfileID == profileID
        else {
            self.deletionRecord = nil
            persistenceError = "该航班不属于当前用户，无法删除。"
            return
        }

        do {
            modelContext.delete(deletionRecord)
            try modelContext.save()
            if selectedID == deletionRecord.id {
                selectedID = nil
            }
            self.deletionRecord = nil
        } catch {
            modelContext.rollback()
            persistenceError = "删除失败：\(error.localizedDescription)"
        }
    }

    private func resetProfileState() {
        selectedID = nil
        searchText = ""
        filter = FlightListFilter()
        editorRecord = nil
        deletionRecord = nil
        showingEditor = false
        showingDeleteConfirmation = false
        searchIsFocused = false
    }

    private func reportProfileScope() {
        #if DEBUG
        ProfileScopeMountProbe.record(
            ProfileScopeMountSnapshot(
                section: .flights,
                profileID: profileID,
                recordCount: records.count,
                holderDisplayName: nil,
                mountID: mountID
            )
        )
        #endif
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
