import Observation
import SwiftUI

/// The one way the app starts a call: the phone buttons, Call back in "Just us", and the night
/// check before either rings. `View.callOverlay` makes one for the signed-in app and puts it in
/// the environment, and shows its night question.
@MainActor
@Observable
final class CallStarter {
    /// "It's 02:14 for Robin. Call anyway?"
    nonisolated struct NightPrompt: Equatable, Sendable {
        let partnerName: String
        let localTime: String
    }

    let center: CallCenter
    /// Shows the call full. `View.callOverlay` sets it.
    @ObservationIgnored weak var overlay: CallOverlayModel?
    /// Set while the night question shows.
    var nightPrompt: NightPrompt?
    /// The partner's time zone is being read, so a second tap does nothing.
    private(set) var isChecking = false

    init(center: CallCenter, nightPrompt: NightPrompt? = nil) {
        self.center = center
        self.nightPrompt = nightPrompt
    }

    /// Answers the partner's ringing call, and opens the call screen while any other call is live.
    /// Otherwise asks first when it is night for the partner, then calls.
    func start(partnerName: String, now: @escaping () -> Date = Date.init) {
        if let session = center.session, session.direction == .incoming, session.phase == .ringing {
            overlay?.showFull()
            center.engine.answer()
            return
        }
        guard !center.isInCall else {
            overlay?.showFull()
            return
        }
        guard !isChecking else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            let timeZone = await center.engine.partnerTimeZone()
            let date = now()
            if let timeZone, CallNightCheck.isNight(at: date, in: timeZone) {
                nightPrompt = NightPrompt(
                    partnerName: partnerName, localTime: CallNightCheck.localTime(at: date, in: timeZone))
            } else {
                call()
            }
        }
    }

    /// Call anyway, from the night question.
    func callAtNight() {
        nightPrompt = nil
        call()
    }

    private func call() {
        guard !center.isInCall else { return }
        center.engine.startCall()
    }
}

private func nightTitle(_ prompt: CallStarter.NightPrompt?) -> LocalizedStringResource {
    guard let prompt else { return .callsNightCall }
    return .callsNightTitle(prompt.localTime, prompt.partnerName)
}

extension View {
    /// The night question for `starter`. Call rings, Cancel does nothing.
    func callNightCheck(_ starter: CallStarter?) -> some View {
        alert(
            Text(nightTitle(starter?.nightPrompt)),
            isPresented: Binding(
                get: { starter?.nightPrompt != nil },
                set: { if !$0 { starter?.nightPrompt = nil } }
            )
        ) {
            Button {
                starter?.callAtNight()
            } label: {
                Text(.callsNightCall)
            }
            Button(role: .cancel) {
                starter?.nightPrompt = nil
            } label: {
                Text(.commonCancel)
            }
        }
    }
}
