import SwiftUI

/// Sheet for planning or editing a visit: the first and last day and an optional place. A
/// visit in the past is fine. A last day before the first can't be saved, and the sheet says why.
/// Owns its whole presentation, so callers only need `.sheet { VisitEditorView(...) }`.
struct VisitEditorView: View {
    /// Nil while planning a new visit.
    let visit: Visit?
    let visits: VisitsViewModel

    @Environment(\.dismiss) private var dismiss
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

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            DatePicker(selection: $start, displayedComponents: .date) {
                Text(.visitEditorStart)
            }
            .accessibilityIdentifier("visit.editor.start")
            .onChange(of: start, moveEndWithStart)

            DatePicker(selection: $end, displayedComponents: .date) {
                Text(.visitEditorEnd)
            }
            .accessibilityIdentifier("visit.editor.end")

            if !isRangeValid {
                Label {
                    Text(.visitEditorRangeError)
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .foregroundStyle(.paeoniaTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("visit.editor.rangeError")
            }
        }
        .font(PaeoniaTypography.body)
        .tint(.paeoniaAccentPrimary)
    }

    /// Moving the first day moves the last day with it, so the visit keeps its length.
    private func moveEndWithStart(from old: Date, to new: Date) {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: old), to: calendar.startOfDay(for: new)
        ).day ?? 0
        end = calendar.date(byAdding: .day, value: days, to: end) ?? end
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
            .disabled(!isRangeValid || isWorking)
            .accessibilityIdentifier("visit.editor.save")
        }
    }

    private func save() {
        isWorking = true
        Task {
            if await visits.saveVisit(id: visit?.id, from: start, to: end, place: place) {
                dismiss()
            }
            isWorking = false
        }
    }

    private func delete() {
        guard let visit else { return }
        isWorking = true
        Task {
            if await visits.deleteVisit(id: visit.id) {
                dismiss()
            }
            isWorking = false
        }
    }
}
