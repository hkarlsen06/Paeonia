#if DEBUG
  import SwiftUI

  struct DeveloperRelationshipScenarioView: View {
    let scenario: DeveloperScenario

    var body: some View {
      Group {
        switch scenario {
        case .countdownMissing, .countdownUpcoming, .countdownToday:
          countdown
        default:
          map
        }
      }
      .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.paeoniaBackgroundPrimary)
    }

    private var countdown: some View {
      MilestoneCountdownCard(startedOn: relationshipStartedOn)
        .frame(maxWidth: 430)
    }

    private var relationshipStartedOn: String? {
      switch scenario {
      case .countdownMissing:
        nil
      case .countdownToday:
        Calendar.current.date(byAdding: .month, value: -1, to: Date())
          .map { PairingStartDate(date: $0).rawValue }
      default:
        "2026-01-08"
      }
    }

    private var map: some View {
      CoupleMapCard(
        currentName: "Alex",
        currentProfilePhotoAssetID: nil,
        partnerName: "Robin",
        partnerProfilePhotoAssetID: nil,
        state: mapState
      )
      .frame(maxWidth: 560)
    }

    private var mapState: CoupleMapState {
      switch scenario {
      case .locationCurrentMissing:
        .currentUnknown
      case .locationLive:
        .ready(
          current: location(latitude: 59.9139, longitude: 10.7522, age: 60),
          partner: location(latitude: 59.9280, longitude: 10.7150, age: 180),
          partnerWasStaleAtLastRefresh: false
        )
      case .locationStale:
        .ready(
          current: location(latitude: 59.9139, longitude: 10.7522, age: 60),
          partner: location(latitude: 59.9280, longitude: 10.7150, age: 30 * 3_600),
          partnerWasStaleAtLastRefresh: true
        )
      default:
        .partnerUnknown(.notSharing)
      }
    }

    private func location(latitude: Double, longitude: Double, age: TimeInterval) -> LocationPoint {
      LocationPoint(
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: 45,
        capturedAt: Date().addingTimeInterval(-age),
        updatedAt: Date().addingTimeInterval(-age)
      )
    }
  }
#endif
