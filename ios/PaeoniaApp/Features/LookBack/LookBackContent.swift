import SwiftUI
import UIKit

/// What the look-back card shows for an item, by kind, under an optional header. A picture's header
/// sits beside it, above the title, so the picture fills the card's height.
struct LookBackContent<Header: View>: View {
    let item: LookBackItem
    let currentUserID: UUID?
    let partnerName: String
    let thumbnailLoader: any WidgetRevisionThumbnailLoading
    /// Shows every line of the words instead of the card's short preview, as the recap does.
    var showsFullText = false
    @ViewBuilder var header: Header

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if let question = item.question, item.kind == .question {
            questionContent(question)
        } else if let drawing = item.drawing, item.kind == .drawing {
            pictureRow {
                LookBackDrawingThumbnail(drawing: drawing, loader: thumbnailLoader)
            } text: {
                Text(verbatim: Self.drawingTitle(drawing, currentUserID: currentUserID, partnerName: partnerName))
            }
        } else if let memory = item.memory, item.kind == .memory {
            pictureRow {
                if let photoID = memory.photoMediaAssetID {
                    MemoryMediaImageView(
                        mediaAssetID: photoID,
                        height: LookBackLayout.pictureSide,
                        cornerRadius: LookBackLayout.pictureRadius,
                        allowsViewing: false
                    )
                    .frame(width: LookBackLayout.pictureSide)
                    .lookBackPrint()
                }
            } text: {
                Text(verbatim: memory.title)
            }
        }
    }

    // MARK: Question

    private func questionContent(_ question: LookBackItem.Question) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            header
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                Text(verbatim: question.shortPrompt(for: locale))
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .lineLimit(showsFullText ? nil : 3)
                LookBackAnswerRow(
                    name: String(localized: .dailyChallengeChoiceYou),
                    answer: question.ownAnswer,
                    names: names(for: question),
                    showsFullText: showsFullText
                )
                LookBackAnswerRow(
                    name: partnerName, answer: question.partnerAnswer, names: names(for: question),
                    showsFullText: showsFullText
                )
            }
        }
    }

    private func names(for question: LookBackItem.Question) -> [UUID: String] {
        [
            question.ownAnswer.userID: String(localized: .dailyChallengeChoiceYou),
            question.partnerAnswer.userID: partnerName,
        ]
    }

    // MARK: Drawing and memory

    /// A picture beside a title and the date, or stacked at accessibility text sizes.
    private func pictureRow(
        @ViewBuilder picture: () -> some View,
        @ViewBuilder text: () -> some View
    ) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: PaeoniaSpacing.space16))
        return layout {
            picture()
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space8) {
                header
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    text()
                        .font(PaeoniaTypography.bodyEmphasis)
                        .foregroundStyle(.paeoniaTextPrimary)
                        .lineLimit(showsFullText ? nil : 3)
                    if let day = item.contentDay {
                        Text(day, format: .dateTime.day().month(.abbreviated).year())
                            .font(PaeoniaTypography.caption)
                            .foregroundStyle(.paeoniaTextSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Text for VoiceOver and titles

    static func drawingTitle(_ drawing: LookBackItem.Drawing, currentUserID: UUID?, partnerName: String) -> String {
        drawing.authorUserID == currentUserID
            ? String(localized: .homeLookBackDrawingYours)
            : String(localized: .homeLookBackDrawingPartners(partnerName))
    }

    /// The card's content as one sentence for VoiceOver.
    static func summary(item: LookBackItem, currentUserID: UUID?, partnerName: String, locale: Locale) -> String? {
        if let question = item.question, item.kind == .question {
            let you = String(localized: .dailyChallengeChoiceYou)
            let names = [question.ownAnswer.userID: you, question.partnerAnswer.userID: partnerName]
            return [
                String(localized: .homeLookBackQuestionAccessibility(question.shortPrompt(for: locale))),
                "\(you): \(LookBackAnswerRow.spoken(question.ownAnswer, names: names))",
                "\(partnerName): \(LookBackAnswerRow.spoken(question.partnerAnswer, names: names))",
            ].joined(separator: ". ")
        }
        if let drawing = item.drawing, item.kind == .drawing {
            return drawingTitle(drawing, currentUserID: currentUserID, partnerName: partnerName)
        }
        if let memory = item.memory, item.kind == .memory {
            return String(localized: .homeLookBackMemoryAccessibility(memory.title))
        }
        return nil
    }
}

extension LookBackContent where Header == EmptyView {
    init(
        item: LookBackItem,
        currentUserID: UUID?,
        partnerName: String,
        thumbnailLoader: any WidgetRevisionThumbnailLoading,
        showsFullText: Bool = false
    ) {
        self.init(
            item: item,
            currentUserID: currentUserID,
            partnerName: partnerName,
            thumbnailLoader: thumbnailLoader,
            showsFullText: showsFullText
        ) { EmptyView() }
    }
}

private enum LookBackLayout {
    static let pictureSide: CGFloat = 76
    static let pictureRadius: CGFloat = 4
    static let printBorder: CGFloat = 6
    static let printTilt: Angle = .degrees(-4)
}

private extension View {
    /// A picture as a small keepsake print: a pale frame with a wider bottom edge, tilted a little.
    func lookBackPrint() -> some View {
        padding(LookBackLayout.printBorder)
            .padding(.bottom, LookBackLayout.printBorder * 2)
            .background(.paeoniaMemory, in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius8, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            .rotationEffect(LookBackLayout.printTilt)
    }
}

/// One person's answer on one line: their name, then their words or how they answered.
private struct LookBackAnswerRow: View {
    let name: String
    let answer: LookBackItem.Answer
    /// Names by user id, to name the person a "pick one of you" answer chose.
    let names: [UUID: String]
    let showsFullText: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // With every line shown at accessibility sizes, the words go under the name and use the full width.
        let layout = showsFullText && dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: PaeoniaSpacing.space8))
        layout {
            Text(verbatim: name)
                .font(PaeoniaTypography.caption.weight(.semibold))
                .foregroundStyle(.paeoniaTextTertiary)
            answerView
        }
    }

    @ViewBuilder
    private var answerView: some View {
        switch answer.display {
        case let .text(text):
            Text(verbatim: text)
                .font(PaeoniaTypography.body)
                .foregroundStyle(.paeoniaTextPrimary)
                .lineLimit(showsFullText ? nil : 2)
        case .photo:
            indicator("photo", Text(.dailyChallengeKindPhoto))
        case .voice:
            indicator("mic", Text(.dailyChallengeKindVoice))
        case let .choice(userID):
            indicator("person.2", Text(verbatim: names[userID] ?? ""))
        case .none:
            EmptyView()
        }
    }

    private func indicator(_ systemImage: String, _ label: Text) -> some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            Image(systemName: systemImage)
                .foregroundStyle(.paeoniaAccentPrimary)
                .accessibilityHidden(true)
            label
                .foregroundStyle(.paeoniaTextPrimary)
        }
        .font(PaeoniaTypography.body)
    }

    /// The answer as words, for VoiceOver.
    static func spoken(_ answer: LookBackItem.Answer, names: [UUID: String]) -> String {
        switch answer.display {
        case let .text(text): text
        case .photo: String(localized: .dailyChallengeKindPhoto)
        case .voice: String(localized: .dailyChallengeKindVoice)
        case let .choice(userID): names[userID] ?? ""
        case .none: ""
        }
    }
}

/// A saved drawing as a small print, rendered over the same plum surface the history timeline uses.
/// It shows a quiet placeholder while loading and when the picture cannot be built.
private struct LookBackDrawingThumbnail: View {
    let drawing: LookBackItem.Drawing
    let loader: any WidgetRevisionThumbnailLoading

    @State private var image: UIImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LookBackLayout.pictureRadius, style: .continuous)
        shape
            .fill(.paeoniaBackgroundPrimary)
            .frame(width: LookBackLayout.pictureSide, height: LookBackLayout.pictureSide)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "scribble")
                        .foregroundStyle(.paeoniaTextTertiary)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(shape)
            .lookBackPrint()
            .accessibilityHidden(true)
            .task(id: drawing.revisionID) {
                let side = drawing.canvasSide.map { CGFloat($0) } ?? WidgetDrawingViewModel.fallbackCanvasSide
                let data = await loader.thumbnailPNG(
                    revisionID: drawing.revisionID,
                    mediaAssetID: drawing.mediaAssetID,
                    canvasSide: side
                )
                guard !Task.isCancelled, let data else { return }
                image = UIImage(data: data)
            }
    }
}
