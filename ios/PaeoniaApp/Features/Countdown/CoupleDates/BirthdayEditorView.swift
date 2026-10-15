import SwiftUI

/// Sheet for setting either partner's birthday. A wheel picker, because a graphical
/// calendar would need twenty years of paging to reach the year someone was born.
struct BirthdayEditorView: View {
    /// "Your birthday" or "Oda's birthday".
    let title: String
    /// Whose birthday it is, for the explanation under the title.
    let isOwnBirthday: Bool
    let partnerName: String
    /// The stored birthday, or nil when none is set yet.
    let birthday: Date?
    let onSave: (Date?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var day: Date
    @State private var isWorking = false

    init(
        title: String,
        isOwnBirthday: Bool,
        partnerName: String,
        birthday: Date?,
        onSave: @escaping (Date?) async -> Bool
    ) {
        self.title = title
        self.isOwnBirthday = isOwnBirthday
        self.partnerName = partnerName
        self.birthday = birthday
        self.onSave = onSave
        _day = State(initialValue: birthday ?? Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date())
    }

    var body: some View {
        NavigationStack {
            editorContent
                .navigationTitle(Text(verbatim: title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.paeoniaSurfacePrimary)
        .interactiveDismissDisabled(isWorking)
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.sectionSpacing) {
            Text(isOwnBirthday
                ? .homeMilestoneBirthdayEditorOwnMessage(partnerName)
                : .homeMilestoneBirthdayEditorPartnerMessage(partnerName))
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            DatePicker(selection: $day, in: ...Date(), displayedComponents: .date) {
                Text(verbatim: title)
            }
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            if birthday != nil {
                Button(role: .destructive) {
                    save(nil)
                } label: {
                    Text(.homeMilestoneBirthdayRemoveAction)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space16)
        .background(.paeoniaSurfacePrimary)
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
            Button(action: { save(day) }) {
                Text(.homeMilestoneEditorSaveAction)
            }
            .disabled(isWorking)
        }
    }

    private func save(_ day: Date?) {
        isWorking = true
        Task {
            if await onSave(day) {
                dismiss()
            }
            isWorking = false
        }
    }
}
