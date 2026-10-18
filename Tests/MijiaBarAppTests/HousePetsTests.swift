import Foundation
import CoreGraphics
import Testing
import MijiaCore
@testable import MijiaBarApp

@MainActor @Suite struct HousePetsTests {
    private func rig() throws -> HousePetRig { try #require(HousePetPainter.shared.rig) }
    private func bitmap(_ width: Int = 20, _ height: Int = 20) throws -> CGContext {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: Double(height)); context.scaleBy(x: 1, y: -1)
        return context
    }

    @Test func anchorMirrorAndJumpUseRigMetadata() throws {
        var rig = try rig(); rig.anchor = [1.25, 2.5]; rig.cellPx = 3
        for mirrored in [false, true] {
            let pose = HousePetPose(point: .init(x: 105, y: 81), mirrored: mirrored, jumpLift: 12, module: "living", room: "r")
            let transform = HousePetPainter.transform(rig: rig, pose: pose)
            let anchor = CGPoint(x: rig.anchor[0], y: rig.anchor[1]).applying(transform)
            #expect(anchor.x == 105 && anchor.y == 69)
            let adjacent = CGPoint(x: rig.anchor[0] + 1, y: rig.anchor[1]).applying(transform)
            #expect(adjacent.x == (mirrored ? 102 : 108))
        }
    }

    @Test func painterClipsAndMirrorsActualPixels() throws {
        var rig = try rig(); rig.frameSize = [2, 1]; rig.anchor = [1, 1]; rig.cellPx = 2
        let image = try HousePetRecolor.image(width: 2, height: 1, rgba: [255, 0, 0, 255, 0, 255, 0, 255])
        for mirrored in [false, true] {
            let context = try bitmap()
            let pose = HousePetPose(point: .init(x: 10, y: 10), mirrored: mirrored, module: "living", room: "r")
            HousePetPainter.drawFrame(image, in: context, rig: rig, pose: pose, polygons: [[[10, 0], [20, 0], [20, 20], [10, 20]]])
            let output = try #require(context.makeImage()), bytes = try #require(HousePetPainter.pixels(output))
            for row in 0..<20 {
                for column in 0..<10 { #expect(bytes[(row * 20 + column) * 4 + 3] == 0) }
            }
            let colored = stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0 + 3] > 0 }
            #expect(!colored.isEmpty)
            #expect(colored.allSatisfy { bytes[$0 + (mirrored ? 0 : 1)] == 255 })
        }
        let context = try bitmap()
        HousePetPainter.drawFrame(image, in: context, rig: rig, pose: .init(point: .init(x: 10, y: 10), module: "living", room: "r"), polygons: [])
        let emptyImage = try #require(context.makeImage())
        let bytes = try #require(HousePetPainter.pixels(emptyImage))
        #expect(bytes.allSatisfy { $0 == 0 })
    }

    @Test func framePixelsLandAtAnchorRelativeCanvasCoordinates() throws {
        var rig = try rig(); rig.frameSize = [2, 2]; rig.anchor = [1, 1]; rig.cellPx = 2
        let image = try HousePetRecolor.image(width: 2, height: 2, rgba: [255, 0, 0, 255, 0, 255, 0, 255,
                                                                     0, 0, 255, 255, 255, 255, 0, 255])
        let context = try bitmap()
        HousePetPainter.drawFrame(image, in: context, rig: rig, pose: .init(point: .init(x: 10, y: 10), module: "living", room: "r"),
                                  polygons: [[[0, 0], [20, 0], [20, 20], [0, 20]]])
        let output = try #require(context.makeImage()), bytes = try #require(HousePetPainter.pixels(output))
        func pixel(_ column: Int, _ row: Int) -> [UInt8] { Array(bytes[((row * 20 + column) * 4)..<((row * 20 + column) * 4 + 4)]) }
        #expect(pixel(8, 8) == [255, 0, 0, 255])
        #expect(pixel(10, 8) == [0, 255, 0, 255])
        #expect(pixel(8, 10) == [0, 0, 255, 255])
        #expect(pixel(10, 10) == [255, 255, 0, 255])
        #expect(pixel(7, 8) == [0, 0, 0, 0])
    }

    @Test func ratioIsPerChannelClampedAndHasFailureBoundary() throws {
        #expect(HousePetPainter.ratio(lit: [0.1, 0.4, 0.9], unlit: [0.2, 0.2, 0.1]) == [1, 2, 2.6])
        #expect(HousePetPainter.ratio(lit: [1, 1, 1], unlit: [0, 0.2, 0.3]) == nil)
        #expect(HousePetPainter.ratio(lit: [.nan, 1, 1], unlit: [1, 1, 1]) == nil)
        let bytes: [UInt8] = [100, 80, 60, 255, 31, 20, 18, 100]
        let image = try HousePetRecolor.image(width: 2, height: 1, rgba: bytes)
        let lit = try #require(HousePetPainter.illuminate(image, lighting: .init(mul: [2, 2, 2], add: [0.1, 0.1, 0.1]), shadowMultiplier: [0.5, 0.5, 0.5]))
        let data = try #require(lit.dataProvider?.data), pointer = try #require(CFDataGetBytePtr(data))
        #expect(pointer[0] == 226 && pointer[1] == 186 && pointer[2] == 146)
        #expect(pointer[4] == 16 && pointer[5] == 10 && pointer[6] == 9 && pointer[7] == 100)
    }

    @Test func appResourcesResolveAllSheetsWithoutLaunchingUI() throws {
        let rig = try rig(), directory = try #require(HousePetPainter.shared.directory)
        #expect(HousePetPainter.shared.spots != nil)
        for pattern in rig.patterns {
            let pet = HousePet(pattern: pattern)
            let frames = try HousePetPainter.shared.cache.frames(pet: pet, rig: rig, directory: directory, phase: "day")
            #expect(frames.count == rig.frameCount)
            #expect(frames[0].width == rig.frameSize[0] && frames[0].height == rig.frameSize[1])
        }
    }

    @Test func sampledNightLightingAndFallbackFollowRigConstants() throws {
        let painter = HousePetPainter.shared, rig = try rig(), directory = try #require(painter.directory)
        let pet = HousePet(id: "p_1234")
        let pose = HousePetPose(point: .init(x: 0, y: 0), module: "living", room: "r")
        let day = try painter.cache.frames(pet: pet, rig: rig, directory: directory, phase: "day")[0]
        let dark = try HousePetRecolor.image(width: 1, height: 1, rgba: [50, 50, 50, 255])
        let light = try HousePetRecolor.image(width: 1, height: 1, rgba: [100, 100, 100, 255])
        let night = try #require(rig.lighting["night"])
        let expected = try #require(HousePetPainter.illuminate(day, lighting: .init(mul: night.mul.map { $0 * 2 }), shadowMultiplier: night.mul))
        let actual = try #require(painter.frame(pet: pet, pose: pose, night: true, lit: true, unlitImage: dark, litImage: light))
        #expect(actual.dataProvider?.data as Data? == expected.dataProvider?.data as Data?)
        let fallback = try #require(painter.frame(pet: pet, pose: pose, night: true, lit: true, unlitImage: nil, litImage: nil))
        let nightLit = try #require(rig.lighting["nightLit"])
        let expectedFallback = try #require(HousePetPainter.illuminate(day, lighting: nightLit, shadowMultiplier: night.mul))
        #expect(fallback.dataProvider?.data as Data? == expectedFallback.dataProvider?.data as Data?)
    }

    @Test func editorAddRemoveUndoAndThreePetLimit() throws {
        let model = AppModel(mock: true), home = model.houseHomeKey
        let pets = HousePetDemo.pets
        for pet in pets { #expect(model.houseSavePet(pet, label: "add")) }
        #expect(!model.houseSavePet(HousePet(id: "p_4444"), label: "overflow"))
        model.houseChangePet(pets[0].id) { $0.deleted = true }
        #expect(model.house.homes[home]?.pets?[pets[0].id]?.deleted == true)
        let removedAt = try #require(model.house.homes[home]?.pets?[pets[0].id]?.updatedAt)
        model.houseUndoStep(redo: false)
        #expect(model.house.homes[home]?.pets?[pets[0].id]?.deleted == false)
        #expect(try #require(model.house.homes[home]?.pets?[pets[0].id]?.updatedAt) >= removedAt)
        model.houseUndoStep(redo: true)
        #expect(model.house.homes[home]?.pets?[pets[0].id]?.deleted == true)
        model.houseUndoStep(redo: false)
        model.houseEdit("disable") { $0.setPetPrefs(home: home, enabled: false) }
        model.houseUndoStep(redo: false)
        #expect(model.house.homes[home]?.petPrefs?.enabled == true)
        model.houseChangePet(pets[0].id) { $0.name = "changed"; $0.palette.eye = "#112233"; $0.homeRoom = "r"; $0.enabled = false }
        model.houseUndoStep(redo: false)
        #expect(model.house.homes[home]?.pets?[pets[0].id]?.name == pets[0].name)
        #expect(model.house.homes[home]?.pets?[pets[0].id]?.enabled == true)
    }

    @Test func undoDoesNotResurrectFourthPetAfterIndependentAddition() throws {
        var file = HouseFile()
        for pet in HousePetDemo.pets { try file.setPet(home: "h", pet: pet) }
        let before = file
        var pet = HousePetDemo.pets[0]; pet.deleted = true; try file.setPet(home: "h", pet: pet)
        var stack = HouseUndoStack(); stack.record(HouseEdit.diff(label: "remove", home: "h", before: before, after: file))
        try file.setPet(home: "h", pet: HousePet(id: "p_4444"))
        #expect(stack.undo(&file) == .stale)
        #expect(file.homes["h"]?.pets?.values.filter { !$0.deleted }.count == 3)
    }

    @Test func composedWorldMatchesCanvasAndEmbedIsRestOnly() throws {
        let model = AppModel(mock: true); model.addHouseFixtureDemo()
        let layout = HousePetDemo.layout(model: model)
        var config = HomeHouse(); config.pets = Dictionary(uniqueKeysWithValues: HousePetDemo.pets.map { ($0.id, $0) })
        config.decorPrefs = .init(seasonal: false)
        for style in ["cozy-wood", "japanese", "modern"] {
            let source = try #require(HouseModuleAssets.composedScene(layout: layout, phase: .day, style: style, config: config))
            let session = try #require(HousePetSceneSession(source: source, layout: layout, style: style, config: config, rooms: model.houseRooms))
            #expect(!session.world.nodes.isEmpty)
            for node in session.world.nodes {
                #expect(node.point.x >= 0 && node.point.x < source.artSize.width)
                #expect(node.point.y >= 0 && node.point.y < source.artSize.height)
            }
            let state = HousePetsLayer.state(rooms: model.houseRooms, phase: .day, config: config, restOnly: HouseListEmbed.petsRestOnly)
            #expect(state.restOnly)
            let behavior = try #require(HousePetPainter.shared.behavior)
            for pet in HousePetDemo.pets {
                for tick in 0..<24 {
                    let pose = behavior.pose(pet, world: session.world, context: state, at: Date(timeIntervalSince1970: 1800000000 + Double(tick) * 300))
                    #expect(["idle", "sit", "sleep"].contains(pose.action))
                }
            }
        }
    }

    @Test func classicPetVisibilityDoesNotChangeRoomGeometry() throws {
        var config = HomeHouse(); let pet = HousePet(id: "p_1234"); config.pets = [pet.id: pet]
        let visible = try #require(HouseSceneSource.make(layout: nil, phase: .day, config: config))
        config.petPrefs = .init(enabled: false)
        config.pets?[pet.id]?.enabled = false
        let hidden = try #require(HouseSceneSource.make(layout: nil, phase: .day, config: config))
        #expect(visible.byRoom && hidden.byRoom)
        #expect(visible.artSize == hidden.artSize)
        #expect(visible.layout == hidden.layout)
        #expect(visible.scene.origin == hidden.scene.origin)
    }

    @Test func everyInjectedActionPaintsInEachStyleAndHonorsVisibility() throws {
        let rig = try rig(), pet = HousePet(id: "p_1234", pattern: "tabbyWhite")
        let layout = [HouseLayoutCell(room: "room", module: "living", col: 0, row: 0, level: 0)]
        for style in ["cozy-wood", "japanese", "modern"] {
            let source = try #require(HouseModuleAssets.composedScene(layout: layout, phase: .day, style: style))
            let session = try #require(HousePetSceneSession(source: source, layout: layout, style: style, config: HomeHouse(), rooms: []))
            for action in rig.actions.keys.sorted() {
                let pose = try #require(HousePetDemo.pose(world: session.world, rig: rig, module: "living", action: action))
                for enabled in [false, true] {
                    let context = try bitmap(Int(source.artSize.width), Int(source.artSize.height))
                    let state = HousePetContext(rooms: session.world.rooms, enabled: enabled)
                    HousePetPainter.shared.draw(in: context, pets: [pet], world: session.world, scene: source.scene,
                                                context: state, date: .distantPast, unlit: session.unlit, lit: session.lit, poses: [pet.id: pose])
                    let output = try #require(context.makeImage()), bytes = try #require(HousePetPainter.pixels(output))
                    let painted = stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 }
                    #expect(painted == enabled, "\(style) \(action)")
                }
            }
        }
    }
}
