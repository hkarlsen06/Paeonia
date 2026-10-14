import SwiftUI

/// The small popover that opens when someone taps a line: who wrote it, when,
/// and the dared word when the line used one.
///
/// The screen passes the copy in, so this view holds no text of its own. `time`
/// is already formatted, such as "Tue 21:04". `usedDare` is the finished line,
/// such as "Used LIGHTHOUSE".
struct StoryChainLineInfoView<Avatar: View>: View {
    let name: String
    let time: String
    var usedDare: Text?
    @ViewBuilder var avatar: () -> Avatar

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            avatar()
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                Text(verbatim: "\(name) \u{00B7} \(time)")
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)
                if let usedDare {
                    HStack(spacing: PaeoniaSpacing.space4) {
                        Image(systemName: "textformat")
                            .foregroundStyle(Color.paeoniaInkGold)
                            .accessibilityHidden(true)
                        usedDare
                            .foregroundStyle(.paeoniaTextSecondary)
                    }
                    .font(PaeoniaTypography.caption)
                }
            }
        }
        .padding(PaeoniaSpacing.space16)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview {
    StoryChainLineInfoView(name: "Robin", time: "Tue 21:04", usedDare: Text(verbatim: "Used LIGHTHOUSE")) {
        Circle().fill(.paeoniaPartnerTwo).frame(width: 32, height: 32)
    }
    .background(.paeoniaSurfacePrimary)
}
#endif
