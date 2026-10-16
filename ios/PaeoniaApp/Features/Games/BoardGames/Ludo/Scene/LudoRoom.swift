import Metal
import RealityKit
import UIKit

/// The room round the board: a cherry wood table in the evening with a linen runner, a
/// mug of hot chocolate for each of us, a plate of croissants and a small plant. The
/// table stands on a wool rug on a parquet floor, with two chairs at its sides and a
/// painted chest of drawers against the far wall.
/// The plant, the plate and the croissants are CC0 models from Poly Haven
/// (potted_plant_04, carved_wooden_plate, croissant), kept as geometry only
/// (`LudoPlant.usdz`, `LudoPlate.usdz`, `LudoCroissant.usdz`). Their materials are made
/// here from small pictures in the asset catalog. The mugs are made in code.
@MainActor
enum LudoRoom {
    /// The first room built, kept so the next board copies it instead of loading it again.
    private static var prototype: Entity?

    /// Builds the room. A prop that fails to load is left out.
    static func build() async -> Entity {
        if let prototype { return prototype.clone(recursive: true) }
        let root = Entity()
        root.name = "ludoRoom"
        await addTable(to: root)
        await addLegs(to: root)
        await addFloor(to: root)
        await addWalls(to: root)
        await addFurniture(to: root)
        await addRunner(to: root)
        await addMugs(to: root)
        await addProps(to: root)
        prototype = root.clone(recursive: true)
        return root
    }

    /// Height of the table's top, at the bottom of the slab.
    static var tableTop: Float { -LudoSceneStyle.slabThickness - LudoSceneStyle.homeGlowLift }

    // MARK: Table

    /// The top is one plane with the wood across it. The edge under it is a box with the
    /// same wood, its grain scaled to the edge's height so it is not squeezed.
    private static func addTable(to root: Entity) async {
        let style = LudoSceneStyle.self
        var top = await wood()
        var edge = top
        top.textureCoordinateTransform = .init(
            scale: SIMD2(style.tableWidth / style.tableGrainCells, style.tableDepth / style.tableGrainCells)
        )
        edge.textureCoordinateTransform = .init(
            scale: SIMD2(style.tableWidth / style.tableGrainCells, style.tableThickness / style.tableGrainCells)
        )
        let plane = MeshResource.generatePlane(
            width: style.tableWidth,
            depth: style.tableDepth,
            cornerRadius: style.tableCornerRadius
        )
        let surface = ModelEntity(mesh: plane, materials: [top])
        surface.position.y = tableTop
        surface.name = "ludoTable"
        root.addChild(surface)

        let side = ModelEntity(
            mesh: .generateBox(
                width: style.tableWidth,
                height: style.tableThickness,
                depth: style.tableDepth,
                cornerRadius: style.tableCornerRadius
            ),
            materials: [edge]
        )
        // Its top lies a hair under the plane, so the two never flicker through each other.
        side.position.y = tableTop - style.tableThickness / 2 - 0.005
        side.name = "ludoTableEdge"
        root.addChild(side)
    }

    /// Four square legs down to the floor, with the grain running down them.
    private static func addLegs(to root: Entity) async {
        let style = LudoSceneStyle.self
        var grain = await wood()
        let legHeight = style.tableHeight - style.tableThickness
        grain.textureCoordinateTransform = .init(
            scale: SIMD2(style.tableLegSide / style.tableGrainCells, legHeight / style.tableGrainCells)
        )
        let leg = MeshResource.generateBox(
            width: style.tableLegSide,
            height: legHeight,
            depth: style.tableLegSide,
            cornerRadius: 0.2
        )
        let reach = SIMD2(style.tableWidth, style.tableDepth) / 2 - style.tableLegInset - style.tableLegSide / 2
        for corner in [SIMD2<Float>(-1, -1), SIMD2(-1, 1), SIMD2(1, -1), SIMD2(1, 1)] {
            let spot = corner * reach
            let post = ModelEntity(mesh: leg, materials: [grain])
            post.position = SIMD3(spot.x, tableTop - style.tableThickness - legHeight / 2, spot.y)
            post.name = "ludoTableLeg"
            root.addChild(post)
        }
    }

    /// The cherry wood of the table, repeating instead of stretching. The room's color
    /// when its picture is missing.
    private static func wood() async -> PhysicallyBasedMaterial {
        let style = LudoSceneStyle.self
        var material = PhysicallyBasedMaterial()
        if let color = await texture("LudoTableColor", .color) {
            material.baseColor = .init(tint: .white, texture: tiled(color))
        } else {
            material.baseColor = .init(tint: style.color(style.roomHex))
        }
        if let normal = await texture("LudoTableNormal", .normal) {
            material.normal = .init(texture: tiled(normal))
        }
        if let roughness = await texture("LudoTableRoughness", .scalar) {
            material.roughness = .init(scale: style.tableRoughness, texture: tiled(roughness))
        }
        return material
    }

    /// A linen runner along the table, under the board and the mugs, hanging over both ends.
    private static func addRunner(to root: Entity) async {
        let style = LudoSceneStyle.self
        let data = LudoMeshGeometry.runner()
        var descriptor = LudoSceneBuilder.descriptor(data, name: "ludoRunner")
        // The weave's bumps need to know which way is across: always along x.
        descriptor.tangents = MeshBuffers.Tangents(Array(repeating: SIMD3(1, 0, 0), count: data.positions.count))
        guard let mesh = try? MeshResource.generate(from: [descriptor]) else { return }
        let length = style.tableDepth + 2 * style.runnerDrop
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: style.color(style.runnerHex))
        if let detail = await texture("LudoRunnerDetail", .raw) {
            material.baseColor = .init(tint: style.color(style.runnerHex), texture: tiled(detail))
        }
        if let normal = await texture("LudoRunnerNormal", .normal) {
            material.normal = .init(texture: tiled(normal))
        }
        if let roughness = await texture("LudoRunnerRoughness", .scalar) {
            material.roughness = .init(scale: 1, texture: tiled(roughness))
        }
        material.textureCoordinateTransform = .init(
            scale: SIMD2(style.runnerWidth / style.runnerGrainCells, length / style.runnerGrainCells)
        )
        let runner = ModelEntity(mesh: mesh, materials: [material])
        runner.position.y = tableTop + style.runnerLift
        runner.name = "ludoRunner"
        root.addChild(runner)
    }

    // MARK: Props

    private static func addProps(to root: Entity) async {
        let style = LudoSceneStyle.self
        if let plant = await prop("LudoPlant") {
            place(plant, at: style.plantPosition, turn: 0.8, on: root)
        }
        if let plate = await prop("LudoPlate") {
            place(plate, at: style.platePosition, turn: 0.3, on: root)
        }
        // Two croissants side by side on the plate, the second turned a little.
        guard let croissant = await prop("LudoCroissant") else { return }
        let turn: Float = 0.35
        let across = SIMD2(sin(turn), cos(turn)) * style.croissantSpacing
        let lift = style.croissantLift
        place(croissant.clone(recursive: true), at: style.platePosition + across, turn: turn, lift: lift, on: root)
        place(croissant, at: style.platePosition - across, turn: turn + 0.25, lift: lift, on: root)
    }

    /// Stands a prop on the table at (x, z) in cells, `lift` above it, turned round the
    /// vertical axis.
    static func place(_ prop: Entity, at spot: SIMD2<Float>, turn: Float, lift: Float = 0, on root: Entity) {
        let holder = Entity()
        holder.position = SIMD3(spot.x, tableTop + LudoSceneStyle.runnerLift + lift, spot.y)
        holder.orientation = simd_quatf(angle: turn, axis: SIMD3(0, 1, 0))
        holder.addChild(prop)
        root.addChild(holder)
    }

    /// Loads a prop's geometry, stands it up (the models are Z-up), scales it from meters to
    /// cells and gives it its material, made from the pictures named after it. Nil when
    /// the file is missing.
    static func prop(_ name: String, shade: CGFloat = 1) async -> Entity? {
        guard let model = try? await Entity(named: name) else { return nil }
        let material = await propMaterial(name, shade: shade)
        func paint(_ entity: Entity) {
            if let model = entity as? ModelEntity { model.model?.materials = [material] }
            for child in entity.children { paint(child) }
        }
        paint(model)
        model.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(1, 0, 0))
        model.scale = SIMD3(repeating: LudoSceneStyle.cellsPerMeter)
        return model
    }

    /// `shade` darkens the color, 1 leaving it as it is.
    private static func propMaterial(_ name: String, shade: CGFloat) async -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        if let color = await texture(name + "Color", .color) {
            material.baseColor = .init(tint: UIColor(white: shade, alpha: 1), texture: .init(color))
        }
        if let normal = await texture(name + "Normal", .normal) {
            material.normal = .init(texture: .init(normal))
        }
        if let roughness = await texture(name + "Roughness", .scalar) {
            material.roughness = .init(scale: 1, texture: .init(roughness))
        }
        material.metallic = .init(floatLiteral: 0)
        return material
    }

    static func texture(_ name: String, _ semantic: TextureResource.Semantic) async -> TextureResource? {
        guard let image = UIImage(named: name)?.cgImage else { return nil }
        return try? await TextureResource(image: image, options: .init(semantic: semantic))
    }

    /// A texture that repeats across the table instead of stretching once over it.
    static func tiled(_ texture: TextureResource) -> MaterialParameters.Texture {
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
