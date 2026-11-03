import SwiftUI

/// Illustrated pieces share a camera and cup size. Overlays describe the game state.
struct PiccanteTile: View {
    let tile: Int
    let isEaten: Bool
    let chilis: [BoardGamePlayerInfo]
    let isOwnChili: Bool
    let isHiding: Bool
    let isOpening: Bool
    let isBurned: Bool
    let isSelected: Bool
    let isPartnerSelected: Bool
    let isPending: Bool

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    private var isLifted: Bool { isSelected || isPartnerSelected }

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            ZStack {
                if isLifted || isBurned {
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
                .shadow(color: .black.opacity(isLifted ? 0.45 : 0), radius: 5, y: 6)
                .offset(y: isLifted ? -4 : 0)
                .scaleEffect(isLifted ? 1.06 : 1)
                .overlay(alignment: .topTrailing) { stateSymbol(side: side) }
                .overlay(alignment: .bottom) { chiliMarkers(side: side) }
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
        switch tile % 3 {
        case 0: return .gameHubPiccanteHeart
        case 1: return .gameHubPiccanteDrizzle
        default: return .gameHubPiccanteNut
        }
    }

    private var chocolate: some View {
        Image(artwork)
            .resizable()
            .accessibilityHidden(true)
            .scaledToFit()
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
                .font(.system(size: max(9, side * 0.15), weight: .bold))
                .foregroundStyle(.paeoniaTextInverse)
                .frame(width: max(16, side * 0.27), height: max(16, side * 0.27))
                .background(Color.paeoniaWarning, in: Circle())
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func chiliMarkers(side: CGFloat) -> some View {
        if !chilis.isEmpty {
            HStack(spacing: 3) {
                ForEach(chilis.indices, id: \.self) { index in
                    BoardGameAvatar(player: chilis[index], size: max(16, side * 0.25))
                }
            }
            .overlay(alignment: .top) {
                if !isBurned { chiliMarker(side: side).offset(y: -side * 0.4) }
            }
        } else if isOwnChili || isHiding {
            chiliMarker(side: side)
        }
    }

    private func chiliMarker(side: CGFloat) -> some View {
        Text(verbatim: "🌶️")
            .font(.system(size: max(18, side * 0.3)))
            .accessibilityHidden(true)
    }
}
