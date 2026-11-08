import SwiftUI

/// Everything the root view needs for the app lock: the model for the Settings
/// screen, the cover window, and the banner when the lock turns itself off.
/// Developer flows and previews pass `isActive` false and get no lock at all.
struct AppLockRootModifier: ViewModifier {
    let isActive: Bool
    let bannerCenter: PaeoniaBannerCenter
    /// The launch canvas is under the cover. It shows the same mark in the same place,
    /// so the cover goes without a fade, which would leave its still mark over the reveal.
    let liftsAtOnce: Bool

    private let model = AppLockModel.shared
    @State private var cover = AppLockCoverController(model: .shared)

    func body(content: Content) -> some View {
        content
            .environment(isActive ? model : nil)
            .task {
                if isActive {
                    cover.install()
                }
            }
            .onChange(of: liftsAtOnce, initial: true) { _, liftsAtOnce in
                cover.liftsAtOnce = liftsAtOnce
            }
            .onChange(of: model.notice) { _, notice in
                guard let notice else { return }
                bannerCenter.show(
                    .info(
                        title: String(localized: notice.title),
                        message: String(localized: notice.message),
                        systemImage: "lock.open.fill",
                        timing: .untilDismissed
                    )
                )
                model.dismissNotice()
            }
    }
}
