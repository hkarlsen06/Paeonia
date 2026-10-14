import RealityKit
import SwiftUI
import UIKit

/// The satin clay materials of the Ludo scene, made from the numbers in `LudoSceneStyle`.
enum LudoMaterials {
    /// A soft clay finish with a clearcoat for the gloss. The defaults are the board's.
    static func satin(
        _ color: UIColor,
        roughness: Float = LudoSceneStyle.boardRoughness,
        clearcoat: Float = LudoSceneStyle.boardClearcoat,
        showsBothSides: Bool = false
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color)
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: roughness)
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0)
        material.specular = PhysicallyBasedMaterial.Specular(floatLiteral: LudoSceneStyle.specular)
        material.clearcoat = PhysicallyBasedMaterial.Clearcoat(floatLiteral: clearcoat)
        material.clearcoatRoughness = PhysicallyBasedMaterial.ClearcoatRoughness(
            floatLiteral: LudoSceneStyle.clearcoatRoughness
        )
        if LudoSceneStyle.selfFill > 0 {
            material.emissiveColor = .init(color: color.ludoMixed(with: .black, amount: 1 - LudoSceneStyle.selfFill))
            material.emissiveIntensity = 1
        }
        if showsBothSides {
            material.faceCulling = .none
        }
        return material
    }

    /// The same finish, lit from inside. Movable pawns and the winner's home use it.
    static func glowing(
        _ color: UIColor,
        roughness: Float = LudoSceneStyle.boardRoughness,
        clearcoat: Float = LudoSceneStyle.boardClearcoat,
        showsBothSides: Bool = false
    ) -> PhysicallyBasedMaterial {
        var material = satin(color, roughness: roughness, clearcoat: clearcoat, showsBothSides: showsBothSides)
        material.emissiveColor = .init(color: color.ludoLightened(LudoSceneStyle.glowLightening))
        material.emissiveIntensity = LudoSceneStyle.glowIntensity
        return material
    }

    /// The pawn finish: glossier than the board.
    static func pawn(_ color: UIColor, glowing isGlowing: Bool) -> PhysicallyBasedMaterial {
        let roughness = LudoSceneStyle.pawnRoughness
        let clearcoat = LudoSceneStyle.pawnClearcoat
        return isGlowing
            ? glowing(color, roughness: roughness, clearcoat: clearcoat, showsBothSides: true)
            : satin(color, roughness: roughness, clearcoat: clearcoat, showsBothSides: true)
    }

    /// The satin finish with a picture on it, such as the mark on top of a pawn.
    static func picture(_ texture: TextureResource) -> PhysicallyBasedMaterial {
        var material = satin(
            .white,
            roughness: LudoSceneStyle.pawnRoughness,
            clearcoat: LudoSceneStyle.pawnClearcoat,
            showsBothSides: true
        )
        material.baseColor = .init(tint: .white, texture: .init(texture))
        material.emissiveColor = .init(color: .black)
        return material
    }

    /// A flat picture with a see-through background, laid on a tile.
    static func decal(_ texture: TextureResource) -> PhysicallyBasedMaterial {
        var material = satin(.white, roughness: LudoSceneStyle.decalRoughness, clearcoat: 0, showsBothSides: true)
        material.baseColor = .init(tint: .white, texture: .init(texture))
        material.emissiveColor = .init(color: .black)
        material.blending = .transparent(opacity: PhysicallyBasedMaterial.Opacity(floatLiteral: 1))
        return material
    }
}

/// The picture on the flat top of a pawn: the owner's mark in blush on a darker
/// disc of the pawn's color.
@MainActor
enum LudoMarkPicture {
    static func image(style: BoardPieceStyle, pawnColor: UIColor) -> CGImage? {
        let side = CGFloat(LudoSceneStyle.markTextureSide)
        let background = Color(uiColor: pawnColor.ludoDarkened(1 - LudoSceneStyle.markBackgroundShade))
        let content = ZStack {
            Rectangle().fill(background)
            BoardMarkView(style: style, tint: Color(uiColor: LudoSceneStyle.color(LudoSceneStyle.markInkHex)))
                .frame(width: side * LudoSceneStyle.markScale, height: side * LudoSceneStyle.markScale)
        }
        .frame(width: side, height: side)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return renderer.cgImage
    }

    static func texture(style: BoardPieceStyle, pawnColor: UIColor) async -> TextureResource? {
        guard let image = image(style: style, pawnColor: pawnColor) else { return nil }
        return try? await TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }
}

/// The background of the scene. It is a picture of a sky over a ground that is
/// the screen's own color, so the board seems to sit on the screen. The sky is
/// pink on one side and lavender on the other, and it lights the pieces softly,
/// so the glossy pawns and the die pick up both colors.
@MainActor
enum LudoBackdrop {
    static func environment() async -> EnvironmentResource? {
        guard let image = skyImage() else { return nil }
        return try? await EnvironmentResource(equirectangular: image, withName: nil)
    }

    /// An equirectangular picture: the top half is the sky, the bottom half the ground.
    static func skyImage() -> CGImage? {
        let width = 256
        let height = 128
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let color = skyColor(across: Double(column) / Double(width), down: Double(row) / Double(height / 2))
                let offset = (row * width + column) * 4
                pixels[offset] = UInt8(max(0, min(255, color.x * 255)))
                pixels[offset + 1] = UInt8(max(0, min(255, color.y * 255)))
                pixels[offset + 2] = UInt8(max(0, min(255, color.z * 255)))
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        return provider.flatMap {
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: $0,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        }
    }

    /// The color of the picture at a place. `down` is 0 at the zenith and 1 at the horizon.
    private static func skyColor(across: Double, down: Double) -> SIMD3<Double> {
        let ground = rgb(LudoSceneStyle.groundHex)
        guard down < 1 else { return ground }
        let left = rgb(LudoSceneStyle.mirrorsSky ? LudoSceneStyle.skyRightHex : LudoSceneStyle.skyLeftHex)
        let right = rgb(LudoSceneStyle.mirrorsSky ? LudoSceneStyle.skyLeftHex : LudoSceneStyle.skyRightHex)
        let horizon = mix(left, right, LudoMotion.smooth((across - 0.35) / 0.3))
        let sky = mix(rgb(LudoSceneStyle.skyZenithHex), horizon, LudoMotion.smooth(down))
        return mix(sky, ground, LudoMotion.smooth((down - 0.85) / 0.15))
    }

    private static func rgb(_ hex: UInt32) -> SIMD3<Double> {
        SIMD3(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    private static func mix(_ first: SIMD3<Double>, _ second: SIMD3<Double>, _ amount: Double) -> SIMD3<Double> {
        first + (second - first) * amount
    }
}

/// The peony picture that lies flat on the safe squares.
@MainActor
enum LudoPeonyPicture {
    static func texture() async -> TextureResource? {
        guard let image = UIImage(named: LudoSceneStyle.peonyAsset)?.cgImage else { return nil }
        return try? await TextureResource(image: image, withName: nil, options: .init(semantic: .color))
    }
}
