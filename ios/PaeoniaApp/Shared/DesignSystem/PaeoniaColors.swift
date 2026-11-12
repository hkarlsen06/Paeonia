import SwiftUI
import UIKit

// Semantic roles for the single plum theme. PaeoniaShared/PaeoniaPalette.swift
// owns the palette and the app/widget brand roles.

nonisolated extension Color {
    static let paeoniaBackgroundPrimary = PaeoniaBrandColors.background
    static let paeoniaBackgroundSecondary = PaeoniaPalette.plumDeep
    static let paeoniaBackgroundElevated = PaeoniaPalette.plumRaised

    static let paeoniaSurfacePrimary = PaeoniaPalette.plumRaised
    static let paeoniaSurfaceSecondary = PaeoniaPalette.plumSurfaceLow
    static let paeoniaSurfacePressed = PaeoniaPalette.plumPressed
    static let paeoniaSurfaceHighlight = PaeoniaPalette.plumPressed
    static let paeoniaSurfaceDisabled = PaeoniaPalette.plumSurfaceLow
    static let paeoniaBorder = Color("ControlBorder")
    static let paeoniaOutgoingMessage = PaeoniaPalette.outgoingMessage

    static let paeoniaTextPrimary = PaeoniaBrandColors.textPrimary
    static let paeoniaTextSecondary = PaeoniaBrandColors.textSecondary
    static let paeoniaTextTertiary = Color("TextTertiary")
    static let paeoniaTextInverse = PaeoniaPalette.plumDeep

    static let paeoniaAccentPrimary = PaeoniaBrandColors.accent
    static let paeoniaAccentSecondary = PaeoniaPalette.pink
    static let paeoniaBackdropGlow = PaeoniaPalette.lavender
    static let paeoniaPresence = PaeoniaPalette.mint
    static let paeoniaSuccess = PaeoniaPalette.green
    static let paeoniaWarning = PaeoniaPalette.orange
    static let paeoniaError = PaeoniaPalette.coralLight
    static let paeoniaErrorText = PaeoniaPalette.coralLight
    static let paeoniaErrorPressed = PaeoniaPalette.coralBright
    static let paeoniaSyncPending = PaeoniaPalette.orange

    static let paeoniaPartnerOne = PaeoniaPalette.petalLight
    static let paeoniaPartnerTwo = PaeoniaPalette.petalWarm
    static let paeoniaPartnerTwoText = PaeoniaPalette.petalWarmLight
    static let paeoniaMemory = PaeoniaPalette.petalMist
    static let paeoniaWidgetDrawing = PaeoniaPalette.blush
    static let paeoniaInkGold = PaeoniaPalette.gold
    static let paeoniaInkBlue = PaeoniaPalette.blue
    static let paeoniaInkLavender = PaeoniaPalette.lavender

    // The peonies drawn in code, such as the streak sheet's milestone stem.
    static let paeoniaStem = PaeoniaPalette.mint
    static let paeoniaPeonyPetal = PaeoniaPalette.petalWarm
    static let paeoniaPeonyHeart = PaeoniaPalette.petalMist
}

nonisolated extension UIColor {
    static let paeoniaAccentPrimary = UIColor(PaeoniaPalette.petalLight)
    static let paeoniaAccentSecondary = UIColor(PaeoniaPalette.pink)
    static let paeoniaPartnerTwo = UIColor(PaeoniaPalette.petalWarm)
    static let paeoniaSuccess = UIColor(PaeoniaPalette.green)
    static let paeoniaWidgetDrawing = UIColor(PaeoniaPalette.blush)
    static let paeoniaInkGold = UIColor(PaeoniaPalette.gold)
    static let paeoniaInkBlue = UIColor(PaeoniaPalette.blue)
    static let paeoniaInkLavender = UIColor(PaeoniaPalette.lavender)
}

nonisolated extension ShapeStyle where Self == Color {
    static var paeoniaBackgroundPrimary: Color { Color.paeoniaBackgroundPrimary }
    static var paeoniaBackgroundSecondary: Color { Color.paeoniaBackgroundSecondary }
    static var paeoniaBackgroundElevated: Color { Color.paeoniaBackgroundElevated }
    static var paeoniaSurfacePrimary: Color { Color.paeoniaSurfacePrimary }
    static var paeoniaSurfaceSecondary: Color { Color.paeoniaSurfaceSecondary }
    static var paeoniaSurfaceHighlight: Color { Color.paeoniaSurfaceHighlight }
    static var paeoniaBorder: Color { Color.paeoniaBorder }
    static var paeoniaTextPrimary: Color { Color.paeoniaTextPrimary }
    static var paeoniaTextSecondary: Color { Color.paeoniaTextSecondary }
    static var paeoniaTextTertiary: Color { Color.paeoniaTextTertiary }
    static var paeoniaTextInverse: Color { Color.paeoniaTextInverse }
    static var paeoniaAccentPrimary: Color { Color.paeoniaAccentPrimary }
    static var paeoniaAccentSecondary: Color { Color.paeoniaAccentSecondary }
    static var paeoniaPresence: Color { Color.paeoniaPresence }
    static var paeoniaSuccess: Color { Color.paeoniaSuccess }
    static var paeoniaWarning: Color { Color.paeoniaWarning }
    static var paeoniaError: Color { Color.paeoniaError }
    static var paeoniaErrorText: Color { Color.paeoniaErrorText }
    static var paeoniaSyncPending: Color { Color.paeoniaSyncPending }
    static var paeoniaPartnerOne: Color { Color.paeoniaPartnerOne }
    static var paeoniaPartnerTwo: Color { Color.paeoniaPartnerTwo }
    static var paeoniaPartnerTwoText: Color { Color.paeoniaPartnerTwoText }
    static var paeoniaMemory: Color { Color.paeoniaMemory }
    static var paeoniaWidgetDrawing: Color { Color.paeoniaWidgetDrawing }
    static var paeoniaStem: Color { Color.paeoniaStem }
}

extension View {
    /// A screen's background, painted under the keyboard too. Use it on any screen
    /// that can show a keyboard.
    ///
    /// `.background(.paeoniaBackgroundPrimary)` stops at the top of the keyboard's
    /// area. The iOS 26 keyboard draws its rounded panel a little lower, so the black
    /// container behind the screen shows in that gap and beside the corners.
    func paeoniaScreenBackground(_ color: Color = .paeoniaBackgroundPrimary) -> some View {
        background {
            color.ignoresSafeArea()
        }
    }
}
