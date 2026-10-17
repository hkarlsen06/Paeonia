import SwiftUI

/// When the couple got together. The person who joined sees the date their partner
/// set and confirms it or changes it. Someone without a date picks one or skips.
/// A confirmed or saved date then counts up the days together.
struct PostPairingDateStep: View {
    private enum Phase: Equatable {
        case confirm(String)
        case ask
        case reveal(String)
    }

    let partnerName: String
    let ownerUserID: UUID
    let onFinish: () -> Void

    @State private var phase: Phase
    @State private var milestone: RelationshipMilestoneViewModel
    @State private var pickedDate = Date()
    @State private var isEditorPresented = false
    @State private var editorDate = Date()
    @State private var isRevealDone = false
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 52
    private let serverStartedOn: String?
    private let syncAfterLocalChange: @MainActor () async -> Void

    /// `startedOn` is the couple's date as `yyyy-MM-dd`. `confirmsPartnerDate` is
    /// true for the person who joined, when the partner already set it.
    init(
        startedOn: String?,
        confirmsPartnerDate: Bool,
        partnerName: String,
        ownerUserID: UUID,
        milestone: RelationshipMilestoneViewModel,
        syncAfterLocalChange: @escaping @MainActor () async -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.partnerName = partnerName
        self.ownerUserID = ownerUserID
        self.onFinish = onFinish
        self.serverStartedOn = startedOn
        self.syncAfterLocalChange = syncAfterLocalChange
        _milestone = State(initialValue: milestone)
        if let startedOn, confirmsPartnerDate {
            _phase = State(initialValue: .confirm(startedOn))
        } else {
            _phase = State(initialValue: .ask)
        }
    }

    var body: some View {
        content
            .id(phaseID)
            .transition(.opacity)
            .animation(PaeoniaMotion.meaningfulMoment, value: phaseID)
            .task {
                milestone.setSyncAfterLocalChange { await syncAfterLocalChange() }
                await milestone.configure(ownerUserID: ownerUserID, serverStartedOn: serverStartedOn)
            }
            .onChange(of: milestone.error) { _, error in
                guard let error else {
                    return
                }
                bannerCenter.show(.error(message: error.message))
                milestone.clearError()
            }
            .sheet(isPresented: $isEditorPresented) {
                RelationshipDateEditorView(
                    selectedDate: $editorDate,
                    isEditing: true,
                    isSaving: milestone.isSaving,
                    onSave: save
                )
            }
    }

    private var phaseID: Int {
        switch phase {
        case .confirm: 0
        case .ask: 1
        case .reveal: 2
        }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case let .confirm(startedOn):
            confirm(startedOn)
        case .ask:
            ask
        case let .reveal(startedOn):
            reveal(startedOn)
        }
    }

    // MARK: Phases

    private func confirm(_ startedOn: String) -> some View {
        OnboardingStepScaffold(
            title: .onboardingFirstDayDateConfirmTitle(partnerName, Self.dateText(startedOn)),
            message: .onboardingFirstDayDateConfirmMessage,
            placement: .standalone,
            primary: OnboardingStepAction(title: .onboardingFirstDayDateConfirmButton) {
                PaeoniaHaptics.selection()
                phase = .reveal(startedOn)
            },
            secondary: OnboardingStepAction(title: .onboardingFirstDayDateChangeButton) {
                editorDate = Self.date(startedOn) ?? Date()
                isEditorPresented = true
            }
        ) {
            calendarArt
        } content: {
            EmptyView()
        }
    }

    private var ask: some View {
        OnboardingStepScaffold(
            title: .onboardingFirstDayDateAskTitle,
            message: .onboardingFirstDayDateAskMessage,
            placement: .standalone,
            primary: OnboardingStepAction(
                title: .onboardingFirstDayDateSaveButton,
                isLoading: milestone.isSaving
            ) {
                Task { await save(pickedDate) }
            },
            secondary: OnboardingStepAction(
                title: .onboardingFirstDayDateSkipButton,
                isEnabled: !milestone.isSaving,
                action: onFinish
            )
        ) {
            // The question first, then the calendar under it.
            DatePicker(selection: $pickedDate, in: ...Date(), displayedComponents: .date) {
                Text(.homeMilestoneEditorDateLabel)
            }
            .datePickerStyle(.graphical)
            .tint(.paeoniaAccentPrimary)
            .disabled(milestone.isSaving)
        }
    }

    private func reveal(_ startedOn: String) -> some View {
        OnboardingStepScaffold(
            title: .onboardingFirstDayDateRevealTitle(partnerName),
            placement: .standalone,
            primary: isRevealDone
                ? OnboardingStepAction(title: .onboardingFirstDayContinueButton) {
                    PaeoniaHaptics.celebrationContinued()
                    onFinish()
                }
                : nil
        ) {
            RelationshipDaysReveal(startedOn: startedOn) {
                isRevealDone = true
            }
            // Room above for the heart burst, so it clears the title.
            .padding(.top, PaeoniaSpacing.space40)
            .padding(.bottom, PaeoniaSpacing.space24)
        }
    }

    private var calendarArt: some View {
        Image(systemName: "calendar.badge.checkmark")
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(.paeoniaAccentPrimary)
            .symbolRenderingMode(.hierarchical)
            .accessibilityHidden(true)
    }

    // MARK: Actions

    /// Saves the date and counts up from it. Returns whether it saved, for the editor.
    private func save(_ date: Date) async -> Bool {
        guard await milestone.save(startedOn: date), let startedOn = milestone.startedOn else {
            return false
        }
        phase = .reveal(startedOn)
        return true
    }

    // MARK: Dates

    private static func date(_ startedOn: String) -> Date? {
        (try? PairingStartDate(rawValue: startedOn))?.date()
    }

    /// "3 March 2024" in the phone's own format, with no-break spaces so the title
    /// never wraps in the middle of the date.
    private static func dateText(_ startedOn: String) -> String {
        let text = date(startedOn)?.formatted(.dateTime.day().month(.wide).year()) ?? startedOn
        return text.replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}

#if DEBUG
private struct PostPairingDateStepPreview: View {
    let startedOn: String?

    @State private var bannerCenter = PaeoniaBannerCenter()

    var body: some View {
        PostPairingDateStep(
            startedOn: startedOn,
            confirmsPartnerDate: true,
            partnerName: "Hjalmar",
            ownerUserID: UUID(),
            milestone: RelationshipMilestoneViewModel(
                dataService: RelationshipStartedOnDataService(
                    accessSnapshotStore: InMemoryAccessSyncSnapshotRepository(),
                    pendingOperationStore: InMemoryPendingSyncOperationRepository()
                )
            ),
            syncAfterLocalChange: {},
            onFinish: {}
        )
        .environment(bannerCenter)
        .paeoniaTopBanner(bannerCenter)
        .preferredColorScheme(.dark)
    }
}

#Preview("Confirm the partner's date") {
    PostPairingDateStepPreview(startedOn: "2024-03-03")
}

#Preview("No date yet") {
    PostPairingDateStepPreview(startedOn: nil)
}
#endif
