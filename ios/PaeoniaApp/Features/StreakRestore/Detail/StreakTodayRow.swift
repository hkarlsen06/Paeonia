import SwiftUI

/// Today on the streak sheet: both partners' photos inside one ring, and who still
/// has to do something before the day ends. Each half of the ring belongs to one
/// partner. It turns solid once that partner has done something, and until then
/// it burns down toward the deadline like a fuse.
struct StreakTodayRow: View {
    let streak: CoupleStreak
    let people: StreakPeople

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let avatarSize: CGFloat = 36
    private static let ringGap: CGFloat = 3
    private static let ringWidth: CGFloat = 2.5
    /// A full fuse is a whole day.
    private static let fuseLength: TimeInterval = 86_400

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let today = streak.today(at: timeline.date)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: PaeoniaSpacing.space8))
                : AnyLayout(HStackLayout(spacing: PaeoniaSpacing.space12))
            layout {
                ring(today, now: timeline.date)
                    .accessibilityHidden(true)
                lines(today, now: timeline.date)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .animation(reduceMotion ? nil : PaeoniaMotion.stateChange, value: today)
        }
    }

    private func ring(_ today: StreakToday, now: Date) -> some View {
        let fuse = today.deadline.map { min(max($0.timeIntervalSince(now) / Self.fuseLength, 0), 1) } ?? 0
        let bothDone = today.ownDone && today.partnerDone
        return HStack(spacing: Self.ringGap) {
            avatar(people.currentName, people.currentPhotoAssetID, tint: .paeoniaPartnerOne, done: today.ownDone)
            avatar(people.partnerName, people.partnerPhotoAssetID, tint: .paeoniaPartnerTwo, done: today.partnerDone)
        }
        .padding(Self.ringGap + Self.ringWidth)
        .background {
            ZStack {
                ringHalf(.leading, done: today.ownDone, tint: .paeoniaPartnerOne, fuse: fuse)
                ringHalf(.trailing, done: today.partnerDone, tint: .paeoniaPartnerTwo, fuse: fuse)
            }
            .padding(Self.ringWidth / 2)
            .shadow(color: .paeoniaAccentPrimary.opacity(bothDone ? 0.6 : 0), radius: 6)
        }
    }

    @ViewBuilder
    private func ringHalf(_ side: StreakRingHalf.Side, done: Bool, tint: Color, fuse: Double) -> some View {
        let half = StreakRingHalf(side: side)
        if done {
            half.stroke(tint, lineWidth: Self.ringWidth)
        } else {
            ZStack {
                half.stroke(.paeoniaBorder, lineWidth: Self.ringWidth)
                if fuse > 0 {
                    half.trim(from: 0, to: fuse)
                        .stroke(.paeoniaAccentPrimary, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                }
            }
        }
    }

    private func avatar(_ name: String, _ photoAssetID: UUID?, tint: Color, done: Bool) -> some View {
        PaeoniaProfilePhotoAvatar(mediaAssetID: photoAssetID, name: name, tint: tint, size: Self.avatarSize)
            .saturation(done ? 1 : 0.3)
            .opacity(done ? 1 : 0.55)
    }

    private func lines(_ today: StreakToday, now: Date) -> some View {
        VStack(alignment: .leading, spacing: PaeoniaSpacing.space2) {
            Text(headline(today))
                .font(PaeoniaTypography.bodyEmphasis)
                .foregroundStyle(.paeoniaTextPrimary)

            if let deadline = today.deadline {
                HStack {
                    Text(.streakDetailTimeLeft)
                    Text(timerInterval: now...deadline, countsDown: true, showsHours: true)
                        .monospacedDigit()
                        .fixedSize()
                }
                .font(PaeoniaTypography.caption)
                .foregroundStyle(.paeoniaTextSecondary)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func headline(_ today: StreakToday) -> LocalizedStringResource {
        if today.isResting { return .streakTogetherResting }
        switch (today.ownDone, today.partnerDone) {
        case (true, true): return .streakTodayBothDone
        case (true, false): return .streakTodayWaitingForPartner(people.partnerName)
        case (false, true): return .streakTodayYourTurn
        case (false, false): return .streakTodayNeitherDone
        }
    }
}

/// One partner's half of the capsule around both photos. It runs from the top
/// centre round its own end to the bottom centre, so a trimmed half shrinks back
/// toward the top.
nonisolated struct StreakRingHalf: Shape {
    enum Side { case leading, trailing }

    let side: Side

    func path(in rect: CGRect) -> Path {
        let radius = rect.height / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        switch side {
        case .leading:
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.midY), radius: radius,
                startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true
            )
        case .trailing:
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.midY), radius: radius,
                startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false
            )
        }
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

#if DEBUG
#Preview {
    var streak = CoupleStreak.none
    streak.currentCount = 12
    streak.currentUserContributedToday = true
    streak.endsAt = .now.addingTimeInterval(7 * 3_600)
    return StreakTodayRow(
        streak: streak,
        people: StreakPeople(currentName: "Alex", partnerName: "Robin")
    )
    .padding()
    .background(.paeoniaSurfacePrimary)
    .preferredColorScheme(.dark)
}
#endif
