import SwiftUI

/// Illustrated pieces share a camera and cup size. Overlays describe the game state.
struct PiccanteTile: View {
    let tile: Int
    let bite: Int?
    let chilis: [BoardPieceStyle]
    let isOwnChili: Bool
    let isHiding: Bool
    let isOpening: Bool
    let isBurned: Bool
    let isSelected: Bool
    let isPartnerSelected: Bool
    let isPending: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var isLifted: Bool { isSelected || isPartnerSelected }

    var body: some View {
        GeometryReader { proxy in
            let side = proxy.size.width
            Image(artwork)
                .resizable().accessibilityHidden(true)
                .scaledToFit()
                .padding(2)
                .shadow(color: .paeoniaInkGold.opacity(isOpening ? 0.7 : 0), radius: 10)
                .shadow(color: .black.opacity(isLifted ? 0.5 : 0), radius: 5, y: 6)
                .offset(y: isLifted && !reduceMotion ? -5 : 0)
                .scaleEffect(isLifted && !reduceMotion ? 1.05 : 1)
                .overlay { selectionBorder }
                .overlay(alignment: .topLeading) { biteNumber(side: side) }
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
        if bite != nil && !isOpening { return .gameHubPiccanteBitten }
        switch tile % 3 {
        case 0: return .gameHubPiccanteHeart
        case 1: return .gameHubPiccanteDrizzle
        default: return .gameHubPiccanteNut
        }
    }

    @ViewBuilder private var selectionBorder: some View {
        if isLifted || isBurned {
            RoundedRectangle(cornerRadius: PaeoniaRadius.radius12)
                .strokeBorder(
                    isBurned ? Color.paeoniaWarning : isSelected ? .paeoniaAccentPrimary : .paeoniaInkLavender,
                    lineWidth: 3)
        }
    }

    @ViewBuilder private func biteNumber(side: CGFloat) -> some View {
        if let bite {
            Text(verbatim: "\(bite)")
                .font(.system(size: max(10, side * 0.17), weight: .bold, design: .rounded))
                .foregroundStyle(.paeoniaTextInverse)
                .frame(width: max(16, side * 0.27), height: max(16, side * 0.27))
                .background(.paeoniaTextPrimary, in: Circle())
        }
    }

    @ViewBuilder private func stateSymbol(side: CGFloat) -> some View {
        if isLifted || isBurned {
            Image(systemName: isBurned ? "flame.fill" : isSelected ? "checkmark" : "arrow.up")
                .font(.system(size: max(9, side * 0.15), weight: .bold))
                .foregroundStyle(.paeoniaTextInverse)
                .frame(width: max(16, side * 0.27), height: max(16, side * 0.27))
                .background(isBurned ? Color.paeoniaWarning : .paeoniaTextPrimary, in: Circle())
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func chiliMarkers(side: CGFloat) -> some View {
        if !chilis.isEmpty {
            HStack(spacing: 3) {
                ForEach(chilis.indices, id: \.self) { index in
                    BoardMarkView(style: chilis[index], tint: .paeoniaTextInverse)
                        .frame(width: max(12, side * 0.2), height: max(12, side * 0.2))
                        .padding(2)
                        .background(chilis[index].color, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(3)
            .background(.paeoniaBackgroundSecondary, in: Capsule())
            .overlay(alignment: .top) {
                if !isBurned { chiliMarker(side: side).offset(y: -side * 0.4) }
            }
        } else if isOwnChili || isHiding {
            chiliMarker(side: side)
                .padding(3)
                .background(.paeoniaBackgroundSecondary, in: Circle())
        }
    }

    private func chiliMarker(side: CGFloat) -> some View {
        Text(verbatim: "🌶️")
            .font(.system(size: max(18, side * 0.3)))
            .accessibilityHidden(true)
    }
}
