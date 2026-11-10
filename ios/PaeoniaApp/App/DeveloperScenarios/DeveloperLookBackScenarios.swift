#if DEBUG
  import SwiftUI
  import UIKit

  /// The Us tab's look-back card for each kind of item it brings back.
  nonisolated extension DeveloperScenario {
    static let lookBack: [DeveloperScenario] = [homeLookBack]

    static let homeLookBack = DeveloperScenario(
      "home-look-back", "Look-back card", "An old drawing, question and memory on the Us tab", .memories
    ) { _ in DeveloperLookBackScenarioView() }
  }

  private struct DeveloperLookBackScenarioView: View {
    private static let me = UUID()
    private static let robin = UUID()
    private static let calendar = Calendar(identifier: .gregorian)

    private static func day(daysAgo: Int) -> String {
      let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
      let parts = calendar.dateComponents([.year, .month, .day], from: date)
      return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static let items: [LookBackItem] = [
      LookBackItem(
        kind: .drawing,
        contentDate: day(daysAgo: 14),
        onThisDay: false,
        question: nil,
        drawing: .init(revisionID: UUID(), mediaAssetID: UUID(), authorUserID: me, canvasSide: nil),
        memory: nil
      ),
      LookBackItem(
        kind: .question,
        contentDate: day(daysAgo: 365),
        onThisDay: true,
        question: .init(
          instanceID: UUID(),
          shortPromptEN: "A small moment today",
          shortPromptNB: "Et lite øyeblikk i dag",
          ownAnswer: .init(userID: me, text: "The walk home", selectedUserID: nil, hasPhoto: false, hasVoice: false),
          partnerAnswer: .init(userID: robin, text: nil, selectedUserID: nil, hasPhoto: true, hasVoice: false)
        ),
        drawing: nil,
        memory: nil
      ),
      LookBackItem(
        kind: .memory,
        contentDate: day(daysAgo: 60),
        onThisDay: false,
        question: nil,
        drawing: nil,
        memory: .init(memoryID: UUID(), title: "Beach weekend", photoMediaAssetID: nil)
      ),
    ]

    var body: some View {
      ScrollView {
        VStack(spacing: PaeoniaSpacing.space16) {
          ForEach(Self.items, id: \.contentDate) { item in
            HomeLookBackCard(
              item: item,
              currentUserID: Self.me,
              partnerName: "Robin",
              thumbnailLoader: SketchThumbnailLoader()
            )
          }
        }
        .padding(PaeoniaSpacing.screenHorizontalPadding)
      }
      .background(.paeoniaBackgroundPrimary)
      .preferredColorScheme(.dark)
    }
  }

  /// Every drawing is the sample sketch the widget shows.
  private struct SketchThumbnailLoader: WidgetRevisionThumbnailLoading {
    func thumbnailPNG(revisionID: UUID, mediaAssetID: UUID, canvasSide: CGFloat) async -> Data? {
      await MainActor.run { UIImage(resource: .placeholderSketch).pngData() }
    }

    func exportPNG(mediaAssetID: UUID, canvasSide: CGFloat) -> Data? { nil }
  }
#endif
