import SwiftUI

extension View {
    /// Shows the game's "How to play" cards the first time this phone opens the
    /// game, and again whenever `isPresented` turns on. Does nothing for a game
    /// without cards.
    func gameTutorial(_ tutorial: GameTutorial?, isPresented: Binding<Bool>) -> some View {
        task {
            guard let tutorial, !tutorial.hasBeenShown else { return }
            // A sheet asked for while the game screen is still being pushed can
            // be dropped, so wait for the push to finish.
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            tutorial.hasBeenShown = true
            isPresented.wrappedValue = true
        }
        .sheet(isPresented: isPresented) {
            if let tutorial {
                GameTutorialSheet(tutorial: tutorial)
            }
        }
    }
}

/// The toolbar button that opens a game's "How to play" cards.
struct GameTutorialButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(.gamesTutorialOpen)
            } icon: {
                Image(systemName: "questionmark.circle")
            }
        }
        .accessibilityIdentifier("games.tutorial.open")
    }
}

/// Swipeable cards, each with one picture and a short explanation. The button
/// under them goes to the next card, and on the last card closes the sheet.
struct GameTutorialSheet: View {
    let tutorial: GameTutorial

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = 0
    @State private var pageHeight: CGFloat = 0
    @State private var sheetHeight: CGFloat = 0

    private var isLastPage: Bool { selection == tutorial.pages.count - 1 }

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            TabView(selection: $selection) {
                ForEach(Array(tutorial.pages.enumerated()), id: \.element.id) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            // As tall as the tallest card, so the sheet hugs the cards. With
            // very large text the cards scroll instead.
            .frame(maxHeight: pageHeight)
            .background {
                ZStack {
                    ForEach(tutorial.pages) { pageContent($0) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pageHeight = $0 }
            }

            Button(action: advance) {
                Text(isLastPage ? .gamesTutorialPlay : .gamesTutorialNext)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
            .accessibilityIdentifier("games.tutorial.next")
        }
        .padding(.top, PaeoniaSpacing.space32)
        .padding(.bottom, PaeoniaSpacing.space16)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
        .frame(maxHeight: .infinity, alignment: .top)
        .paeoniaScreenBackground(.paeoniaBackgroundSecondary)
        .preferredColorScheme(.dark)
        .presentationDetents(sheetHeight > pageHeight && pageHeight > 0 ? [.height(sheetHeight)] : [.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("games.tutorial.\(tutorial.kind.rawValue)")
    }

    private func pageView(_ page: GameTutorial.Page) -> some View {
        ScrollView {
            pageContent(page)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func pageContent(_ page: GameTutorial.Page) -> some View {
        VStack(spacing: PaeoniaSpacing.space24) {
            Image(page.image)
                .resizable()
                .accessibilityHidden(true)
                .scaledToFit()
                .frame(maxWidth: 320, maxHeight: 240)
                // Every card keeps the same slot, so the text stays put
                // between square boards and the wide Mind Meld cards.
                .frame(height: 240)

            VStack(spacing: PaeoniaSpacing.space8) {
                Text(page.title)
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(page.message)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        // Room for the page dots, which sit about 27 points above the bottom
        // of the pages, plus a clear gap between them and the text.
        .padding(.bottom, PaeoniaSpacing.space40 + PaeoniaSpacing.space16)
        .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
    }

    private func advance() {
        PaeoniaHaptics.gameContinued()
        guard !isLastPage else {
            dismiss()
            return
        }
        withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) {
            selection += 1
        }
    }
}
