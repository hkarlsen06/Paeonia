import SwiftUI

/// The Us tab card after a visit. From the day after its last day, for two weeks, it names the
/// visit's dates and asks for photos from it (`VisitMemoryPrompt`). Before anyone made a memory
/// of the visit it opens the new-memory form with the visit's first day and place filled in.
/// After that it opens that memory's edit form, where the person adds their photos. The
/// person can hide it, which hides it on all their phones and not on the partner's.
struct HomeVisitMemoryCard: View {
    let visits: VisitsViewModel
    let memories: MemoriesViewModel
    let viewerID: UUID
    let partnerName: String
    /// True for the card among the Us tab's first cards, which shows only a prompt that waits for
    /// this person (`VisitMemoryPrompt.waitsForViewer`). False for the card under the tiles, which
    /// shows every other prompt.
    let waiting: Bool
    let onOpen: (VisitMemoryForm) -> Void

    private static let iconSize: CGFloat = 32

    /// Refreshed at midnight, so the card comes the day after a visit and goes after two weeks
    /// while the app stays open.
    @State private var now = Date()

    var body: some View {
        content
            .onCalendarDayChange { now = Date() }
    }

    /// The prompt at `now` on this phone's calendar, once both the visits and the memories are
    /// read, so the card never shows for a moment before the person's photos load.
    static func prompt(
        visits: VisitsViewModel,
        memories: MemoriesViewModel,
        viewerID: UUID,
        waiting: Bool,
        at now: Date
    ) -> VisitMemoryPrompt? {
        guard visits.hasLoaded, memories.hasLoadedOnce else { return nil }
        return VisitMemoryPrompt.current(
            visits: visits.state.visits,
            memories: memories.timeline.flatMap(\.memories).map(\.snapshot),
            viewerID: viewerID,
            today: LockScreenCalendarDate(containing: now, in: .current),
            waitingForViewer: waiting
        )
    }

    @ViewBuilder
    private var content: some View {
        if let prompt = Self.prompt(visits: visits, memories: memories, viewerID: viewerID, waiting: waiting, at: now) {
            PaeoniaCard(padding: PaeoniaSpacing.space12) {
                HStack(spacing: PaeoniaSpacing.space8) {
                    Button { open(prompt) } label: { label(for: prompt) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.visitMemory.card")
                    hideButton(visitID: prompt.visit.id)
                }
            }
            .transition(.opacity)
        }
    }

    private func label(for prompt: VisitMemoryPrompt) -> some View {
        let dates = prompt.visit.dateRangeText()
        let (headline, detail): (String, String) = switch prompt {
        case .startMemory:
            (
                String(localized: .homeVisitMemoryStartTitle),
                [dates, prompt.visit.place?.nameAndCity].compactMap(\.self).joined(separator: " · ")
            )
        case .addYourPhotos(_, _, partnerAddedPhotos: true):
            (
                String(localized: .homeVisitMemoryPartnerAddedTitle(partnerName)),
                String(localized: .homeVisitMemoryAddYoursDetail(dates))
            )
        case .addYourPhotos:
            (String(localized: .homeVisitMemoryAddYoursTitle), dates)
        }
        return HStack(spacing: PaeoniaSpacing.space12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaAccentPrimary)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .background(.paeoniaSurfaceSecondary, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
                Text(headline)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextTertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func hideButton(visitID: UUID) -> some View {
        Button {
            Task { await visits.dismissMemoryPrompt(visitID: visitID) }
        } label: {
            Image(systemName: "xmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.paeoniaTextSecondary)
                .frame(width: PaeoniaSpacing.compactButtonHeight, height: PaeoniaSpacing.compactButtonHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.homeVisitMemoryHide))
        .accessibilityIdentifier("home.visitMemory.hide")
    }

    private func open(_ prompt: VisitMemoryPrompt) {
        switch prompt {
        case let .startMemory(visit):
            startMemory(for: visit)
        case let .addYourPhotos(_, memoryID, _):
            if let record = memories.record(for: memoryID) { onOpen(.edit(record)) }
        }
    }

    /// Fills an empty new-memory draft with the visit's first day and place. A draft the person
    /// already started for something else stays as it is, so nothing they made is replaced.
    private func startMemory(for visit: Visit) {
        if memories.draft.isEmpty {
            memories.updateDraft(
                MemoryDraft(
                    date: MemoryTimeline.pickerDate(forLocalDate: visit.startDate) ?? Date(),
                    place: visit.place,
                    visitID: visit.id
                )
            )
        }
        onOpen(.new(visitID: visit.id))
    }
}

enum VisitMemoryForm: Identifiable {
    case new(visitID: UUID)
    case edit(MemoryRecord)

    var id: UUID {
        switch self {
        case let .new(visitID): visitID
        case let .edit(record): record.snapshot.memoryID
        }
    }
}

struct VisitMemoryFormSheet: ViewModifier {
    @Binding var form: VisitMemoryForm?
    let memories: MemoriesViewModel?
    let viewerID: UUID?

    func body(content: Content) -> some View {
        let isOpen = form != nil
        return content
            .sheet(item: $form, onDismiss: { memories?.flushDraft() }) { form in
                if let memories {
                    Group {
                        switch form {
                        case let .new(visitID):
                            NewMemoryEditor(viewModel: memories, visitID: visitID)
                        case let .edit(record):
                            ExistingMemoryEditor(record: record, currentUserID: viewerID, viewModel: memories)
                        }
                    }
                    .modifier(MemoryNoticeBanners(memories: memories))
                }
            }
            // `.preference` would replace the value the cards below report for `HomeIsCoveredKey`.
            .transformPreference(HomeIsCoveredKey.self) { $0 = $0 || isOpen }
    }
}

/// Shows the memories notices, such as a failed save, inside a sheet the Us tab opened, where
/// the Memories tab's banner can't be seen.
private struct MemoryNoticeBanners: ViewModifier {
    let memories: MemoriesViewModel
    @Environment(PaeoniaBannerCenter.self) private var bannerCenter

    func body(content: Content) -> some View {
        content.onChange(of: memories.notice) { _, notice in
            guard let notice else { return }
            bannerCenter.show(notice.banner)
            memories.dismissNotice()
        }
    }
}
