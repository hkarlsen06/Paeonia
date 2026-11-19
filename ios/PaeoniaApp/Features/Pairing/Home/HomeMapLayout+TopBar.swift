import SwiftUI

extension HomeMapLayout {
    func topBar(_ couple: HomeMapCouple?) -> some View {
        VStack(spacing: PaeoniaSpacing.space8) {
            header(AnyView(Group { if !dynamicTypeSize.isAccessibilitySize { title(couple) } }))
                .frame(height: PaeoniaSpacing.compactButtonHeight)
            if dynamicTypeSize.isAccessibilitySize {
                title(couple)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        // Leave room below the pill for the bar's glass.
        .padding(.bottom, PaeoniaSpacing.space12)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topBarHeight = $0 }
    }

    /// The partner's hearts while they play, otherwise how far apart the couple is.
    @ViewBuilder
    private func title(_ couple: HomeMapCouple?) -> some View {
        ZStack {
            if let line = hearts?.incomingLine {
                HeartsIncomingLine(text: line)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else if let couple {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: PaeoniaSpacing.space8))
                    : AnyLayout(HStackLayout(spacing: 0))
                layout {
                    HomeMapDistanceLine(
                        current: couple.current,
                        partner: couple.partner,
                        partnerCoordinate: couple.partner.coordinate,
                        partnerWasStaleAtLastRefresh: couple.partnerWasStaleAtLastRefresh,
                        partnerName: partnerName,
                        compass: compass
                    )
                    .accessibilityAction(named: Text(.heartsSendAction)) { sendHeart() }
                    HomeMapCreditsButton()
                        .layoutPriority(1)
                }
                // A new place pans the map over `homeLayoutDuration`. The distance rolls to
                // match, and the info button moves with the line's new width.
                .animation(reduceMotion ? nil : PaeoniaMotion.homeLayoutChange, value: [couple.current, couple.partner])
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: hearts?.incomingLine)
    }

}
