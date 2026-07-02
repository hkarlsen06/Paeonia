import SwiftUI

/// The pre-auth entry surface. It leads with a short, swipeable carousel of the
/// shared-artifact heroes (doodle, daily questions, countdown) and then hands off to
/// the existing `SignInView`. It is the first app surface the cold-launch intro
/// uncovers, so its content cascades in with `View.launchEntrance(order:)`.
///
/// A "Have an invite code?" path is reachable throughout for a partner who was sent a
/// code: it captures the code and moves them to sign-in, where the paywall picks the
/// code up so they join instead of paying.
struct WelcomeView: View {
    let isWorking: Bool
    let onAppleSignIn: () -> Void
    let onGoogleSignIn: () -> Void
    let onSubmitInviteCode: (String) -> Void

    private enum Phase {
        case carousel
        case signIn
    }

    private let carousel = WelcomeCarousel.standard
    @State private var index = 0
    @State private var phase: Phase = .carousel
    @State private var isInviteSheetPresented = false

    var body: some View {
        ZStack {
            background

            switch phase {
            case .carousel:
                carouselContent
                    .transition(.opacity)
            case .signIn:
                SignInView(
                    isWorking: isWorking,
                    onAppleSignIn: onAppleSignIn,
                    onGoogleSignIn: onGoogleSignIn,
                    onHaveInviteCode: presentInviteSheet
                )
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: index)
        .sheet(isPresented: $isInviteSheetPresented) {
            WelcomeInviteCodeSheet { code in
                onSubmitInviteCode(code)
                goToSignIn()
            }
        }
    }

    // MARK: - Carousel

    private var carouselContent: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            header
                .launchEntrance(order: 0)

            TabView(selection: $index) {
                ForEach(Array(carousel.pages.enumerated()), id: \.element.id) { offset, page in
                    WelcomeHeroPage(
                        title: page.title,
                        subtitle: page.subtitle,
                        showsBrandMark: offset == 0
                    )
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .launchEntrance(order: 1)

            VStack(spacing: PaeoniaSpacing.space24) {
                pageIndicator
                bottomControls
            }
            .launchEntrance(order: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        ZStack {
            // Text-only wordmark here — the petal mark is the centered hero below, so
            // showing it in the header too would double up.
            Text(.appTitle)
                .font(PaeoniaTypography.wordmark(size: 22))
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Spacer()
                Button(action: skipToSignIn) {
                    Text(.welcomeSkip)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
            }
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.top, PaeoniaSpacing.space16)
    }

    private var pageIndicator: some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            ForEach(0..<carousel.count, id: \.self) { dot in
                Capsule(style: .continuous)
                    .fill(dot == index ? Color.paeoniaAccentPrimary : Color.paeoniaTextTertiary.opacity(0.35))
                    .frame(width: dot == index ? 22 : 7, height: 7)
            }
        }
        .animation(PaeoniaMotion.stateChange, value: index)
        .accessibilityHidden(true)
    }

    private var bottomControls: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            Button(action: advance) {
                Text(carousel.isLast(index) ? .welcomeGetStarted : .welcomeNext)
            }
            .buttonStyle(PaeoniaPrimaryButtonStyle())

            Button(action: presentInviteSheet) {
                Text(.welcomeHaveInviteCode)
                    .frame(maxWidth: .infinity, minHeight: PaeoniaSpacing.compactButtonHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PaeoniaQuietButtonStyle())
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.bottom, PaeoniaSpacing.space16)
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color.paeoniaBackgroundPrimary

            RadialGradient(
                colors: [.paeoniaAccentPrimary.opacity(0.14), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    private func advance() {
        if carousel.isLast(index) {
            goToSignIn()
        } else {
            withAnimation(PaeoniaMotion.stateChange) {
                index += 1
            }
        }
    }

    private func skipToSignIn() {
        goToSignIn()
    }

    private func goToSignIn() {
        withAnimation(PaeoniaMotion.meaningfulMoment) {
            phase = .signIn
        }
    }

    private func presentInviteSheet() {
        isInviteSheetPresented = true
    }
}

/// One carousel page: its headline and supporting line, centered. Only the first page
/// shows the brand mark above the copy — the others are copy-only so the logo isn't
/// repeated across the carousel.
private struct WelcomeHeroPage: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let showsBrandMark: Bool

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space32) {
            if showsBrandMark {
                WelcomeBrandArt()
                    .frame(maxWidth: .infinity)
            }

            VStack(spacing: PaeoniaSpacing.space12) {
                Text(title)
                    .font(PaeoniaTypography.heroTitle)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(subtitle)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    WelcomeView(
        isWorking: false,
        onAppleSignIn: {},
        onGoogleSignIn: {},
        onSubmitInviteCode: { _ in }
    )
}
#endif
