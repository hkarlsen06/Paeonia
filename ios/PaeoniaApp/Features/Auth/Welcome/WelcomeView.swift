import SwiftUI
import UIKit

/// The first signed-out screen. The lockup, one picture and one line say what Paeonia
/// is, and three choices lead on: start a couple, join a partner who invited you, or
/// sign back in. It is the first surface the cold-launch intro uncovers, so its parts
/// cascade in with `View.launchEntrance(order:)`.
///
/// "I was invited" opens the code sheet. A partner who installed from the invite web
/// page gets a Paste button for the link it copied instead. A saved code moves the flow
/// on to sign-in (`WelcomeFlowModel.inviteCodeSaved`).
struct WelcomeView: View {
    let model: WelcomeFlowModel
    let onSubmitInviteCode: (String) -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var isInviteSheetPresented = false
    /// Whether the clipboard holds something that looks like a link. The `/join` web
    /// page copies the invite link when a partner without the app taps "Install",
    /// because the link itself is lost on the way through the App Store. Checking the
    /// pattern does not read the clipboard, so iOS shows no paste prompt. Only the
    /// system paste button reads it.
    @State private var clipboardHasLink = false

    var body: some View {
        // The summary sits just above the buttons, and the picture is centered between
        // the lockup and the summary. When it does not fit, such as at large text sizes,
        // the same content scrolls and the spacers shrink to their minimum.
        ViewThatFits(in: .vertical) {
            content

            ScrollView {
                content
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            choices
                .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
                .padding(.top, PaeoniaSpacing.space12)
                .padding(.bottom, PaeoniaSpacing.space8)
                .background(alignment: .top) {
                    // Content scrolling under the buttons fades out instead of being
                    // cut off by a hard edge.
                    LinearGradient(
                        colors: [.paeoniaBackgroundPrimary.opacity(0), .paeoniaBackgroundPrimary],
                        startPoint: .top,
                        endPoint: .init(x: 0.5, y: 0.12)
                    )
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                }
                .launchEntrance(order: 2)
        }
        .background(PaeoniaGlowBackground())
        .onAppear(perform: model.welcomeAppeared)
        // Checked again on return to the app, since the link may be copied after the
        // welcome screen first appeared.
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                return
            }
            let patterns = try? await UIPasteboard.general.detectedPatterns(for: [\.probableWebURL])
            clipboardHasLink = patterns?.contains(\.probableWebURL) ?? false
        }
        .sheet(isPresented: $isInviteSheetPresented) {
            PairingCodeEntrySheet(
                title: .welcomeInviteCodeTitle,
                message: .welcomeInviteCodeSubtitle,
                submitTitle: .welcomeInviteCodeContinue
            ) { code in
                onSubmitInviteCode(code)
                return true
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // The only lockup in the signed-out flow. Later steps leave it out.
            PaeoniaBrandLockup(wordmarkSize: 36, taglineSize: 17)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .launchEntrance(order: 0)

            Spacer(minLength: PaeoniaSpacing.space24)

            WelcomeHero()
                .launchEntrance(order: 1)

            Spacer(minLength: PaeoniaSpacing.space24)

            Text(.welcomeSummary)
                .font(PaeoniaTypography.welcomeSummary)
                .foregroundStyle(.paeoniaTextPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // Narrower than the column, so the lines come out close in length.
                .frame(maxWidth: 300)
                .launchEntrance(order: 1)
        }
        .frame(maxWidth: PaeoniaSpacing.focusedContentWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.screenTopSpacing)
        .padding(.bottom, PaeoniaSpacing.space24)
    }

    // MARK: Choices

    private var choices: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Button(action: model.chooseStart) {
                Text(.welcomeStartButton)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())
            .accessibilityIdentifier("welcome.start")

            invitedChoice

            Button(action: model.chooseReturning) {
                Text(.welcomeReturningButton)
                    .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
            .accessibilityIdentifier("welcome.returning")
        }
    }

    @ViewBuilder
    private var invitedChoice: some View {
        if clipboardHasLink {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PaeoniaSpacing.space8) {
                    invitePastePrompt
                    invitePasteButton
                }

                VStack(spacing: PaeoniaSpacing.space8) {
                    invitePastePrompt
                    invitePasteButton
                }
            }
            .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.buttonHeight)
        } else {
            Button(action: openInviteSheet) {
                Text(.welcomeInvitedButton)
            }
            .buttonStyle(PaeoniaSecondaryButtonStyle())
            .accessibilityIdentifier("welcome.invited")
        }
    }

    private var invitePastePrompt: some View {
        Text(.welcomeInvitePastePrompt)
            .font(PaeoniaTypography.bodyEmphasis)
            .foregroundStyle(.paeoniaTextPrimary)
            .multilineTextAlignment(.center)
    }

    /// The system paste button reads the clipboard without a permission prompt. Anything
    /// other than a Paeonia join link opens the code sheet, so the partner can still
    /// type the code.
    private var invitePasteButton: some View {
        PasteButton(payloadType: String.self) { strings in
            model.chooseJoining()
            if let code = PairingInviteCode.joinLinkCode(in: strings.joined(separator: " ")) {
                onSubmitInviteCode(code)
            } else {
                isInviteSheetPresented = true
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
        .tint(.paeoniaAccentSecondary)
    }

    private func openInviteSheet() {
        model.chooseJoining()
        isInviteSheetPresented = true
    }
}

#if DEBUG
#Preview {
    WelcomeView(
        model: WelcomeFlowModel(
            store: InMemoryWelcomeFlowStore(),
            funnel: NoOpWelcomeFunnelRecorder(),
            phoneHasNoOtherAccount: { true }
        ),
        onSubmitInviteCode: { _ in }
    )
    .environment(PaeoniaBannerCenter())
    .preferredColorScheme(.dark)
}
#endif
