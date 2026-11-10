import SwiftUI

/// The next visit and the couple's list of things to do together. Without a planned visit it
/// asks when they meet next, and the list still shows, since ideas come before a date does.
/// Owns its whole presentation, so callers only need `.sheet { VisitDetailView(...) }`.
struct VisitDetailView: View {
    let visits: VisitsViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var editor: Editor?
    @State private var newItemTitle = ""
    @FocusState private var isAddFieldFocused: Bool
    /// Refreshed at midnight so the count moves on while the screen stays open.
    @State private var now = Date()

    private enum Editor: Identifiable {
        case new
        case edit(Visit)

        var id: String {
            switch self {
            case .new: "new"
            case let .edit(visit): visit.id.uuidString
            }
        }
    }

    var body: some View {
        let today = LockScreenCalendarDate(containing: now, in: .current)
        let visit = visits.state.currentOrNext(on: today)
        NavigationStack {
            List {
                Section {
                    if let visit {
                        visitHeader(visit, today: today)
                    } else {
                        noVisitHeader
                    }
                }
                .listRowBackground(Color.paeoniaSurfacePrimary)
                listSection
            }
            .paeoniaGroupedList()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Text(.homeVisitLabel))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let visit {
                    ToolbarItem(placement: .primaryAction) {
                        Button { editor = .edit(visit) } label: {
                            Text(.visitDetailEdit)
                        }
                        .accessibilityIdentifier("visit.detail.edit")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Text(.commonDone)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(.paeoniaBackgroundPrimary)
        .onCalendarDayChange { now = Date() }
        .sheet(item: $editor) { editor in
            switch editor {
            case .new:
                VisitEditorView(visit: nil, visits: visits)
            case let .edit(visit):
                VisitEditorView(visit: visit, visits: visits)
            }
        }
    }

    private var listSection: some View {
        Section {
            ForEach(visits.state.items) { item in
                TogetherListRow(item: item) {
                    Task { await visits.setItemDone(id: item.id, !item.isDone) }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await visits.deleteItem(id: item.id) }
                    } label: {
                        Text(.visitListDelete)
                    }
                }
            }
            addRow
        } header: {
            Text(.visitListTitle)
        } footer: {
            if visits.state.items.isEmpty {
                Text(.visitListEmpty)
            }
        }
        .listRowBackground(Color.paeoniaSurfacePrimary)
    }

    private func visitHeader(_ visit: Visit, today: LockScreenCalendarDate) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
            if let headline = visit.phase(on: today).headline {
                Text(headline)
                    .font(PaeoniaTypography.display)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityIdentifier("visit.detail.countdown")
            }
            Text(visit.dateRangeText())
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
            if let place = visit.place {
                Label {
                    VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                        Text(place.name)
                            .font(PaeoniaTypography.bodyEmphasis)
                            .foregroundStyle(.paeoniaTextPrimary)
                        if let detail = place.cityAndCountry {
                            Text(detail)
                                .font(PaeoniaTypography.caption)
                                .foregroundStyle(.paeoniaTextSecondary)
                        }
                    }
                } icon: {
                    MemoryPlaceMapThumbnail(coordinate: place.coordinate, size: 40)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, PaeoniaSpacing.space8)
        .accessibilityElement(children: .combine)
    }

    private var noVisitHeader: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(.homeVisitPromptTitle)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button { editor = .new } label: {
                Text(.homeVisitPlanAction)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .accessibilityIdentifier("visit.detail.plan")
        }
        .padding(.vertical, PaeoniaSpacing.space8)
    }

    private var addRow: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            TextField(text: $newItemTitle, axis: .vertical) {
                Text(.visitListAddPlaceholder)
            }
            .lineLimit(1...3)
            .focused($isAddFieldFocused)
            .submitLabel(.done)
            .onChange(of: newItemTitle) { _, title in
                // The vertical field takes a return as a new line. It adds the item instead.
                if title.contains("\n") {
                    newItemTitle = title.replacingOccurrences(of: "\n", with: "")
                    addItem()
                } else if title.count > TogetherListItem.maxTitleLength {
                    newItemTitle = String(title.prefix(TogetherListItem.maxTitleLength))
                }
            }
            .accessibilityIdentifier("visit.list.add.field")

            Button(action: addItem) {
                Text(.visitListAddAction)
                    .font(PaeoniaTypography.bodyEmphasis)
            }
            .buttonStyle(.borderless)
            .disabled(newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("visit.list.add")
        }
    }

    private func addItem() {
        let title = newItemTitle
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        newItemTitle = ""
        Task { await visits.addItem(title) }
    }
}

/// One thing on the list, ticked by tapping the row.
private struct TogetherListRow: View {
    let item: TogetherListItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: PaeoniaSpacing.space12) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isDone ? .paeoniaAccentPrimary : .paeoniaTextTertiary)
                    .accessibilityHidden(true)
                Text(item.title)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(item.isDone ? .paeoniaTextSecondary : .paeoniaTextPrimary)
                    .strikethrough(item.isDone)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(item.isDone ? .visitListItemDone : .visitListItemNotDone))
        .accessibilityIdentifier("visit.list.item")
    }
}
