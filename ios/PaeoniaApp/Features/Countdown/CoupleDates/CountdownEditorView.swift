import SwiftUI

/// Sheet for adding or editing a countdown: a title and the day it counts down to.
/// Owns its whole presentation like `RelationshipDateEditorView`, so callers only need
/// `.sheet { CountdownEditorView(...) }`.
struct CountdownEditorView: View {
    /// Nil while adding a new countdown.
    let countdown: CustomCountdown?
    let onSave: (String, Date) async -> Bool
    let onDelete: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var day: Date
    @State private var isConfirmingDelete = false
    @State private var isWorking = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
    }

    init(
        countdown: CustomCountdown?,
        onSave: @escaping (String, Date) async -> Bool,
        onDelete: @escaping () async -> Bool = { false }
    ) {
        self.countdown = countdown
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: countdown?.title ?? "")
        let existingDay = countdown.flatMap { try? PairingStartDate(rawValue: $0.targetDate) }?.date()
        _day = State(initialValue: existingDay ?? Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                editorContent
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.paeoniaSurfacePrimary)
            .navigationTitle(
                Text(countdown == nil ? .homeMilestoneCountdownNewTitle : .homeMilestoneCountdownEditTitle)
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .presentationDetents([.large])
        .presentationBackground(.paeoniaSurfacePrimary)
        .interactiveDismissDisabled(isWorking)
        .onAppear {
            if countdown == nil { focusedField = .title }
        }
        .alert(Text(.homeMilestoneCountdownDeleteConfirmTitle), isPresented: $isConfirmingDelete) {
            Button(role: .destructive, action: delete) {
                Text(.homeMilestoneCountdownDeleteAction)
            }
            Button(role: .cancel) {} label: {
                Text(.homeMilestoneEditorCancelAction)
            }
        } message: {
            Text(.homeMilestoneCountdownDeleteConfirmMessage)
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
            Text(.homeMilestoneCountdownEditorMessage)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            MemoryTextField(
                text: $title,
                placeholder: .homeMilestoneCountdownTitlePlaceholder,
                isFocused: $focusedField,
                field: .title,
                lineLimit: 1...2,
                characterLimit: CustomCountdown.maxTitleLength
            )

            DatePicker(selection: $day, in: earliestDay..., displayedComponents: .date) {
                Text(.homeMilestoneCountdownDateLabel)
            }
            .datePickerStyle(.graphical)
            .tint(.paeoniaAccentPrimary)

            if countdown != nil {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Text(.homeMilestoneCountdownDeleteAction)
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

    /// Today for a new countdown. A countdown whose day has passed keeps its own day
    /// reachable, so editing the title doesn't force a new date.
    private var earliestDay: Date {
        let today = Calendar.current.startOfDay(for: Date())
        guard let countdown, let existing = (try? PairingStartDate(rawValue: countdown.targetDate))?.date() else {
            return today
        }
        return min(existing, today)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isWorking
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
            .disabled(!canSave)
        }
    }

    private func save() {
        isWorking = true
        Task {
            if await onSave(title, day) {
                dismiss()
            }
            isWorking = false
        }
    }

    private func delete() {
        isWorking = true
        Task {
            if await onDelete() {
                dismiss()
            }
            isWorking = false
        }
    }
}
