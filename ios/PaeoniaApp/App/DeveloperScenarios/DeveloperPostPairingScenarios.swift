#if DEBUG
  import PencilKit
  import SwiftUI
  import UIKit

  /// The celebration and the first day sequence after it, with local data. Alex is
  /// the signed-in person and Robin the partner. As the person who joined, Alex
  /// unwraps Robin's heart, confirms the date Robin set, picks question time, and
  /// is asked to answer. As the inviter, Alex set everything up while waiting, so
  /// only Robin's drawing back is left to unwrap.
  @MainActor
  struct DeveloperPostPairingScenarioView: View {
    let acceptedInvite: Bool
    @State private var run = 0

    var body: some View {
      DeveloperPostPairingRun(acceptedInvite: acceptedInvite, onRestart: { run += 1 })
        .id(run)
    }
  }

  @MainActor
  private struct DeveloperPostPairingRun: View {
    let acceptedInvite: Bool
    let onRestart: () -> Void

    @State private var bannerCenter = PaeoniaBannerCenter()
    @State private var store: DeveloperLocalFlowCelebrationStore
    @State private var model: PostPairingFlowModel
    @State private var isCelebrating = true
    @State private var outcome: PostPairingOutcome?

    private static let context = PostPairingContext(
      pairID: UUID(uuidString: "abababab-0000-4000-8000-000000000001") ?? UUID(),
      currentUserID: DeveloperScenarioFixture.currentUserID,
      partnerUserID: DeveloperScenarioFixture.partnerUserID,
      coupleID: UUID(uuidString: "abababab-0000-4000-8000-000000000002") ?? UUID()
    )

    init(acceptedInvite: Bool, onRestart: @escaping () -> Void) {
      self.acceptedInvite = acceptedInvite
      self.onRestart = onRestart
      let operationProvider = DeveloperScenarioOperationProvider()
      let store = DeveloperLocalFlowCelebrationStore()
      _store = State(initialValue: store)
      _model = State(
        initialValue: PostPairingFlowModel(
          store: store,
          loader: DeveloperPostPairingLoader(
            gift: acceptedInvite ? DeveloperPostPairingFixture.heart() : DeveloperGamesFixture.umbrella(),
            questionTimeIsOn: !acceptedInvite,
            partnerAnswersWaiting: acceptedInvite
          ),
          widgetConfigurations: DeveloperNoWidgetConfigurations(),
          questionTimeModel: QuestionTimeModel(
            preferences: DeveloperNotificationPreferences(),
            pushAuthorization: DeveloperScenarioPushAuthorization(denied: false),
            primerStore: DeveloperLocalFlowPrimerStore()
          ),
          milestoneViewModel: RelationshipMilestoneViewModel(
            dataService: RelationshipStartedOnDataService(
              accessSnapshotStore: InMemoryAccessSyncSnapshotRepository(),
              pendingOperationStore: InMemoryPendingSyncOperationRepository()
            ),
            operationProvider: operationProvider
          ),
          drawingViewModel: WidgetDrawingViewModel(
            authorName: "Alex",
            service: DeveloperWidgetCanvasService(),
            uploader: DeveloperWidgetCanvasUploader()
          )
        )
      )
    }

    var body: some View {
      ZStack {
        if isCelebrating {
          PairingCelebrationView(
            currentDisplayName: "Alex",
            partnerDisplayName: "Robin",
            playsIntro: true,
            dismissTitle: model.gift == nil
              ? .pairingCelebrationGetStartedButton
              : .onboardingFirstDayGiftButton("Robin"),
            onDismiss: dismissCelebration
          )
          .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
          .padding(.top, PaeoniaSpacing.screenTopSpacing)
          .padding(.bottom, PaeoniaSpacing.space16)
          .paeoniaReadableWidth(PaeoniaSpacing.focusedContentWidth)
          .transition(.opacity)
        } else if let outcome {
          finished(outcome)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
          PostPairingFlowView(
            model: model,
            partnerName: "Robin",
            currentDisplayName: "Alex",
            startedOn: "2024-03-03",
            acceptedInvite: acceptedInvite,
            syncAfterLocalChange: {},
            onFinish: { outcome = $0 }
          )
          .transition(.opacity)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.paeoniaBackgroundPrimary)
      .animation(PaeoniaMotion.pairedScreenTransition, value: isCelebrating)
      .animation(PaeoniaMotion.pairedScreenTransition, value: outcome)
      .environment(bannerCenter)
      .paeoniaTopBanner(bannerCenter)
      .preferredColorScheme(.dark)
      .onAppear {
        model.prepare(Self.context)
      }
    }

    /// What the root does on dismiss: the progress starts.
    private func dismissCelebration() {
      store.markCelebrationSeen(forPairID: Self.context.pairID)
      store.savePostPairingProgress(PostPairingProgress(), forPairID: Self.context.pairID)
      isCelebrating = false
    }

    private func finished(_ outcome: PostPairingOutcome) -> some View {
      VStack(spacing: PaeoniaSpacing.space16) {
        Text(verbatim: outcome == .answerQuestions ? "Done · opens the answer flow" : "Done · lands on Home")
          .font(PaeoniaTypography.title)
          .foregroundStyle(.paeoniaTextPrimary)
        Button(action: onRestart) {
          Text(verbatim: "Play again")
        }
        .buttonStyle(PaeoniaSecondaryButtonStyle())
      }
      .padding(PaeoniaSpacing.screenHorizontalPadding)
    }
  }

  /// Local answers for the first day steps. The gift arrives after a moment, so the
  /// celebration's button changes to name it.
  private struct DeveloperPostPairingLoader: PostPairingDataLoading {
    let gift: PKDrawing?
    let questionTimeIsOn: Bool
    let partnerAnswersWaiting: Bool

    func partnerGift(partnerUserID _: UUID) async -> PostPairingGiftLoad {
      try? await Task.sleep(for: .seconds(1.5))
      return gift.map { .ready(PostPairingGift(revisionID: UUID(), drawing: $0)) } ?? .none
    }

    // swiftlint:disable:next async_without_await
    func ownDrawingImage(currentUserID _: UUID) async -> UIImage? {
      nil
    }

    func questionTimeIsOn() async -> Bool? {
      try? await Task.sleep(for: .milliseconds(200))
      return questionTimeIsOn
    }

    func partnerAnswersWaiting(currentUserID _: UUID) async -> Bool {
      try? await Task.sleep(for: .milliseconds(200))
      return partnerAnswersWaiting
    }
  }

  /// No widgets installed, so the widget nudge follows a drawing back.
  private struct DeveloperNoWidgetConfigurations: WidgetConfigurationProviding {
    // swiftlint:disable:next async_without_await
    func installedWidgetKinds() async throws -> [String] { [] }
  }

  enum DeveloperPostPairingFixture {
    /// A heart at the canonical canvas size, drawn as two halves and a little
    /// sparkle, with real time offsets so the replay has a pace to follow.
    static func heart() -> PKDrawing {
      let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
      let center = CGPoint(x: 160, y: 170)
      func point(_ angle: Double) -> CGPoint {
        // The classic heart curve, scaled to the canvas.
        let x = 16 * pow(sin(angle), 3)
        let y = 13 * cos(angle) - 5 * cos(2 * angle) - 2 * cos(3 * angle) - cos(4 * angle)
        return CGPoint(x: center.x + x * 6, y: center.y - y * 6)
      }
      let right = (0...40).map { point(Double($0) / 40 * .pi) }
      let left = (0...40).map { point(-Double($0) / 40 * .pi) }
      let sparkle = [CGPoint(x: 248, y: 70), CGPoint(x: 262, y: 56), CGPoint(x: 276, y: 70), CGPoint(x: 262, y: 84),
                     CGPoint(x: 248, y: 70)]
      return PKDrawing(strokes: [
        stroke(left, color: .paeoniaAccentPrimary, startsAt: base),
        stroke(right, color: .paeoniaAccentPrimary, startsAt: base.addingTimeInterval(2.6)),
        stroke(sparkle, color: .paeoniaInkGold, startsAt: base.addingTimeInterval(5)),
      ])
    }

    private static func stroke(_ points: [CGPoint], color: UIColor, startsAt date: Date) -> PKStroke {
      let controlPoints = points.enumerated().map { index, point in
        PKStrokePoint(
          location: point,
          timeOffset: Double(index) * 0.05,
          size: CGSize(width: 8, height: 8),
          opacity: 1,
          force: 1,
          azimuth: 0,
          altitude: .pi / 2
        )
      }
      return PKStroke(
        ink: PKInk(.pen, color: color),
        path: PKStrokePath(controlPoints: controlPoints, creationDate: date)
      )
    }
  }
#endif
