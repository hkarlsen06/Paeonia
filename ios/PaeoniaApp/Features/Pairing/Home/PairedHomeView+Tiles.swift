import SwiftUI

extension PairedHomeView {
    var milestoneAndWidget: some View {
        // One layout keeps the cards' identity, so a text size change doesn't
        // reset them or close the milestone sheet. On a wide iPad each tile is a
        // column wide, so they stay side by side at every text size.
        let layout = if dynamicTypeSize.isAccessibilitySize && !isWideLayout {
            AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space16))
        } else {
            AnyLayout(HStackLayout(alignment: .top, spacing: PaeoniaSpacing.space16))
        }
        // On a wide iPad the pair usually sits under the header, so the drawing goes
        // under the avatars and the calendar to the edge, where it doesn't compete with
        // them. `ForEach` keeps each tile's identity when the order flips.
        let tiles: [HomeTile] = isWideLayout ? [.drawing, .milestone] : [.milestone, .drawing]
        return layout {
            ForEach(tiles, id: \.self) { tile in
                switch tile {
                case .milestone:
                    milestoneCard
                case .drawing:
                    HomeWidgetCard(
                        coupleID: coupleID,
                        partnerName: partnerDisplayName?.trimmedNonEmpty,
                        onOpen: onOpenWidgetDrawing
                    )
                }
            }
        }
    }

    private enum HomeTile {
        case milestone
        case drawing
    }

    private var milestoneCard: some View {
        MilestoneCountdownCard(
            startedOn: relationshipStartedOn,
            isSaving: milestoneIsSaving,
            isLoading: milestoneIsLoading,
            onSave: onSaveRelationshipStartedOn,
            coupleDates: coupleDates,
            names: coupleDateNames
        )
    }
}
