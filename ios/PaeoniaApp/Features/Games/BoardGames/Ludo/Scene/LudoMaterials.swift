import ImageIO
import RealityKit
import SwiftUI
import UIKit

/// The materials of the Ludo scene, made from the numbers in `LudoSceneStyle`: glazed
/// ceramic for the slab and the pieces, and plain for pictures.
enum LudoMaterials {
    /// What the surface is made of.
    enum Finish {
        /// Glazed ceramic: faint clay grain and iron speckle under an uneven gloss.
        case glaze
        /// The same glaze without the grain, for the shapes made in code, which have
        /// no directions for a bump picture to follow.
        case smoothGlaze
        /// One flat color, or a picture laid on it afterwards.
        case plain
    }

    /// A ceramic finish with a clearcoat for the gloss. The defaults are the board's.
    static func satin(
        _ color: UIColor,
        roughness: Float = LudoSceneStyle.boardRoughness,
        clearcoat: Float = LudoSceneStyle.boardClearcoat,
        showsBothSides: Bool = false,
        finish: Finish = .glaze
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
        LudoSurfaces.loaded?.apply(finish, to: &material, color: color, roughness: roughness)
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
        showsBothSides: Bool = false,
        finish: Finish = .glaze
    ) -> PhysicallyBasedMaterial {
        var material = satin(
            color,
            roughness: roughness,
            clearcoat: clearcoat,
            showsBothSides: showsBothSides,
            finish: finish
        )
        material.emissiveColor = .init(color: color.ludoLightened(LudoSceneStyle.glowLightening))
        material.emissiveIntensity = LudoSceneStyle.glowIntensity
        return material
    }

    /// The pawn finish: glossier than the board.
    static func pawn(_ color: UIColor, glowing isGlowing: Bool) -> PhysicallyBasedMaterial {
        let roughness = LudoSceneStyle.pawnRoughness
        let clearcoat = LudoSceneStyle.pawnClearcoat
        return isGlowing
            ? glowing(color, roughness: roughness, clearcoat: clearcoat, showsBothSides: true, finish: .smoothGlaze)
            : satin(color, roughness: roughness, clearcoat: clearcoat, showsBothSides: true, finish: .smoothGlaze)
    }

    /// The satin finish with a picture on it, such as the mark on top of a pawn.
    static func picture(_ texture: TextureResource) -> PhysicallyBasedMaterial {
        var material = satin(
            .white,
            roughness: LudoSceneStyle.pawnRoughness,
            clearcoat: LudoSceneStyle.pawnClearcoat,
            showsBothSides: true,
            finish: .plain
        )
        material.baseColor = .init(tint: .white, texture: .init(texture))
        material.emissiveColor = .init(color: .black)
        return material
    }
}

/// The scanned surface pictures of the glaze (CC0, from ambientCG: Clay005's grain
/// under Porcelain002's gloss), made gray so the players' colors tint them. They load
/// once, before the scene's materials are made.
@MainActor
struct LudoSurfaces {
    let glazeDetail: TextureResource
    let glazeRoughness: TextureResource
    let glazeNormal: TextureResource

    private(set) static var loaded: LudoSurfaces?

    static func load() async {
        guard loaded == nil else { return }
        guard let glazeDetail = await texture("LudoGlazeDetail", .raw),
              let glazeRoughness = await texture("LudoGlazeRoughness", .scalar),
              let glazeNormal = await texture("LudoGlazeNormal", .normal)
        else { return }
        loaded = LudoSurfaces(glazeDetail: glazeDetail, glazeRoughness: glazeRoughness, glazeNormal: glazeNormal)
    }

    private static func texture(_ name: String, _ semantic: TextureResource.Semantic) async -> TextureResource? {
        guard var image = UIImage(named: name)?.cgImage else { return nil }
        // The asset catalog stores a gray picture with one channel, and RealityKit reads
        // one channel as red only. A tint picture must keep all three.
        if semantic == .raw, let color = threeChannels(image) {
            image = color
        }
        return try? await TextureResource(image: image, withName: nil, options: .init(semantic: semantic))
    }

    /// The picture drawn again with red, green and blue channels.
    private static func threeChannels(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Lays the pictures of `finish` on a material. The roughness pictures run from
    /// about half to all of `roughness`, so the gloss is uneven like a real glaze.
    func apply(
        _ finish: LudoMaterials.Finish,
        to material: inout PhysicallyBasedMaterial,
        color: UIColor,
        roughness: Float
    ) {
        switch finish {
        case .glaze, .smoothGlaze:
            material.baseColor = .init(tint: color, texture: .init(glazeDetail))
            material.roughness = .init(scale: roughness, texture: .init(glazeRoughness))
            if finish == .glaze {
                material.normal = .init(texture: .init(glazeNormal))
            }
        case .plain:
            break
        }
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

/// The light around the scene: a photo of a warm living room with a lit fireplace (CC0,
/// Poly Haven's fireplace), touched with pink on the left and lavender on the right over
/// a dark plum floor. It is an OpenEXR picture in the asset catalog, so its lamps keep
/// their brightness.
@MainActor
enum LudoBackdrop {
    /// Loaded once and kept, so the board opens faster the next time.
    private static var loaded: EnvironmentResource?

    static func environment() async -> EnvironmentResource? {
        if let loaded { return loaded }
        guard let data = NSDataAsset(name: "LudoRoomLight")?.data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              var image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        if LudoSceneStyle.mirrorsSky, let mirrored = mirrored(image) {
            image = mirrored
        }
        // The scene shows no sky, so RealityKit can skip making one.
        loaded = try? await EnvironmentResource(equirectangular: image, options: .init())
        return loaded
    }

    /// The picture flipped left to right.
    private static func mirrored(_ image: CGImage) -> CGImage? {
        guard let space = image.colorSpace,
              let context = CGContext(
                  data: nil,
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: image.bitsPerComponent,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: image.bitmapInfo.rawValue
              )
        else { return nil }
        context.translateBy(x: CGFloat(image.width), y: 0)
        context.scaleBy(x: -1, y: 1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
