import SwiftUI

extension Color {
    static let paeoniaBackgroundPrimary = Color(uiColor: .systemBackground)
    static let paeoniaBackgroundSecondary = Color(uiColor: .secondarySystemBackground)
    static let paeoniaBackgroundElevated = Color(uiColor: .tertiarySystemBackground)

    static let paeoniaSurfacePrimary = Color(uiColor: .secondarySystemGroupedBackground)
    static let paeoniaSurfaceSecondary = Color(uiColor: .tertiarySystemGroupedBackground)
    static let paeoniaSurfacePressed = Color(uiColor: .systemFill)
    static let paeoniaSurfaceDisabled = Color(uiColor: .systemGray5)

    static let paeoniaTextPrimary = Color(uiColor: .label)
    static let paeoniaTextSecondary = Color(uiColor: .secondaryLabel)
    static let paeoniaTextTertiary = Color(uiColor: .tertiaryLabel)
    static let paeoniaTextInverse = Color(uiColor: .systemBackground)

    static let paeoniaAccentPrimary = Color.accentColor
    static let paeoniaAccentSecondary = Color(uiColor: .systemIndigo)
    static let paeoniaSuccess = Color(uiColor: .systemGreen)
    static let paeoniaWarning = Color(uiColor: .systemOrange)
    static let paeoniaError = Color(uiColor: .systemRed)
    static let paeoniaSyncPending = Color(uiColor: .systemOrange)
    static let paeoniaSyncError = Color(uiColor: .systemRed)

    static let paeoniaPartnerOne = Color(uiColor: .systemBlue)
    static let paeoniaPartnerTwo = Color(uiColor: .systemPurple)
    static let paeoniaMemory = Color(uiColor: .systemTeal)
    static let paeoniaPrompt = Color(uiColor: .systemPink)
    static let paeoniaWidgetDrawing = Color(uiColor: .label)
}

extension ShapeStyle where Self == Color {
    static var paeoniaBackgroundPrimary: Color { Color.paeoniaBackgroundPrimary }
    static var paeoniaBackgroundSecondary: Color { Color.paeoniaBackgroundSecondary }
    static var paeoniaBackgroundElevated: Color { Color.paeoniaBackgroundElevated }
    static var paeoniaSurfacePrimary: Color { Color.paeoniaSurfacePrimary }
    static var paeoniaSurfaceSecondary: Color { Color.paeoniaSurfaceSecondary }
    static var paeoniaSurfacePressed: Color { Color.paeoniaSurfacePressed }
    static var paeoniaSurfaceDisabled: Color { Color.paeoniaSurfaceDisabled }
    static var paeoniaTextPrimary: Color { Color.paeoniaTextPrimary }
    static var paeoniaTextSecondary: Color { Color.paeoniaTextSecondary }
    static var paeoniaTextTertiary: Color { Color.paeoniaTextTertiary }
    static var paeoniaTextInverse: Color { Color.paeoniaTextInverse }
    static var paeoniaAccentPrimary: Color { Color.paeoniaAccentPrimary }
    static var paeoniaAccentSecondary: Color { Color.paeoniaAccentSecondary }
    static var paeoniaSuccess: Color { Color.paeoniaSuccess }
    static var paeoniaWarning: Color { Color.paeoniaWarning }
    static var paeoniaError: Color { Color.paeoniaError }
    static var paeoniaSyncPending: Color { Color.paeoniaSyncPending }
    static var paeoniaSyncError: Color { Color.paeoniaSyncError }
    static var paeoniaPartnerOne: Color { Color.paeoniaPartnerOne }
    static var paeoniaPartnerTwo: Color { Color.paeoniaPartnerTwo }
    static var paeoniaMemory: Color { Color.paeoniaMemory }
    static var paeoniaPrompt: Color { Color.paeoniaPrompt }
    static var paeoniaWidgetDrawing: Color { Color.paeoniaWidgetDrawing }
}
