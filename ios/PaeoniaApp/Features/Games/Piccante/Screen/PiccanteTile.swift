import SwiftUI

/// Illustrated pieces share a camera and cup size. Overlays describe the game state.
struct PiccanteTile: View {
    let variety: PiccanteVariety
    let isEaten: Bool
    let chilis: [BoardGamePlayerInfo]
    let isOwnChili: Bool
    let isHiding: Bool
    let isOpening: Bool
    let isBurned: Bool
    let isSelected: Bool
    let isPartnerSelected: Bool
    let isPending: Bool
    var sniff: PiccanteSniff?
    var lastBiter: BoardGamePlayerInfo?
    var burnShake = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    private var isLifted: Bool { isSelected || isPartnerSelected }

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack {
                if isLifted || isBurned || lastBiter != nil {
                    if differentiateWithoutColor {
                        silhouetteOutline(color: .paeoniaTextPrimary, width: 4)
                    }
                    silhouetteOutline(color: selectionColor, width: 2.5)
                }
                chocolate
            }
                .padding(2)
                .compositingGroup()
                .shadow(color: .paeoniaInkGold.opacity(isOpening ? 0.7 : 0), radius: 10)
                .shadow(color: .black.opacity(isLifted && !isEaten ? 0.45 : 0), radius: 5, y: 6)
                .offset(y: isLifted ? -4 : 0)
                .scaleEffect(isLifted ? 1.06 : 1)
                .overlay(alignment: .topTrailing) { stateSymbol(side: side) }
                .overlay(alignment: .bottom) { chiliMarkers(side: side) }
                .overlay(alignment: .topLeading) { sniffMarker(side: side) }
                .overlay(alignment: .bottomTrailing) {
                    if let lastBiter {
                        BoardGameAvatar(player: lastBiter, size: max(20, side * 0.32))
                    }
                }
                .phaseAnimator([0.0, -4, 4, -3, 3, 0], trigger: burnShake) { content, offset in
                    content.offset(x: isBurned && !reduceMotion ? offset : 0)
                } animation: { _ in .linear(duration: 0.045) }
                .overlay {
                    if isPending { ProgressView().tint(.paeoniaTextPrimary) }
                }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
    }

    private var artwork: ImageResource {
        if isBurned { return .gameHubPiccanteBurned }
        if isEaten && !isOpening { return .gameHubPiccanteWrapper }
        return variety.artwork
    }

    private var chocolate: some View {
        Image(artwork)
            .resizable()
            .accessibilityHidden(true)
            .scaledToFit()
            .saturation(isEaten && !isBurned ? 0.2 : 1)
            .opacity(isEaten && !isBurned ? 0.5 : 1)
            .scaleEffect(isEaten && !isBurned ? 0.9 : 1)
    }

    private var selectionColor: Color {
        isBurned ? .paeoniaWarning : isSelected ? .boardGameMine : .boardGamePartner
    }

    private func silhouetteOutline(color: Color, width: CGFloat) -> some View {
        // Offset the alpha mask evenly so round and heart-shaped cups keep their own edges.
        ZStack {
            ForEach(0..<8) { step in
                let angle = Double(step) * .pi / 4
                Image(artwork)
                    .renderingMode(.template)
                    .resizable()
                    .accessibilityHidden(true)
                    .scaledToFit()
                    .foregroundStyle(color)
                    .offset(x: cos(angle) * width, y: sin(angle) * width)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func stateSymbol(side: CGFloat) -> some View {
        if isBurned {
            Image(systemName: "flame.fill")
                .font(.system(size: max(11, side * 0.19), weight: .bold))
                .foregroundStyle(.paeoniaTextInverse)
                .frame(width: max(22, side * 0.32), height: max(22, side * 0.32))
                .background(Color.paeoniaWarning, in: Circle())
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func chiliMarkers(side: CGFloat) -> some View {
        if !chilis.isEmpty {
            HStack(spacing: 3) {
                ForEach(chilis.indices, id: \.self) { index in
                    BoardGameAvatar(player: chilis[index], size: max(22, side * 0.32))
                }
            }
            .overlay(alignment: .top) {
                if !isBurned { chiliMarker(side: side).offset(y: -side * 0.62) }
            }
        } else if isOwnChili || isHiding {
            chiliMarker(side: side).offset(y: -side * 0.08)
        }
    }

    @ViewBuilder private func sniffMarker(side: CGFloat) -> some View {
        if let sniff, !isEaten {
            Image(systemName: sniff.hasChili ? "flame.fill" : "checkmark")
                .font(.system(size: max(11, side * 0.18), weight: .bold))
                .foregroundStyle(.paeoniaTextPrimary)
                .frame(width: max(22, side * 0.32), height: max(22, side * 0.32))
                .background(sniff.hasChili ? Color.paeoniaWarning : .paeoniaSurfacePrimary, in: Circle())
                .overlay { Circle().strokeBorder(Color.paeoniaTextPrimary, lineWidth: 1.5) }
                .shadow(color: .paeoniaWarning.opacity(sniff.hasChili ? 0.8 : 0), radius: 9)
                .accessibilityHidden(true)
        }
    }

    private func chiliMarker(side: CGFloat) -> some View {
        Image(.gameHubPiccanteChili)
            .resizable()
            .accessibilityHidden(true)
            .scaledToFit()
            .frame(width: max(22, side * 0.36), height: max(22, side * 0.33))
            .rotationEffect(.degrees(-15))
    }
}
