import SwiftUI

struct RecapTimelineLink<Label: View>: View {
    let day: Date
    @ViewBuilder let label: Label

    @Environment(RecapViewModel.self) private var recaps: RecapViewModel?
    @State private var opened: AnniversaryRecap?

    var body: some View {
        if let recaps, let recap = recaps.recap(on: RecapCalendar.today(day)) {
            Button { opened = recap } label: {
                VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                    label
                    SwiftUI.Label {
                        Text(.recapTimelineOpen)
                    } icon: {
                        Image(systemName: "sparkles").accessibilityHidden(true)
                    }
                        .font(PaeoniaTypography.caption.weight(.semibold))
                        .foregroundStyle(.paeoniaAccentPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("timeline.recap.\(recap.anniversaryDate)")
            .sheet(item: $opened) { recap in
                RecapView(model: recaps, recap: recap)
                    .analyticsScreen("recap")
            }
        } else {
            label
        }
    }
}
