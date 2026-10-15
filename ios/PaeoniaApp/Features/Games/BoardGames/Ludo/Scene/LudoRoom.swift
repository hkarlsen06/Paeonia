import Metal
import RealityKit
import UIKit

/// The room round the board: a cherry wood table in the evening with a linen runner, a
/// lit candle in a brass holder and a pot of tea with two cups, fading into the dark. The
/// props are CC0 models from Poly Haven (tea_set_01, brass_candleholders), kept as geometry
/// only (`LudoTeaSet.usdz`, `LudoBrassCandle.usdz`). Their materials are made here from
/// small pictures in the asset catalog.
@MainActor
final class LudoRoom {
    private(set) var root = Entity()
    private var candleLight: Entity?
    private var flame: Entity?

    /// The first room built, kept so the next board copies it instead of loading it again.
    private static var prototype: Entity?

    /// Builds the room. A prop that fails to load is left out.
    static func build() async -> LudoRoom {
        let room = LudoRoom()
        if let prototype {
            room.root = prototype.clone(recursive: true)
        } else {
            room.root.name = "ludoRoom"
            await room.addTable()
            await room.addProps()
            prototype = room.root.clone(recursive: true)
        }
        room.flame = room.root.findEntity(named: "ludoFlame")
        room.candleLight = room.root.findEntity(named: "ludoCandleLight")
        return room
    }

    /// The candle flickers a little each frame. Reduce Motion holds it still.
    func update(clock: Double, reduceMotion: Bool) {
        guard let candleLight, let flame, var light = candleLight.components[PointLightComponent.self] else { return }
        let flicker: Float = reduceMotion ? 0 : Self.flicker(clock)
        light.intensity = LudoSceneStyle.candleLumens * (1 + LudoSceneStyle.candleFlicker * flicker)
        candleLight.components.set(light)
        flame.scale = SIMD3(1 - flicker * 0.04, 1 + flicker * 0.1, 1 - flicker * 0.04)
    }

    /// A soft wandering value from -1 to 1, a sum of slow waves that never lines up.
    private static func flicker(_ clock: Double) -> Float {
        let value = sin(clock * 7.3) * 0.5 + sin(clock * 13.1 + 1.7) * 0.3 + sin(clock * 23.9 + 0.4) * 0.2
        return Float(value)
    }

    // MARK: Table

    private func addTable() async {
        let side = LudoSceneStyle.tableSize
        let top = -LudoSceneStyle.slabThickness
        var material = PhysicallyBasedMaterial()
        let repeats = side / LudoSceneStyle.tableGrainCells
        if let color = await Self.texture("LudoTableColor", .color) {
            material.baseColor = .init(tint: .white, texture: Self.tiled(color))
        } else {
            material.baseColor = .init(tint: LudoSceneStyle.color(LudoSceneStyle.roomHex))
        }
        if let normal = await Self.texture("LudoTableNormal", .normal) {
            material.normal = .init(texture: Self.tiled(normal))
        }
        if let roughness = await Self.texture("LudoTableRoughness", .scalar) {
            material.roughness = .init(scale: LudoSceneStyle.tableRoughness, texture: Self.tiled(roughness))
        }
        material.textureCoordinateTransform = .init(scale: SIMD2(repeating: repeats))
        let table = ModelEntity(mesh: .generatePlane(width: side, depth: side), materials: [material])
        table.position.y = top - LudoSceneStyle.homeGlowLift
        table.name = "ludoTable"
        root.addChild(table)

        await addRunner()

        // The table and the runner fade into the dark room away from the board.
        guard let image = Self.darkness(),
              let texture = try? await TextureResource(image: image, options: .init(semantic: .color))
        else { return }
        var shade = UnlitMaterial()
        shade.color = .init(tint: .white, texture: .init(texture))
        shade.blending = .transparent(opacity: .init(floatLiteral: 1))
        let darkness = ModelEntity(mesh: .generatePlane(width: side, depth: side), materials: [shade])
        darkness.position.y = top + LudoSceneStyle.runnerLift + 0.01
        darkness.components.set(DynamicLightShadowComponent(castsShadow: false))
        darkness.name = "ludoRoomDarkness"
        root.addChild(darkness)
    }

    /// A long linen runner across the table, from the far side to the near side, under
    /// the board and the props.
    private func addRunner() async {
        let style = LudoSceneStyle.self
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: style.color(style.runnerHex))
        if let detail = await Self.texture("LudoRunnerDetail", .raw) {
            material.baseColor = .init(tint: style.color(style.runnerHex), texture: Self.tiled(detail))
        }
        if let normal = await Self.texture("LudoRunnerNormal", .normal) {
            material.normal = .init(texture: Self.tiled(normal))
        }
        if let roughness = await Self.texture("LudoRunnerRoughness", .scalar) {
            material.roughness = .init(scale: 1, texture: Self.tiled(roughness))
        }
        material.textureCoordinateTransform = .init(
            scale: SIMD2(style.runnerWidth / style.runnerGrainCells, style.tableSize / style.runnerGrainCells)
        )
        let mesh = MeshResource.generatePlane(width: style.runnerWidth, depth: style.tableSize)
        let runner = ModelEntity(mesh: mesh, materials: [material])
        runner.position.y = -style.slabThickness + style.runnerLift
        runner.name = "ludoRunner"
        root.addChild(runner)
    }

    /// The room's color with the darkness in its alpha: clear round the board, thick far away.
    private static func darkness() -> CGImage? {
        let side = 256
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: side,
                  height: side,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        let room = LudoSceneStyle.color(LudoSceneStyle.roomHex)
        let colors = [room.withAlphaComponent(0).cgColor, room.cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return nil }
        let middle = CGPoint(x: side / 2, y: side / 2)
        let perCell = CGFloat(side) / CGFloat(LudoSceneStyle.tableSize)
        context.drawRadialGradient(
            gradient,
            startCenter: middle,
            startRadius: CGFloat(LudoSceneStyle.roomLitRadius) * perCell,
            endCenter: middle,
            endRadius: CGFloat(LudoSceneStyle.roomDarkRadius) * perCell,
            options: [.drawsAfterEndLocation]
        )
        return context.makeImage()
    }

    // MARK: Props

    private func addProps() async {
        let style = LudoSceneStyle.self
        if let candlestick = await Self.prop("LudoBrassCandle", material: "LudoBrassCandle", metallic: true) {
            place(candlestick, at: style.candlePosition, turn: 0.6)
            addFlame(on: candlestick)
        }
        guard let set = await Self.prop("LudoTeaSet", material: "LudoTeaSet", metallic: true) else { return }
        // The set comes laid out like a catalog photo. Take the teapot and two cups on saucers.
        let pieces = [
            TeaPiece(names: ["teapot_01", "teapot_01_lid"], spot: style.teapotPosition, turn: -0.7),
            TeaPiece(names: ["saucer_circular_04", "cup_small_01"], spot: style.partnerCupPosition, turn: 2.2),
            TeaPiece(names: ["saucer_circular_03", "cup_small_02"], spot: style.myCupPosition, turn: -0.4)
        ]
        for piece in pieces {
            let group = Entity()
            for name in piece.names {
                guard let part = set.findEntity(named: "tea_set_01_" + name) else { continue }
                // Each part sits at the set's origin. A cup rests a little up in its saucer, full of tea.
                let isCup = name.hasPrefix("cup")
                part.position = SIMD3(0, 0, isCup ? style.cupInSaucer : 0)
                if isCup, let tea = Self.tea() { part.addChild(tea) }
                group.addChild(part)
            }
            group.orientation = set.orientation
            group.scale = set.scale
            place(group, at: piece.spot, turn: piece.turn)
        }
    }

    /// Parts of the tea set that stand together, where on the table, and how turned.
    private struct TeaPiece {
        let names: [String]
        let spot: SIMD2<Float>
        let turn: Float
    }

    /// The surface of the tea in a cup, in the cup model's own meters, where up is +z.
    private static func tea() -> ModelEntity? {
        let style = LudoSceneStyle.self
        let data = LudoMeshGeometry.disc(radius: style.teaRadius, segments: 32, flipsVertically: false)
        guard let mesh = try? MeshResource.generate(from: [LudoSceneBuilder.descriptor(data, name: "ludoTea")]) else {
            return nil
        }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: style.color(style.teaHex))
        material.roughness = .init(floatLiteral: style.teaRoughness)
        material.metallic = .init(floatLiteral: 0)
        let surface = ModelEntity(mesh: mesh, materials: [material])
        // The disc faces +y. A quarter turn round x faces it up the model's +z.
        surface.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        surface.position = SIMD3(0, 0, style.teaLevel)
        return surface
    }

    /// Stands a prop on the table at (x, z) in cells, turned round the vertical axis.
    private func place(_ prop: Entity, at spot: SIMD2<Float>, turn: Float) {
        let holder = Entity()
        // The props stand on the runner.
        holder.position = SIMD3(spot.x, -LudoSceneStyle.slabThickness + LudoSceneStyle.runnerLift, spot.y)
        holder.orientation = simd_quatf(angle: turn, axis: SIMD3(0, 1, 0))
        holder.addChild(prop)
        root.addChild(holder)
    }

    /// A small flame on top of the candle, with the warm light it gives.
    private func addFlame(on candlestick: Entity) {
        let bounds = candlestick.visualBounds(relativeTo: candlestick.parent)
        let wick = SIMD3(bounds.center.x, bounds.max.y, bounds.center.z)
        guard let mesh = try? MeshResource.generate(
            from: [LudoSceneBuilder.descriptor(LudoMeshGeometry.flame(), name: "ludoFlame")]
        ) else { return }
        var inner = UnlitMaterial(color: LudoSceneStyle.color(LudoSceneStyle.flameCoreHex))
        inner.faceCulling = .none
        let flame = ModelEntity(mesh: mesh, materials: [inner])
        flame.components.set(DynamicLightShadowComponent(castsShadow: false))
        var outer = UnlitMaterial(color: LudoSceneStyle.color(LudoSceneStyle.flameHex))
        outer.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        outer.faceCulling = .none
        let halo = ModelEntity(mesh: mesh, materials: [outer])
        halo.scale = SIMD3(1.5, 1.25, 1.5)
        halo.components.set(DynamicLightShadowComponent(castsShadow: false))
        let holder = Entity()
        holder.name = "ludoFlame"
        holder.position = wick + SIMD3(0, LudoSceneStyle.flameLift, 0)
        holder.addChild(flame)
        holder.addChild(halo)
        candlestick.parent?.addChild(holder)

        let light = PointLight()
        light.light = PointLightComponent(
            color: LudoSceneStyle.color(LudoSceneStyle.flameHex),
            intensity: LudoSceneStyle.candleLumens,
            attenuationRadius: LudoSceneStyle.candleReach
        )
        light.name = "ludoCandleLight"
        light.position = holder.position + SIMD3(0, LudoSceneStyle.flameHeight * 0.5, 0)
        candlestick.parent?.addChild(light)
    }

    /// Loads a prop's geometry, stands it up (the models are Z-up), scales it from meters to
    /// cells and gives it its material. Nil when the file is missing.
    private static func prop(_ file: String, material name: String, metallic: Bool = false) async -> Entity? {
        guard let model = try? await Entity(named: file) else { return nil }
        let material = await propMaterial(name, metallic: metallic)
        func paint(_ entity: Entity) {
            if let model = entity as? ModelEntity { model.model?.materials = [material] }
            for child in entity.children { paint(child) }
        }
        paint(model)
        model.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        model.scale = SIMD3(repeating: LudoSceneStyle.cellsPerMeter)
        return model
    }

    private static func propMaterial(_ name: String, metallic: Bool) async -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let color = await texture(name + "Color", .color) {
            material.baseColor = .init(tint: .white, texture: .init(color))
        }
        if let normal = await texture(name + "Normal", .normal) {
            material.normal = .init(texture: .init(normal))
        }
        if let roughness = await texture(name + "Roughness", .scalar) {
            material.roughness = .init(scale: 1, texture: .init(roughness))
        }
        if metallic, let metal = await texture(name + "Metallic", .scalar) {
            material.metallic = .init(scale: 1, texture: .init(metal))
        }
        return material
    }

    private static func texture(_ name: String, _ semantic: TextureResource.Semantic) async -> TextureResource? {
        guard let image = UIImage(named: name)?.cgImage else { return nil }
        return try? await TextureResource(image: image, options: .init(semantic: semantic))
    }

    /// A texture that repeats across the table instead of stretching once over it.
    private static func tiled(_ texture: TextureResource) -> MaterialParameters.Texture {
        let sampler = MTLSamplerDescriptor()
        sampler.sAddressMode = .repeat
        sampler.tAddressMode = .repeat
        sampler.minFilter = .linear
        sampler.magFilter = .linear
        sampler.mipFilter = .linear
        sampler.maxAnisotropy = 8
        return MaterialParameters.Texture(texture, sampler: .init(sampler))
    }
}
