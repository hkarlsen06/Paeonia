import SwiftUI

struct PiccanteScreen: View {
    @Bindable var viewModel: PiccanteViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.threadChatContext) private var chatContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PaeoniaBannerCenter.self) private var banners
    @AccessibilityPresentation(.controls) private var showsControls
    @State private var tutorial = false
    @State private var boardControls = false
    @State private var sniffPicker = false
    @State private var sniffTile: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.space24) {
                if let game = viewModel.game {
                    players
                    Text(viewModel.status)
                        .font(PaeoniaTypography.sectionTitle)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("piccante.status")
                    if game.phase == .choosing {
                        chooseSize
                    } else {
                        box(game)
                            .frame(maxWidth: 560)
                        if let bite = game.bites.prefix(viewModel.shownBites).last,
                            !(game.phase == .finished && bite.tile == game.bites.last?.tile)
                        {
                            Text(PiccanteRules.flavor(gameID: game.id, number: game.gameNumber, tile: bite.tile))
                                .font(PaeoniaTypography.body).foregroundStyle(.paeoniaTextSecondary)
                        }
                        controls(game)
                    }
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
            .padding(PaeoniaSpacing.space24)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { tally }
            ToolbarItem(placement: .topBarTrailing) { GameMenu(history: nil, showTutorial: { tutorial = true }) }
        }
        .gameInviteToolbar(
            invite: viewModel.invite, partnerName: viewModel.partnerName, send: { await viewModel.sendInvite() },
            identifier: "piccante.invite"
        )
        .gameTutorial(GameTutorial(kind: .piccante, partnerName: viewModel.partnerName), isPresented: $tutorial)
        .gameLiveReactions(viewModel.reactions)
        .sheet(isPresented: $boardControls) { nativeControls }
        .sheet(isPresented: $sniffPicker) { privateSniffPicker }
        .task {
            viewModel.reduceMotion = reduceMotion
            await viewModel.start()
        }
        .onDisappear { viewModel.stop(markResultSeen: !chatContext.preservesGamePresentation(.piccante)) }
        .onChange(of: reduceMotion) { _, value in viewModel.reduceMotion = value }
        .onChange(of: scenePhase) { _, value in if value != .inactive { viewModel.scenePhaseChanged(value == .active) }
        }
        .onChange(of: viewModel.notice) { _, notice in
            if let notice {
                banners.show(notice.banner)
                viewModel.notice = nil
            }
        }
    }
    private var players: some View {
        let players = viewModel.participants.players
        return GameLiveRow {
            HStack(spacing: PaeoniaSpacing.space8) {
                GameAvatar(player: players.0, isMe: true, size: 44).accessibilityHidden(true)
                Text(verbatim: viewModel.participants.currentName)
                    .font(PaeoniaTypography.body.weight(.semibold))
                    .foregroundStyle(.paeoniaPartnerOne)
            }
        } trailing: {
            HStack(spacing: PaeoniaSpacing.space8) {
                GameAvatar(player: players.1, isMe: false, size: 44)
                    .gamePresenceRing(viewModel.partnerHere).accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text(verbatim: viewModel.partnerName).font(PaeoniaTypography.body.weight(.semibold))
                    Text(viewModel.partnerHere ? .piccantePartnerHere : .piccantePartnerAway)
                        .font(PaeoniaTypography.caption)
                }
                .foregroundStyle(Color.paeoniaInkLavender)
            }
        }
    }
    @ViewBuilder private var tally: some View {
        if let game = viewModel.game {
            if viewModel.playStyle == .against {
                Text(.piccanteTally(game.myWins, game.partnerWins))
                    .font(PaeoniaTypography.caption).foregroundStyle(.paeoniaTextPrimary)
            } else {
                Text(.piccanteGamesTogether(game.gamesFinished))
                    .font(PaeoniaTypography.caption).foregroundStyle(.paeoniaTextPrimary)
            }
        }
    }
    private var chooseSize: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            Image(.gameHubPiccanteBox).resizable().accessibilityHidden(true)
                .scaledToFit().frame(maxHeight: 220)
            if viewModel.canAct {
                ForEach([3, 4, 5], id: \.self) { size in
                    Button {
                        Task { await viewModel.act(.choose, size: size) }
                    } label: {
                        Text(.piccanteBoxSize(size, size))
                    }
                    .buttonStyle(PaeoniaSecondaryButtonStyle())
                    .accessibilityIdentifier("piccante.size.\(size)")
                }
            }
        }
    }
    private func box(_ game: RemotePiccanteGame) -> PiccanteBox {
        PiccanteBox(
            game: game, shownBites: viewModel.shownBites, revealsChilis: viewModel.revealSettled,
            selected: viewModel.selected, partnerSelected: viewModel.partnerSelected, pendingTile: viewModel.heldTile,
            style: { viewModel.style(for: $0) }, select: { viewModel.select($0) }, canSelect: viewModel.canAct)
    }
    @ViewBuilder private func controls(_ game: RemotePiccanteGame) -> some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            if game.phase == .hiding && viewModel.isMyTurn { hidingControls }
            if game.phase == .biting { bitingControls(game) }
            if game.phase == .finished && viewModel.revealSettled { resultControls(game) }
            if showsControls {
                Button {
                    boardControls = true
                } label: {
                    Text(.piccanteBoardControls)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
            }
            if viewModel.isSendFailing {
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
            Text(.piccanteHideHint).foregroundStyle(.paeoniaTextSecondary)
            TextField(String(localized: .piccanteNotePlaceholder), text: $viewModel.note)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("piccante.note")
            HStack {
                Text(.piccanteNoteHint).font(PaeoniaTypography.caption)
                Spacer()
                Text(verbatim: "\(viewModel.note.unicodeScalars.count)/60").font(PaeoniaTypography.caption)
            }.foregroundStyle(.paeoniaTextSecondary)
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
    @ViewBuilder private func bitingControls(_ game: RemotePiccanteGame) -> some View {
        if viewModel.isMyTurn && viewModel.heldTile == nil {
            Text(.piccanteBiteHint).foregroundStyle(.paeoniaTextSecondary)
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
                    sniffTile = nil
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
            Text(sniffLabel(sniff, size: game.size ?? 3))
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
    private var privateSniffPicker: some View {
        NavigationStack {
            List {
                if let game = viewModel.game, let userID = viewModel.userID {
                    Text(.piccanteSniffPrivate)
                    ForEach(0..<((game.size ?? 3) * (game.size ?? 3)), id: \.self) { tile in
                        if PiccanteRules.canSniff(tile, in: game, userID: userID) {
                            Button {
                                sniffTile = tile
                            } label: {
                                HStack {
                                    Text(
                                        .piccanteTilePosition(tile / (game.size ?? 3) + 1, tile % (game.size ?? 3) + 1))
                                    Spacer()
                                    if sniffTile == tile { Image(systemName: "checkmark").accessibilityHidden(true) }
                                }
                            }
                            .accessibilityAddTraits(sniffTile == tile ? .isSelected : [])
                            .accessibilityIdentifier("piccante.sniff.tile.\(tile)")
                        }
                    }

                }
            }
            .navigationTitle(Text(.piccanteSniffAction))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await viewModel.act(.sniff, tile: sniffTile)
                            sniffPicker = false
                        }
                    } label: {
                        Text(.piccanteSniffAction)
                    }
                    .disabled(sniffTile == nil || viewModel.isSaving)
                    .accessibilityIdentifier("piccante.sniff.confirm")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        sniffPicker = false
                    } label: {
                        Text(.commonCancel)
                    }
                }
            }
        }
    }
    private var nativeControls: some View {
        NavigationStack {
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
                    if game.phase == .biting {
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
                            sniffTile = nil
                            sniffPicker = true
                        } label: {
                            Text(.piccanteSniffAction)
                        }
                        .disabled(game.mySniff != nil || !viewModel.canAct)
                    }
                }
            }
            .navigationTitle(Text(.piccanteBoardControls))
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

struct PiccanteResultNotes: View {
    let game: RemotePiccanteGame
    let userID: UUID?
    let partnerName: String
    var body: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            if Set(game.chilis.map(\.tile)).count == 1 {
                Text(.piccanteSameOne).font(PaeoniaTypography.title).foregroundStyle(Color.paeoniaInkGold)
            }
            ForEach(orderedChilis.indices, id: \.self) { index in
                let chili = orderedChilis[index]
                if let note = chili.note {
                    VStack(spacing: PaeoniaSpacing.space8) {
                        Text(chili.userID == game.winnerUserID ? .piccanteWinnersNote : .piccanteWouldHaveGot)
                            .font(PaeoniaTypography.caption).foregroundStyle(.paeoniaTextSecondary)
                        Text(verbatim: note).font(PaeoniaTypography.sectionTitle).foregroundStyle(.paeoniaTextPrimary)
                    }
                    .padding(PaeoniaSpacing.space16)
                    .frame(maxWidth: .infinity)
                    .background(.paeoniaSurfaceSecondary, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius16))
                }
            }
        }
    }
    private var orderedChilis: [PiccanteChili] {
        game.chilis.sorted { $0.userID == game.winnerUserID && $1.userID != game.winnerUserID }
    }
}
