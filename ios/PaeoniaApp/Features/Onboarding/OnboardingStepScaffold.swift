import SwiftUI

/// Where an onboarding step is shown. Inside `PaeoniaScreenFrame` the frame already
/// draws the background, the side margins and the column width, so the step adds none
/// of them. After pairing the step stands alone and draws them itself.
enum OnboardingStepPlacement {
    case screenFrame
    case standalone
}

/// A button in an onboarding step's bottom bar.
struct OnboardingStepAction {
    let title: LocalizedStringResource
    /// Shows a spinner in place of the title and ignores taps.
    var isLoading = false
    var isEnabled = true
    let action: () -> Void
}

/// The shared layout of an onboarding step: optional art at the top, a title and a
/// short message, the step's own content, and a bottom bar with a primary button and
/// a quiet second choice under it. Everything drops in with the screen entrance
/// cascade (art, text, content, then the bar). Either button can come and go, for a
/// step whose choices change, and the bar animates the change. On an iPad the step
/// sits in the middle of the screen, above the bar.
struct OnboardingStepScaffold<Art: View, Content: View>: View {
    let title: LocalizedStringResource
    let message: LocalizedStringResource?
    let placement: OnboardingStepPlacement
    let primary: OnboardingStepAction?
    let secondary: OnboardingStepAction?
    /// Holds the entrance until the step has what it needs to show. Once true, it
    /// must stay true.
    let isReady: Bool
    /// The id of a view in the content to scroll into sight, such as a picker that
    /// just opened under the fold. The scroll runs each time it changes to a new id.
    let scrollTarget: AnyHashable?
    private let art: Art
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The scroll view's height above the bottom bar.
    @State private var visibleHeight: CGFloat = 0

    init(
        title: LocalizedStringResource,
        message: LocalizedStringResource? = nil,
        placement: OnboardingStepPlacement = .screenFrame,
        primary: OnboardingStepAction? = nil,
        secondary: OnboardingStepAction? = nil,
        isReady: Bool = true,
        scrollTarget: AnyHashable? = nil,
        @ViewBuilder art: () -> Art,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.message = message
        self.placement = placement
        self.primary = primary
        self.secondary = secondary
        self.isReady = isReady
        self.scrollTarget = scrollTarget
        self.art = art()
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            scrollView
                .onChange(of: scrollTarget) { _, target in
                    guard let target else {
                        return
                    }
                    withAnimation(reduceMotion ? nil : PaeoniaMotion.stateChange) {
                        proxy.scrollTo(target, anchor: .bottom)
                    }
                }
        }
    }

    private var scrollView: some View {
        ScrollView {
            VStack(spacing: PaeoniaSpacing.sectionSpacing) {
                if Art.self != EmptyView.self {
                    art
                        .screenEntrance(order: 1, isReady: isReady)
                }

                header
                    .screenEntrance(order: 2, isReady: isReady)

                content
                    .screenEntrance(order: 3, isReady: isReady)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space24)
            // An iPad screen leaves most of the height empty, so the step sits in
            // the middle of it instead of at the top.
            .frame(minHeight: isWide ? visibleHeight : nil)
            .modifier(OnboardingStepColumn(placement: placement))
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height
        } action: { _, height in
            visibleHeight = height
        }
        .paeoniaBottomBar(spacing: 0) {
            actionBar
                .padding(.top, PaeoniaSpacing.space12)
                .padding(.bottom, placement == .standalone ? PaeoniaSpacing.space16 : 0)
                .modifier(OnboardingStepColumn(placement: placement))
                .onboardingBottomBarFade()
                .screenEntrance(order: 4, isReady: isReady)
        }
        .background {
            if placement == .standalone {
                PaeoniaGlowBackground()
            }
        }
    }

    /// An iPad width.
    private var isWide: Bool {
        horizontalSizeClass == .regular
    }

    private var header: some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            Text(title)
                .font(PaeoniaTypography.title)
                .foregroundStyle(.paeoniaTextPrimary)
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isHeader)

            if let message {
                Text(message)
                    .font(PaeoniaTypography.body)
                    .foregroundStyle(.paeoniaTextSecondary)
                    .contentTransition(.opacity)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private var actionBar: some View {
        VStack(spacing: PaeoniaSpacing.space12) {
            if let primary {
                Button(action: primary.action) {
                    Text(primary.title)
                }
                .buttonStyle(PaeoniaPrimaryButtonStyle(isLoading: primary.isLoading))
                .disabled(!primary.isEnabled)
                .transition(buttonTransition)
            }

            if let secondary {
                Button(action: secondary.action) {
                    Text(secondary.title)
                }
                .buttonStyle(PaeoniaQuietButtonStyle())
                .disabled(!secondary.isEnabled)
                .frame(maxWidth: .infinity)
                .transition(buttonTransition)
            }
        }
        .animation(PaeoniaMotion.stateChange, value: primary == nil)
        .animation(PaeoniaMotion.stateChange, value: secondary == nil)
    }

    private var buttonTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12))
    }
}

extension OnboardingStepScaffold where Art == EmptyView {
    init(
        title: LocalizedStringResource,
        message: LocalizedStringResource? = nil,
        placement: OnboardingStepPlacement = .screenFrame,
        primary: OnboardingStepAction? = nil,
        secondary: OnboardingStepAction? = nil,
        isReady: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            message: message,
            placement: placement,
            primary: primary,
            secondary: secondary,
            isReady: isReady,
            art: { EmptyView() },
            content: content
        )
    }
}

/// The margins and column width `PaeoniaScreenFrame` gives its content, for a step
/// that stands alone.
private struct OnboardingStepColumn: ViewModifier {
    let placement: OnboardingStepPlacement

    func body(content: Content) -> some View {
        switch placement {
        case .screenFrame:
            content
        case .standalone:
            content
                .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
                .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        }
    }
}

#if DEBUG
#Preview("Standalone") {
    OnboardingStepScaffold(
        title: .onboardingQuestionTimeTitle,
        message: .onboardingQuestionTimeMessagePaired,
        placement: .standalone,
        primary: OnboardingStepAction(title: .onboardingWidgetNudgeContinueButton) {},
        secondary: OnboardingStepAction(title: .onboardingQuestionTimeNotNowButton) {}
    ) {
        Image(systemName: "sparkles")
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(.paeoniaAccentPrimary)
    } content: {
        Text(verbatim: "Step content")
            .foregroundStyle(.paeoniaTextSecondary)
    }
    .preferredColorScheme(.dark)
}

#Preview("In the screen frame") {
    PaeoniaScreenFrame {
        OnboardingStepScaffold(
            title: .onboardingWidgetNudgeTitle,
            message: .onboardingWidgetNudgeMessage,
            secondary: OnboardingStepAction(title: .onboardingWidgetNudgeLaterButton) {}
        ) {
            Text(verbatim: "Step content")
                .foregroundStyle(.paeoniaTextSecondary)
        }
    }
    .preferredColorScheme(.dark)
}
#endif
