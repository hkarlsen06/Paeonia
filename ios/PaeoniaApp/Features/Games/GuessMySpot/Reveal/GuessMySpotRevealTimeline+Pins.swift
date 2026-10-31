import CoreGraphics

/// The reveal's pins and line as the timeline has them now.
extension GuessMySpotRevealTimeline {
    /// The pin the reveal starts from stands and pulses, and the other one drops.
    /// A held guess has only its own pin.
    func pins(guess: GuessMySpotMap.Pin, spot: GuessMySpotMap.Pin?, isSender: Bool) -> [GuessMySpotMap.Pin] {
        guard let spot else { return [standing(guess)] }
        let (first, second) = isSender ? (spot, guess) : (guess, spot)
        return dropped ? [standing(first), dropping(second)] : [standing(first)]
    }

    /// A far guess draws quiet and dashed from the start, as in Consensio.
    func line(from: GuessMySpotCoordinate, to: GuessMySpotCoordinate, isFar: Bool) -> GuessMySpotMap.Line? {
        guard lineProgress > 0 else { return nil }
        return GuessMySpotMap.Line(from: from, to: to, progress: lineProgress, isFar: isFar)
    }

    private func standing(_ pin: GuessMySpotMap.Pin) -> GuessMySpotMap.Pin {
        var pin = pin
        pin.glow = glow
        pin.scale = pulseScale * verdictScale
        return pin
    }

    private func dropping(_ pin: GuessMySpotMap.Pin) -> GuessMySpotMap.Pin {
        var pin = pin
        pin.glow = glow
        pin.scale = verdictScale
        pin.lift = dropLift
        pin.ring = ring
        return pin
    }
}
