import SwiftUI

/// Sheet for planning or editing a visit: the first and last day and an optional place. A
/// visit in the past is fine. A last day before the first can't be saved, and the sheet says why.
/// Owns its whole presentation, so callers only need `.sheet { VisitEditorView(...) }`.
struct VisitEditorView: View {
    /// Nil while planning a new visit.
    let visit: Visit?
    let visits: VisitsViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @State private var start: Date
    @State private var end: Date
    @State private var place: MemoryPlace?
    @State private var isConfirmingDelete = false
    @State private var isWorking = false

    init(visit: Visit?, visits: VisitsViewModel) {
        self.visit = visit
        self.visits = visits
        let calendar = Calendar.current
        let defaultStart = calendar.date(byAdding: .day, value: 14, to: calendar.startOfDay(for: Date())) ?? Date()
        let start = visit?.startDay() ?? defaultStart
        _start = State(initialValue: start)
        _end = State(initialValue: visit?.endDay() ?? calendar.date(byAdding: .day, value: 3, to: start) ?? start)
        _place = State(initialValue: visit?.place)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                editorContent
            }
            .background(.paeoniaSurfacePrimary)
            .navigationTitle(Text(visit == nil ? .homeVisitPlanAction : .visitEditorEditTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .paeoniaBanner(bannerCenter)
        .presentationDetents([.large])
        .presentationBackground(.paeoniaSurfacePrimary)
        .interactiveDismissDisabled(isWorking)
        .alert(Text(.visitEditorDeleteConfirmTitle), isPresented: $isConfirmingDelete) {
            Button(role: .destructive, action: delete) {
                Text(.visitEditorDelete)
            }
            Button(role: .cancel) {} label: {
                Text(.homeMilestoneEditorCancelAction)
            }
        } message: {
            Text(.visitEditorDeleteConfirmMessage)
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
            Text(.visitEditorMessage)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            datesSection

            MemoryPlaceField(place: $place, photos: [], knownPlaces: knownPlaces)

            if visit != nil {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Text(.visitEditorDelete)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space16)
        .padding(.bottom, PaeoniaSpacing.space40)
    }

    /// The days the server accepts. The last day may still be before the first, which the
    /// editor explains, but not further after it than the longest visit.
    private var startRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let earliest = Visit.earliestDay.startOfDay(in: calendar) ?? .distantPast
        return earliest...(Visit.latestDay.startOfDay(in: calendar) ?? .distantFuture)
    }

    private var endRange: ClosedRange<Date> {
        let longest = Calendar.current.date(byAdding: .day, value: Visit.maxDays - 1, to: start) ?? start
        return startRange.lowerBound...max(startRange.lowerBound, min(longest, startRange.upperBound))
    }

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            DatePicker(selection: $start, in: startRange, displayedComponents: .date) {
                Text(.visitEditorStart)
            }
            .accessibilityIdentifier("visit.editor.start")
            .onChange(of: start) { old, new in
                end = Visit.end(end, afterStartMovedFrom: old, to: new)
            }

            DatePicker(selection: $end, in: endRange, displayedComponents: .date) {
                Text(.visitEditorEnd)
            }
            .accessibilityIdentifier("visit.editor.end")

            if isDeleted {
                notice(.visitEditorDeleted)
            } else if !isRangeValid {
                notice(.visitEditorRangeError)
                    .accessibilityIdentifier("visit.editor.rangeError")
            }
        }
        .font(PaeoniaTypography.body)
        .tint(.paeoniaAccentPrimary)
    }

    private func notice(_ text: LocalizedStringResource) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "exclamationmark.circle")
        }
        .foregroundStyle(.paeoniaTextPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The places of the couple's other visits, for "Places you've used".
    private var knownPlaces: [MemoryPlace] {
        visits.state.visits.compactMap(\.place)
    }

    private var isRangeValid: Bool {
        Calendar.current.startOfDay(for: end) >= Calendar.current.startOfDay(for: start)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: { dismiss() }) {
                Text(.homeMilestoneEditorCancelAction)
            }
            .disabled(isWorking)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button(action: save) {
                Text(.homeMilestoneEditorSaveAction)
            }
            .disabled(!isRangeValid || isWorking || isDeleted)
            .accessibilityIdentifier("visit.editor.save")
        }
    }

    /// The visit being edited is gone, deleted by the partner while this sheet was open.
    /// Once this phone saves or deletes, `isWorking` stays on until the sheet closes.
    private var isDeleted: Bool {
        guard let visit, !isWorking else { return false }
        return !visits.state.visits.contains { $0.id == visit.id }
    }

    private func save() {
        isWorking = true
        Task {
            if await visits.saveVisit(id: visit?.id, from: start, to: end, place: place) {
                dismiss()
            } else {
                isWorking = false
            }
        }
    }

    private func delete() {
        guard let visit else { return }
        isWorking = true
        Task {
            if await visits.deleteVisit(id: visit.id) {
                dismiss()
            } else {
                isWorking = false
            }
        }
    }
}
