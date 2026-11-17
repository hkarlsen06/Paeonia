import SwiftUI

/// The mark, the call button and the streak, in the navigation bar or in the header Home draws itself.
extension PairedHomeView {
    /// The brand mark and the streak at the corners, and both partners with their stories
    /// in the middle. The note bubbles over the avatars rise up beside the mark and the
    /// streak, so the row uses the space a navigation bar would leave empty.
    var homeHeader: some View {
        // The avatars and their note bubbles sit below the bar, where the map layout puts
        // its row of avatars, so they keep their place when one layout fades into the other.
        VStack(spacing: PaeoniaSpacing.space12 + PaeoniaSpacing.space8) {
            if drawsOwnHeader {
                markAndStreakRow()
            }
            if let stories, let storyPeople {
                HomeStoriesStrip(viewModel: stories, people: storyPeople)
            }
        }
    }

    /// The mark on the leading side, the call button and the streak on the trailing side, and
    /// `title` between them. The sides take equal widths while the title fits, so it sits in the
    /// middle, and the title only ever gets the room the sides leave.
    func markAndStreakRow(title: some View = EmptyView()) -> some View {
        HStack(spacing: PaeoniaSpacing.space8) {
            brandMark(height: Self.markHeight)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            title
                .layoutPriority(1)
            GlassEffectContainer {
                HStack {
                    // Calls the partner, on the side of the row nearest their avatar.
                    CallButton()
                        .glassEffect(.regular.interactive(), in: Circle())
                    if dailyChallengeStreak.isVisible {
                        DailyStreakToolbarLabel(state: dailyChallengeStreak, onTap: onTapStreak)
                            // The label pads itself for a capsule. This adds what the
                            // toolbar's capsule added, so the pill keeps its old width.
                            .padding(.horizontal, PaeoniaSpacing.space4)
                            .frame(minHeight: Self.headerBarHeight)
                            .glassEffect(.regular.interactive(), in: Capsule())
                            // Fades in once the streak is known instead of popping in.
                            .transition(.opacity)
                    }
                }
            }
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: Self.headerBarHeight)
        // The cards' screen padding is wider than a navigation bar's edge inset.
        .padding(.horizontal, Self.barEdgeInset - PaeoniaSpacing.screenHorizontalPadding)
        // In an iPad window the close and resize controls sit in the top leading corner,
        // where the mark would be. The row starts after them, as a navigation bar's items do.
        .containerCornerOffset(.leading, sizeToFit: true)
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: dailyChallengeStreak.isVisible)
    }

    /// The height of a navigation bar's row, so the mark and the streak sit where a bar
    /// would put them.
    private static let headerBarHeight = PaeoniaSpacing.compactButtonHeight
    /// How far a navigation bar keeps its items from the screen edge, so the streak
    /// doesn't shift when the user switches from a tab that has a bar.
    private static let barEdgeInset: CGFloat = 16
    /// The mark's frame in the navigation bar, which draws it a little smaller.
    private static let barMarkHeight: CGFloat = 28
    /// The size the navigation bar drew the mark at, for the header Home draws itself.
    private static let markHeight: CGFloat = 22

    @ToolbarContentBuilder
    var barItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            brandMark(height: Self.barMarkHeight)
        }
        // The mark is the brand, not a control, so keep it free of the
        // system's Liquid Glass capsule and let it sit flat on the bar.
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .topBarTrailing) {
            CallButton()
        }

        // Fades in when the streak count becomes available rather than popping in.
        if dailyChallengeStreak.isVisible {
            ToolbarItem(placement: .topBarTrailing) {
                DailyStreakToolbarLabel(state: dailyChallengeStreak, onTap: onTapStreak)
                    .transition(.opacity)
                    .animation(
                        reduceMotion ? nil : PaeoniaMotion.stateChange,
                        value: dailyChallengeStreak.isVisible
                    )
            }
        }
    }

    private func brandMark(height: CGFloat) -> some View {
        Image(.paeoniaMark)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }
}
