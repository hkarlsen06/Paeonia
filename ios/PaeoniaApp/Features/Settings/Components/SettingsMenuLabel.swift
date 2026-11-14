import SwiftUI

/// The label of a row on the More tab's menu: the title beside a plum icon tile, and
/// the row's current state in secondary text at the end when it has one. Pushed
/// settings screens draw plain glyphs instead.
struct SettingsMenuLabel: View {
    private let title: Text
    private let systemImage: String
    private let value: Text?

    init(_ title: LocalizedStringResource, systemImage: String, value: Text? = nil) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.value = value
    }

    init(verbatim title: String, systemImage: String, value: Text? = nil) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
        self.value = value
    }

    var body: some View {
        if let value {
            LabeledContent {
                value.foregroundStyle(.paeoniaTextSecondary)
            } label: {
                label
            }
        } else {
            label
        }
    }

    private var label: some View {
        Label {
            title.foregroundStyle(.paeoniaTextPrimary)
        } icon: {
            SettingsMenuIcon(systemName: systemImage)
        }
    }
}

/// A plum SF Symbol on a soft plum tile. Every menu row uses the same colors, since
/// the design guide rules out a color per row.
struct SettingsMenuIcon: View {
    let systemName: String

    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var glyphSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var cornerRadius = PaeoniaRadius.radius8

    var body: some View {
        // Fitted to a box, because a wide symbol such as the game controller at a
        // fixed font size is wider than the tile.
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .frame(width: glyphSize, height: glyphSize)
            .foregroundStyle(.paeoniaAccentPrimary)
            .frame(width: tileSize, height: tileSize)
            .background(
                Color.paeoniaAccentPrimary.opacity(0.16),
                in: .rect(cornerRadius: cornerRadius, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
