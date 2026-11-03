import SwiftUI

enum PiccanteNoteColors {
    static let paper = Color.paeoniaInkGold.mix(with: .paeoniaTextPrimary, by: 0.82)
    static let quietPaper = paper.mix(with: .paeoniaInkLavender, by: 0.28)
    static let ink = Color.paeoniaTextInverse
}

struct PiccanteResultNotes: View {
    let game: RemotePiccanteGame
    let userID: UUID?
    let partnerName: String

    var body: some View {
        VStack(spacing: PaeoniaSpacing.space16) {
            if Set(game.chilis.map(\.tile)).count == 1 {
                Label {
                    Text(.piccanteSameOne)
                } icon: {
                    Image(systemName: "heart.fill")
                }
                .font(PaeoniaTypography.title)
                .foregroundStyle(Color.paeoniaInkGold)
            }
            ForEach(orderedChilis.indices, id: \.self) { index in
                let chili = orderedChilis[index]
                if let note = chili.note {
                    notePaper(note, chili: chili)
                }
            }
        }
    }

    private func notePaper(_ note: String, chili: PiccanteChili) -> some View {
        let isWinning = chili.userID == game.winnerUserID
        return VStack(alignment: .leading, spacing: PaeoniaSpacing.space12) {
            Text(heading(for: chili))
                .font(PaeoniaTypography.caption.weight(.semibold))
            Text(verbatim: note)
                .font(isWinning ? PaeoniaTypography.collectionTitle : Font.system(.body, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(signature(for: chili))
                .font(PaeoniaTypography.caption)
        }
        .foregroundStyle(PiccanteNoteColors.ink)
        .multilineTextAlignment(.leading)
        .padding(isWinning ? PaeoniaSpacing.space20 : PaeoniaSpacing.space16)
        .padding(.trailing, PaeoniaSpacing.space8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paeoniaCardSurface(
            in: RoundedRectangle(cornerRadius: PaeoniaRadius.radius12),
            fill: isWinning ? PiccanteNoteColors.paper : PiccanteNoteColors.quietPaper
        )
        .overlay(alignment: .topTrailing) {
            PiccantePaperFold()
                .fill(PiccanteNoteColors.ink.opacity(0.12))
                .frame(width: 22, height: 22)
                .padding(1)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, isWinning ? 0 : PaeoniaSpacing.space8)
        .accessibilityElement(children: .combine)
    }

    private func heading(for chili: PiccanteChili) -> LocalizedStringResource {
        if chili.userID == game.winnerUserID {
            return chili.userID == userID ? .piccanteNoteForPartner(partnerName) : .piccanteNoteForYou
        }
        return chili.userID == userID ? .piccanteNoteIfYouWon : .piccanteWouldHaveGot
    }

    private func signature(for chili: PiccanteChili) -> LocalizedStringResource {
        guard chili.userID == userID else { return .piccanteNoteFrom(partnerName) }
        return chili.userID == game.winnerUserID ? .piccanteNoteFromYou : .piccanteNoteWrittenByYou(partnerName)
    }

    private var orderedChilis: [PiccanteChili] {
        game.chilis.sorted { $0.userID == game.winnerUserID && $1.userID != game.winnerUserID }
    }
}

nonisolated private struct PiccantePaperFold: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
