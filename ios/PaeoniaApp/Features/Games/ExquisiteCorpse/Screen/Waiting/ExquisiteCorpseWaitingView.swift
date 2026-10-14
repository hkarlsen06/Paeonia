import SwiftUI

/// Waiting for the partner. It says whose turn it is and makes the wait feel
/// shared. Three looks, picked by the phase:
/// - `.waiting`: the partner draws out of sight, or is not here.
/// - `.watching`: the partner draws now, and this person sees the folded paper
///   (`ExquisiteCorpseWatchView`).
/// - `.waitingToSync`: this person's legs are queued, and the reveal opens once
///   the server has them.
struct ExquisiteCorpseWaitingView: View {
    let viewModel: ExquisiteCorpseViewModel
    /// Matches the strip of the watched square to the next canvas. Nil with Reduce Motion.
    let handoff: Namespace.ID?

    var body: some View {
        switch viewModel.phase {
        case .watching:
            ExquisiteCorpseWatchView(viewModel: viewModel, handoff: handoff)
        case .waitingToSync:
            ExquisiteCorpseSyncingView(viewModel: viewModel)
        default:
            ExquisiteCorpseAwayView(viewModel: viewModel)
        }
    }
}

/// The partner's turn, and they are not drawing in the room.
struct ExquisiteCorpseAwayView: View {
    let viewModel: ExquisiteCorpseViewModel
    /// Fixed when the screen opens. The screen fades out when the turn comes
    /// around, and must not change its words on the way.
    private let part: ExquisiteCorpsePartKind?
    private let figureNumber: Int

    init(viewModel: ExquisiteCorpseViewModel) {
        self.viewModel = viewModel
        part = viewModel.part
        figureNumber = viewModel.figureNumber
    }

    var body: some View {
        GameFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space24) {
                Spacer(minLength: PaeoniaSpacing.space16)
                VStack(spacing: PaeoniaSpacing.space16) {
                    ExquisiteCorpsePartnerAvatar(
                        player: viewModel.partner,
                        isPartnerHere: viewModel.partnerPresence.isHere
                    )
                    VStack(spacing: PaeoniaSpacing.space8) {
                        Text(title)
                            .font(PaeoniaTypography.title)
                            .foregroundStyle(.paeoniaTextPrimary)
                        Text(.exquisiteCorpseWaitHint)
                            .font(PaeoniaTypography.body)
                            .foregroundStyle(.paeoniaTextSecondary)
                        if showsLegsNextHint {
                            Text(.exquisiteCorpseWaitHintLegsNext)
                                .font(PaeoniaTypography.body)
                                .foregroundStyle(.paeoniaTextSecondary)
                        }
                    }
                    .multilineTextAlignment(.center)
                    ExquisiteCorpseMiniFold(partsDone: partsDone, openPart: openPart)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("corpse.waiting")
                ExquisiteCorpseSendStatus(viewModel: viewModel)
                    .multilineTextAlignment(.center)
                Spacer(minLength: PaeoniaSpacing.space16)
            }
            .frame(maxWidth: .infinity)
        } bottom: {
            ExquisiteCorpseInviteButton(viewModel: viewModel)
        }
        // The partner's phone changes the title, ring and invite button while this
        // screen is open. Everything moves to its new place together.
        .animation(PaeoniaMotion.stateChange, value: viewModel.partnerPresence)
        .animation(PaeoniaMotion.stateChange, value: viewModel.invite)
        .animation(PaeoniaMotion.stateChange, value: viewModel.isHeldOnPhone)
        .animation(PaeoniaMotion.stateChange, value: viewModel.isSendFailing)
        .onChange(of: viewModel.partnerPresence) { old, new in
            guard !old.isHere, new.isHere else { return }
            AccessibilityNotification.Announcement(String(localized: title)).post()
        }
    }

    /// The partner starts a new creature, once the one before it is finished.
    private var startsNewCreature: Bool {
        part == nil || (part == .head && figureNumber > 1)
    }

    private var title: LocalizedStringResource {
        let name = viewModel.partnerName
        guard let part, !startsNewCreature else { return .exquisiteCorpseWaitNewCreature(name) }
        if viewModel.partnerPresence == .drawing {
            switch part {
            case .head: return .exquisiteCorpseWaitDrawingNowHead(name)
            case .body: return .exquisiteCorpseWaitDrawingNowBody(name)
            case .legs: return .exquisiteCorpseWaitDrawingNowLegs(name)
            }
        }
        switch part {
        case .head: return .exquisiteCorpseWaitWaitingHead(name)
        case .body: return .exquisiteCorpseWaitWaitingBody(name)
        case .legs: return .exquisiteCorpseWaitWaitingLegs(name)
        }
    }

    /// In the first figure the head drawer is also told the legs are theirs.
    private var showsLegsNextHint: Bool {
        figureNumber == 1 && part == .body
    }

    private var partsDone: Int {
        startsNewCreature ? 0 : part?.rawValue ?? 0
    }

    private var openPart: ExquisiteCorpsePartKind? {
        startsNewCreature ? nil : part
    }
}

/// This person's legs are queued. The reveal opens once the server has them, and
/// until then this says where the legs are.
struct ExquisiteCorpseSyncingView: View {
    let viewModel: ExquisiteCorpseViewModel

    var body: some View {
        GameFocusedLayout(fillsHeight: true) {
            VStack(spacing: PaeoniaSpacing.space24) {
                Spacer(minLength: PaeoniaSpacing.space16)
                VStack(spacing: PaeoniaSpacing.space16) {
                    ExquisiteCorpseMiniFold(partsDone: ExquisiteCorpsePartKind.allCases.count, openPart: nil)
                    if viewModel.isSendFailing {
                        ExquisiteCorpseSendFailure(viewModel: viewModel)
                    } else if viewModel.isHeldOnPhone {
                        offlineLine
                    } else {
                        opening
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("corpse.syncing")
                Spacer(minLength: PaeoniaSpacing.space16)
            }
            .frame(maxWidth: .infinity)
        }
        .animation(PaeoniaMotion.stateChange, value: viewModel.isHeldOnPhone)
        .animation(PaeoniaMotion.stateChange, value: viewModel.isSendFailing)
    }

    private var offlineLine: some View {
        Label {
            Text(.exquisiteCorpseRevealOffline)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "clock")
                .accessibilityHidden(true)
        }
        .font(PaeoniaTypography.body)
        .foregroundStyle(.paeoniaSyncPending)
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("corpse.pending")
    }

    private var opening: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Text(.exquisiteCorpseWaitOpening)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
            ProgressView()
                .tint(.paeoniaAccentPrimary)
        }
    }
}
