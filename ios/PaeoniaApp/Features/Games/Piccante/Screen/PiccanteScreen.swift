import SwiftUI

struct PiccanteScreen: View {
    @Bindable var viewModel: PiccanteViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.threadChatContext) private var chatContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(PaeoniaBannerCenter.self) private var banners
    @AccessibilityPresentation(.controls) private var showsControls
    @State private var tutorial = false
    @State private var boardControls = false
    @State private var sniffPicker = false
    @State private var nativeSniffPicker = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content(minimumHeight: viewModel.game?.phase == .choosing ? proxy.size.height : 0)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
            .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                if let score = viewModel.visibleScore, !dynamicTypeSize.isAccessibilitySize {
                    ToolbarItem(placement: .topBarTrailing) { scoreControl(score) }
                        .sharedBackgroundVisibility(.hidden)
                }
                ToolbarItem(placement: .topBarTrailing) { GameMenu(history: nil, showTutorial: { tutorial = true }) }
            }
            .gameMenuInvite(
                invite: viewModel.invite, partnerName: viewModel.partnerName, send: { await viewModel.sendInvite() },
                identifier: "piccante.invite"
            )
            .gameMenuInviteHost()
            .gameTutorial(GameTutorial(kind: .piccante, partnerName: viewModel.partnerName), isPresented: $tutorial)
            .gameLiveReactions(viewModel.reactions)
            .sheet(isPresented: $boardControls) { nativeControls }
            .sheet(isPresented: $sniffPicker) { PiccanteSniffPicker(viewModel: viewModel) }
            .task {
                viewModel.reduceMotion = reduceMotion
                await viewModel.start()
            }
            .onDisappear { viewModel.stop(markResultSeen: !chatContext.preservesGamePresentation(.piccante)) }
            .onChange(of: reduceMotion) { _, value in viewModel.reduceMotion = value }
            .onChange(of: scenePhase) { _, value in
                if value != .inactive { viewModel.scenePhaseChanged(value == .active) }
            }
            .onChange(of: viewModel.notice) { _, notice in
                if let notice {
                    banners.show(notice.banner)
                    viewModel.notice = nil
                }
            }
    }
}

extension PiccanteScreen {
    fileprivate func content(minimumHeight: CGFloat) -> some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            if let game = viewModel.game {
                gameContent(game)
            } else if let failure = viewModel.failure {
                PaeoniaLoadFailureView(
                    failure: failure, offlineMessage: .piccanteOffline, failedMessage: .piccanteFailed
                ) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Text(.commonTryAgain)
                    }
                    .buttonStyle(PaeoniaSecondaryButtonStyle())
                }
            } else {
                ProgressView().tint(.paeoniaAccentPrimary)
            }
        }
        .frame(minHeight: max(0, minimumHeight - PaeoniaSpacing.screenHorizontalPadding * 2))
        // The inner animation wins when both change, so the game arriving is a plain crossfade.
        .animation(PaeoniaMotion.stateChange, value: loadStage)
        .animation(reduceMotion ? PaeoniaMotion.buttonPress : PaeoniaMotion.meaningfulMoment, value: phaseIdentity)
        .padding(PaeoniaSpacing.screenHorizontalPadding)
        .paeoniaReadableWidth()
    }

    @ViewBuilder fileprivate func gameContent(_ game: RemotePiccanteGame) -> some View {
        if let score = viewModel.visibleScore, dynamicTypeSize.isAccessibilitySize {
            scoreControl(score).frame(maxWidth: .infinity, alignment: .leading)
        }
        players
        ZStack(alignment: .top) {
            phaseContent(game)
                .id(phaseIdentity)
                .transition(phaseTransition)
        }
    }

    @ViewBuilder private func phaseContent(_ game: RemotePiccanteGame) -> some View {
        if game.phase == .choosing {
            VStack(spacing: PaeoniaSpacing.space16) {
                status
                chooseSize
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxHeight: .infinity)
            // The sizes go while the choice saves. The box glides to the new center.
            .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: viewModel.canAct)
        } else {
            VStack(spacing: PaeoniaSpacing.space16) {
                status
                box(game)
                    .frame(maxWidth: 480)
                controls(game)
                    // A turn, a sniff or a failed send adds or removes a control. The rest glide to make room.
                    .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: game)
                    .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: viewModel.heldTile)
                    .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: viewModel.sendState.isFailing)
            }
        }
    }

    /// The spinner, the failure or the game. Moving between them is a crossfade.
    private var loadStage: String {
        viewModel.game != nil ? "game" : viewModel.failure != nil ? "failure" : "loading"
    }

    /// A new game, and the box once it is chosen, get the phase transition the other games use.
    private var phaseIdentity: String? {
        viewModel.game.map { "\($0.gameNumber)-\($0.phase == .choosing ? "choosing" : "box")" }
    }

    /// Cross-fade and a 12 point rise. Reduce Motion keeps only the cross-fade.
    private var phaseTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity)
    }

    private var status: some View {
        Text(viewModel.status)
            .font(PaeoniaTypography.sectionTitle)
            .foregroundStyle(.paeoniaTextPrimary)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("piccante.status")
    }

    @ViewBuilder fileprivate func scoreControl(_ score: BoardGameScore) -> some View {
        if chatContext.isAvailable, let open = chatContext.openGameChat {
            Button { open(.piccante, nil, nil) } label: {
                BoardGameScoreCapsule(score: score, me: viewModel.meInfo, partner: viewModel.partnerInfo)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(.gamesConversationOpen))
            .accessibilityIdentifier("piccante.history.open")
        } else {
            BoardGameScoreCapsule(score: score, me: viewModel.meInfo, partner: viewModel.partnerInfo)
        }
    }

    private var players: some View {
        GamePlayersRow(
            me: viewModel.meInfo, partner: viewModel.partnerInfo, turn: viewModel.turnLabel,
            partnerName: viewModel.partnerName, partnerIsHere: viewModel.partnerHere)
    }
    private var chooseSize: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            Image(.gameHubPiccanteBox).resizable().accessibilityHidden(true)
                .scaledToFit().frame(maxHeight: 220)
            if viewModel.canAct {
                PiccanteSizeChoices { size in
                    Task { await viewModel.act(.choose, size: size) }
                }
            }
        }
    }
    private func box(_ game: RemotePiccanteGame) -> PiccanteBox {
        PiccanteBox(
            game: game, shownBites: viewModel.shownBites, revealsChilis: viewModel.revealSettled,
            selected: viewModel.selected, partnerSelected: viewModel.partnerSelected, pendingTile: viewModel.heldTile,
            player: { $0 == viewModel.userID ? viewModel.meInfo : viewModel.partnerInfo },
            select: { viewModel.select($0) }, canSelect: viewModel.canAct,
            revealsBurn: viewModel.burnRevealed,
            burnShake: viewModel.burnShake, currentUserID: viewModel.userID)
    }
    @ViewBuilder private func controls(_ game: RemotePiccanteGame) -> some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            if game.phase == .hiding && viewModel.isMyTurn { hidingControls }
            if game.phase == .biting { bitingControls(game) }
            if game.phase == .finished && viewModel.noteRevealed {
                resultControls(game)
                    .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }
            if showsControls {
                Button {
                    boardControls = true
                } label: {
                    Text(.piccanteBoardControls)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .accessibilityIdentifier("piccante.controls.open")
            }
            if viewModel.sendState.isFailing {
                Text(.piccanteSendFailed).foregroundStyle(.paeoniaTextSecondary)
                Button {
                    Task { await viewModel.retry() }
                } label: {
                    Text(.commonTryAgain)
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
            }
        }
        .multilineTextAlignment(.center)
    }
    private var hidingControls: some View {
        Group {
            Text(.piccanteHideHint).font(PaeoniaTypography.body).foregroundStyle(.paeoniaTextSecondary)
            noteField
            if viewModel.note.unicodeScalars.count >= 50 {
                noteCount
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Button {
                Task { await viewModel.act(.hide) }
            } label: {
                Text(.piccanteHideAction)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(viewModel.selected == nil || !PiccanteRules.validNote(viewModel.note) || viewModel.isSaving)
            .accessibilityIdentifier("piccante.hide")
        }
    }
    private var noteField: some View {
        TextField(String(localized: .piccanteNotePlaceholder(viewModel.partnerName)), text: $viewModel.note)
            .textFieldStyle(.plain)
            .font(PaeoniaTypography.body)
            .foregroundStyle(PiccanteNoteColors.ink)
            .tint(PiccanteNoteColors.ink)
            .multilineTextAlignment(.leading)
            .padding(PaeoniaSpacing.space16)
            .background(PiccanteNoteColors.paper, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius12))
            .submitLabel(.done)
            .accessibilityIdentifier("piccante.note")
    }
    private var noteCount: some View {
        Text(verbatim: "\(viewModel.note.unicodeScalars.count)/60")
            .monospacedDigit()
    }
    @ViewBuilder private func bitingControls(_ game: RemotePiccanteGame) -> some View {
        if viewModel.isMyTurn && viewModel.heldTile == nil {
            if viewModel.showsBiteHint {
                Text(.piccanteBiteHint).foregroundStyle(.paeoniaTextSecondary)
            }
            Button {
                Task { await viewModel.act(.bite) }
            } label: {
                Text(.piccanteBiteAction)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(!viewModel.canAct || viewModel.selected == nil)
            .accessibilityIdentifier("piccante.bite")
            if game.mySniff == nil {
                Button {
                    sniffPicker = true
                } label: {
                    Label {
                        Text(.piccanteSniffAction)
                    } icon: {
                        Image(systemName: "wind")
                    }
                }
                .buttonStyle(PaeoniaSecondaryButtonStyle())
                .disabled(!viewModel.canAct)
                .accessibilityIdentifier("piccante.sniff")
            }
        }
        if let sniff = game.mySniff {
            Label {
                Text(sniffLabel(sniff, size: game.size ?? 3))
            } icon: {
                Image(systemName: sniff.hasChili ? "flame" : "checkmark.shield")
            }
            .font(PaeoniaTypography.body).foregroundStyle(.paeoniaTextPrimary)
            .accessibilityIdentifier("piccante.sniff.answer")
        }
        if game.partnerSniffUsed {
            Text(.piccantePartnerSniffed(viewModel.partnerName)).font(PaeoniaTypography.caption).foregroundStyle(
                .paeoniaTextSecondary)
        }
        GameLiveReactionButtons(isAvailable: viewModel.partnerHere, identifierPrefix: "piccante", send: viewModel.react)
    }
    private func sniffLabel(_ sniff: PiccanteSniff, size: Int) -> LocalizedStringResource {
        let row = sniff.tile / size + 1
        let column = sniff.tile % size + 1
        if sniff.hasChili { return .piccanteSniffHot(row, column) }
        return .piccanteSniffSafe(row, column)
    }
    @ViewBuilder private func resultControls(_ game: RemotePiccanteGame) -> some View {
        PiccanteResultNotes(game: game, userID: viewModel.userID, partnerName: viewModel.partnerName)
        if viewModel.state?.game?.gameNumber != game.gameNumber {
            Button {
                Task { await viewModel.continueResult() }
            } label: {
                Text(.piccanteContinue)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
        } else {
            Button {
                Task { await viewModel.act(.rematch) }
            } label: {
                Text(.piccantePlayAgain)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .disabled(viewModel.isSaving)
            .accessibilityIdentifier("piccante.rematch")
        }
    }
}

extension PiccanteScreen {
    private var nativeControlList: some View {
        List {
            if let game = viewModel.game {
                ForEach(0..<((game.size ?? 3) * (game.size ?? 3)), id: \.self) { tile in
                    Button {
                        viewModel.select(tile)
                    } label: {
                        Text(verbatim: box(game).label(tile))
                    }
                    .disabled(!viewModel.canAct || game.bites.contains { $0.tile == tile })
                }
                if game.phase == .hiding && viewModel.isMyTurn { hidingControls }
                if game.phase == .biting { nativeBiteButtons(game) }
            }
        }
    }
    @ViewBuilder private func nativeBiteButtons(_ game: RemotePiccanteGame) -> some View {

        Button {
            Task {
                await viewModel.act(.bite)
                boardControls = false
            }
        } label: {
            Text(.piccanteBiteAction)
        }
        .disabled(viewModel.selected == nil || !viewModel.canAct)
        Button {
            nativeSniffPicker = true
        } label: {
            Text(.piccanteSniffAction)
        }
        .disabled(game.mySniff != nil || !viewModel.canAct)
        .accessibilityIdentifier("piccante.controls.sniff")

    }
    private var nativeControls: some View {
        NavigationStack {
            nativeControlList
                .paeoniaGroupedList()
                .navigationTitle(Text(.piccanteBoardControls))
                .sheet(isPresented: $nativeSniffPicker) { PiccanteSniffPicker(viewModel: viewModel) }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            boardControls = false
                        } label: {
                            Text(.commonDone)
                        }
                    }
                }
        }
    }
}
