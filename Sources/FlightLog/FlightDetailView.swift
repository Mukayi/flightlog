import SwiftUI

struct FlightDetailView: View {
    let record: FlightRecord
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let presentation = FlightDetailPresentation(record: record)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: FlightTheme.Spacing.xl) {
                ChapterHeader(
                    title: "航班档案",
                    narrative: "\(presentation.boardingPass.departure.iata) 至 \(presentation.boardingPass.arrival.iata) 的登机牌、旅程时间与归档资料。",
                    eyebrow: "FLIGHT ARCHIVE"
                )

                BoardingPassCard(
                    flight: presentation.boardingPass,
                    density: .full
                )

                VStack(alignment: .leading, spacing: FlightTheme.Spacing.md) {
                    ChapterHeader(
                        title: "旅程时间线",
                        narrative: "按保存的历史当地时间与 UTC 偏移展示起飞、飞行时长和到达。",
                        eyebrow: "LOCAL JOURNEY"
                    )
                    FlightJourneyTimeline(presentation: presentation.journey)
                }

                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 260),
                            spacing: FlightTheme.Spacing.md,
                            alignment: .top
                        ),
                    ],
                    alignment: .leading,
                    spacing: FlightTheme.Spacing.md
                ) {
                    ForEach(presentation.archiveSections) { section in
                        archiveCard(section)
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(FlightTheme.Spacing.xl)
        }
        .navigationTitle(record.flightNumber)
        .toolbar {
            ToolbarItemGroup {
                Button("编辑", systemImage: "pencil", action: onEdit)
                Button(
                    "删除",
                    systemImage: "trash",
                    role: .destructive,
                    action: onDelete
                )
            }
        }
    }

    @ViewBuilder
    private func archiveCard(
        _ section: FlightDetailArchiveSection
    ) -> some View {
        PassportSurface(.archiveCard) {
            VStack(alignment: .leading, spacing: 0) {
                Text(section.title)
                    .font(
                        FlightTheme.Typography.serif(
                            .headline,
                            weight: .bold
                        )
                    )
                    .padding(.bottom, FlightTheme.Spacing.xs)
                ForEach(section.fields) { field in
                    DetailRow(title: field.title, value: field.value)
                    if field.id != section.fields.last?.id {
                        Divider()
                    }
                }
            }
            .padding(FlightTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 8)
    }
}
