import SwiftUI

struct MemoryCardPhotoLayout: Layout {
    enum TitleStyle: Int, CaseIterable {
        case large, medium, compact

        var font: Font {
            switch self {
            case .large: PaeoniaTypography.largeTitle
            case .medium: PaeoniaTypography.heroTitle
            case .compact: PaeoniaTypography.title
            }
        }
    }

    let hasNote: Bool

    private static let noteIndex = TitleStyle.allCases.count
    private static let minimumNoteIndex = noteIndex + 1
    private static let preferredNoteIndex = minimumNoteIndex + 1
    private static let dateIndex = preferredNoteIndex + 1
    private static let photoIndex = dateIndex + 1
    private let columnGap = PaeoniaSpacing.space16
    private let contentGap = PaeoniaSpacing.space8

    private struct Plan {
        let size: CGSize
        let titleIndex: Int
        let titleFrame: CGRect
        let noteFrame: CGRect
        let dateFrame: CGRect
        let photoFrame: CGRect
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        plan(width: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let plan = plan(width: bounds.width, subviews: subviews)
        for index in subviews.indices {
            let frame: CGRect
            switch index {
            case plan.titleIndex: frame = plan.titleFrame
            case Self.noteIndex: frame = plan.noteFrame
            case Self.dateIndex: frame = plan.dateFrame
            case Self.photoIndex: frame = plan.photoFrame
            default: frame = .zero
            }
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func plan(width: CGFloat, subviews: Subviews) -> Plan {
        let photoWidth = max(0, width - columnGap) * 0.46
        let textWidth = max(0, width - columnGap - photoWidth)
        let textProposal = ProposedViewSize(width: textWidth, height: nil)
        let dateSize = subviews[Self.dateIndex].sizeThatFits(
            ProposedViewSize(width: photoWidth, height: nil)
        )
        let height = dateSize.height + contentGap + photoWidth
        let idealNoteHeight = subviews[Self.noteIndex].sizeThatFits(textProposal).height
        let minimumNoteHeight = hasNote ? min(
            idealNoteHeight,
            subviews[Self.minimumNoteIndex].sizeThatFits(textProposal).height
        ) : 0
        let preferredNoteHeight = hasNote ? min(
            idealNoteHeight,
            subviews[Self.preferredNoteIndex].sizeThatFits(textProposal).height
        ) : 0
        let noteReservation = hasNote ? contentGap + preferredNoteHeight : 0
        let titleIndex = TitleStyle.allCases.first { style in
            subviews[style.rawValue].sizeThatFits(textProposal).height + noteReservation <= height
        }?.rawValue ?? TitleStyle.compact.rawValue
        let titleHeight = min(subviews[titleIndex].sizeThatFits(textProposal).height, height)
        let availableNoteHeight = max(0, height - titleHeight - contentGap)
        let noteHeight = hasNote && availableNoteHeight >= minimumNoteHeight ? availableNoteHeight : 0
        let photoX = width - photoWidth
        return Plan(
            size: CGSize(width: width, height: height),
            titleIndex: titleIndex,
            titleFrame: CGRect(x: 0, y: 0, width: textWidth, height: titleHeight),
            noteFrame: CGRect(x: 0, y: titleHeight + contentGap, width: textWidth, height: noteHeight),
            dateFrame: CGRect(x: width - dateSize.width, y: 0, width: dateSize.width, height: dateSize.height),
            photoFrame: CGRect(x: photoX, y: dateSize.height + contentGap, width: photoWidth, height: photoWidth)
        )
    }
}
