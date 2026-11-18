import SwiftUI

/// What comes back when two people bring back what they had, as a short list of
/// things, and one line about what does not. The join screen and the inviter's
/// answer screen both show it.
struct RelationshipRestoreSummary: View {
    /// Says whose yes it takes, such as "Comes back if Robin says yes".
    let title: LocalizedStringResource

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let items: [(title: LocalizedStringResource, symbol: String)] = [
        (.pairingRestoreItemAnswers, "text.bubble.fill"),
        (.pairingRestoreItemChats, "bubble.left.and.bubble.right.fill"),
        (.pairingRestoreItemMemories, "heart.text.square.fill"),
        (.pairingRestoreItemDrawings, "scribble.variable"),
        (.pairingRestoreItemPhotos, "photo.fill"),
        (.pairingRestoreItemVoiceMessages, "waveform"),
    ]

    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(
            repeating: GridItem(.flexible(), spacing: PaeoniaSpacing.space12, alignment: .leading),
            count: count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
            Text(title)
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, alignment: .leading, spacing: PaeoniaSpacing.space12) {
                ForEach(Self.items.indices, id: \.self) { index in
                    Label {
                        Text(Self.items[index].title)
                            .font(PaeoniaTypography.body)
                            .foregroundStyle(.paeoniaTextPrimary)
                    } icon: {
                        SettingsMenuIcon(systemName: Self.items[index].symbol)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            Rectangle()
                .fill(.paeoniaBorder)
                .frame(height: 1)
                .accessibilityHidden(true)

            Label {
                Text(.pairingRestoreGone)
            } icon: {
                Image(systemName: "minus.circle")
                    .accessibilityHidden(true)
            }
            .font(PaeoniaTypography.caption)
            .foregroundStyle(.paeoniaTextSecondary)
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(PaeoniaSpacing.cardContentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paeoniaCardSurface(
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.standard, style: .continuous),
            fill: .paeoniaSurfacePrimary
        )
    }
}
