import SwiftUI

/// The Home card that brings an old question, drawing or memory back. Home hides it when there is
/// nothing to show. The whole card is one button. The caller decides where a tap goes
/// (`LookBackItem.destination`).
struct HomeLookBackCard: View {
    let item: LookBackItem
    let currentUserID: UUID?
    let partnerName: String
    let thumbnailLoader: any WidgetRevisionThumbnailLoading
    var onOpen: () -> Void = {}

    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: onOpen) {
            PaeoniaCard {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
                    header
                    LookBackContent(
                        item: item,
                        currentUserID: currentUserID,
                        partnerName: partnerName,
                        thumbnailLoader: thumbnailLoader
                    )
                }
            }
        }
        .buttonStyle(.paeoniaPressableCard)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(.homeLookBackOpenAction), onOpen)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space12) {
            PaeoniaCardEyebrow(eyebrow)
            Spacer(minLength: PaeoniaSpacing.space8)
            if let whenText {
                Text(verbatim: whenText)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }
        }
    }

    private var eyebrow: LocalizedStringResource {
        item.onThisDay ? .homeLookBackEyebrowOnThisDay : .homeLookBackEyebrowEarlier
    }

    /// The year for "on this day", otherwise how long ago, like "3 weeks ago".
    private var whenText: String? {
        if item.onThisDay, let year = item.contentYear {
            return String(year)
        }
        return item.contentDay?.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }

    private var accessibilityLabel: String {
        [String(localized: eyebrow), whenText, LookBackContent.summary(
            item: item,
            currentUserID: currentUserID,
            partnerName: partnerName,
            locale: locale
        )]
        .compactMap { $0 }
        .joined(separator: ". ")
    }
}

#if DEBUG
private enum LookBackPreviewData {
    static let me = UUID()
    static let partner = UUID()

    static let question = LookBackItem(
        kind: .question,
        contentDate: "2025-10-14",
        onThisDay: true,
        question: .init(
            instanceID: UUID(),
            shortPromptEN: "A small moment today",
            shortPromptNB: "Et lite øyeblikk",
            ownAnswer: .init(
                userID: me, text: "The walk home", selectedUserID: nil, hasPhoto: false, hasVoice: false
            ),
            partnerAnswer: .init(
                userID: partner, text: nil, selectedUserID: nil, hasPhoto: true, hasVoice: false
            )
        ),
        drawing: nil,
        memory: nil
    )

    static let memory = LookBackItem(
        kind: .memory,
        contentDate: "2026-09-01",
        onThisDay: false,
        question: nil,
        drawing: nil,
        memory: .init(memoryID: UUID(), title: "Beach weekend", photoMediaAssetID: nil)
    )
}

#Preview {
    VStack(spacing: PaeoniaSpacing.space16) {
        ForEach([LookBackPreviewData.question, LookBackPreviewData.memory], id: \.contentDate) { item in
            HomeLookBackCard(
                item: item,
                currentUserID: LookBackPreviewData.me,
                partnerName: "Oda",
                thumbnailLoader: NoOpWidgetRevisionThumbnailLoader()
            )
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.paeoniaBackgroundPrimary)
    .preferredColorScheme(.dark)
}
#endif
