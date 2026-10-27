import Foundation
import Testing
@testable import MijiaCore

@Suite struct HouseDogTests {
    @Test func templatesShareActionsButNotEncodedArt() throws {
        let cat = try HousePetTests.rig(), dog = try HousePetTests.rig("dog-short")
        #expect(dog.species == "dog" && dog.id == "dog-short")
        #expect(dog.patterns == cat.patterns)
        #expect(HousePetRig.supported[dog.id]?.patterns == dog.patterns)
        #expect(HousePetRig.supported[cat.id]?.patterns == cat.patterns)
        #expect(Set(dog.actions.keys) == Set(["idle", "walk", "sit", "groom", "lookup", "sleep", "stretch", "jump"]))
        #expect(dog.frameCount == 68 && dog.cellPx == 2)
        for (name, action) in dog.actions {
            #expect(action.fps == cat.actions[name]?.fps && action.loop == cat.actions[name]?.loop)
            #expect(action.frames == cat.actions[name]?.frames)
            for (facing, source) in [("SW", "SE"), ("NW", "NE")] {
                let mirrored = dog.frame(action: name, facing: facing, elapsed: 0.5)
                #expect(mirrored.mirrored)
                #expect(mirrored.index == dog.frame(action: name, facing: source, elapsed: 0.5).index)
            }
        }
        for pattern in dog.patterns {
            let catData = try Data(contentsOf: HousePetTests.directory.appendingPathComponent(cat.sheets[pattern]!))
            let dogData = try Data(contentsOf: HousePetTests.directory.appendingPathComponent(dog.sheets[pattern]!))
            #expect(catData != dogData)
        }
        for phase in cat.lighting.keys {
            #expect(dog.lighting[phase]?.mul == cat.lighting[phase]?.mul)
            #expect(dog.lighting[phase]?.add == cat.lighting[phase]?.add)
        }
    }

    @Test func validatesSpeciesRigPairsAndRoundTrips() throws {
        var file = HouseFile()
        for (index, species) in ["cat", "dog"].enumerated() {
            for pattern in HousePetRig.allPatterns {
                let pet = HousePet(id: "p_123\(index)", species: species, rig: species + "-short", pattern: pattern)
                try file.setPet(home: "home", pet: pet)
                let decoded = try JSONDecoder().decode(HousePet.self, from: JSONEncoder().encode(pet))
                #expect(decoded == pet)
            }
        }
        for (species, rig, pattern) in [("dog", "cat-short", "solid"), ("cat", "dog-short", "solid"),
                                         ("fox", "dog-short", "solid"), ("dog", "dog-long", "solid"),
                                         ("dog", "dog-short", "missing")] {
            #expect(throws: HousePetError.self) {
                try file.setPet(home: "home", pet: .init(id: "p_5678", species: species, rig: rig, pattern: pattern))
            }
        }
    }

    @Test(arguments: ["cat", "dog", "unknown"]) func photoResultSelectsTemplate(_ species: String) throws {
        let result = try HousePetPhoto.analyze(rgba: [180, 120, 65, 255], width: 1, height: 1, species: species)
        let pet = result.pet(name: "Preview")
        #expect(pet.species == (species == "dog" ? "dog" : "cat"))
        #expect(pet.rig == pet.species + "-short")
        #expect(pet.palette == result.palette && pet.pattern == result.pattern && pet.name == "Preview")
        var file = HouseFile(); try file.setPet(home: "home", pet: pet)
    }

    @Test func speciesBedsAndGenericFallback() throws {
        let catalog = try HousePetTests.catalog(), source = try HousePetTests.spots()
        let items = try HouseDecorCatalog.load(from: HousePetTests.root.appendingPathComponent("Sources/MijiaBarApp/Resources/House/decor/decor-catalog.json"))
        #expect(items.items.first { $0.id == "cat_bed" }?.species == ["cat"])
        #expect(items.items.first { $0.id == "cat_tree" }?.species == ["cat"])
        #expect(items.items.first { $0.id == "dog_bed" }?.species == ["dog"])
        #expect(items.items.first { $0.id == "food_bowl" }?.species == nil)
        let layout = [HouseLayoutCell(room: "room", module: "living", col: 0, row: 0, level: 0)]
        let art = try #require(catalog.modules["living"])
        let baseWorld = HousePetWorld(layout: layout, catalog: catalog, spots: source)
        let first = try #require(baseWorld.nodes.first)
        let last = try #require(baseWorld.nodes.reversed().first { !baseWorld.path(from: first.id, to: $0.id).isEmpty && first.point.distance(to: $0.point) > 5 * baseWorld.cellSize })
        let placements: [HouseDecorPlacement] = zip(["cat_bed", "dog_bed"], [first, last]).map { pair in
            let (item, node) = pair
            let horizontal = Double(art.tip[0]) + Double(node.u - node.v) * 20
            let vertical = Double(art.tip[1]) + Double(node.u + node.v + 1) * 8.25
            return HouseDecorPlacement(room: "room", slot: item, item: item, module: "living",
                                       at: [horizontal, vertical], surface: "floor", source: .user)
        }
        let cat = HousePet(id: "p_100001"), dog = HousePet(id: "p_100002", species: "dog", rig: "dog-short")
        let behavior = HousePetBehavior(rig: try HousePetTests.rig(), rigs: ["dog-short": try HousePetTests.rig("dog-short")])
        let date = Date(timeIntervalSince1970: 1792270000)
        for decor in [placements, Array(placements.prefix(1)), []] {
            let world = HousePetWorld(layout: layout, catalog: catalog, spots: source, decor: decor, items: items)
            let context = HousePetContext(night: true, petIDs: [cat.id, dog.id], changedAt: date)
            let poses = behavior.poses([cat, dog], world: world, context: context, at: date.addingTimeInterval(3600))
            for pet in [cat, dog] {
                let pose = try #require(poses[pet.id])
                #expect(pose.action == "sleep" && pose.visible)
                if let bed = world.spots.first(where: { $0.species == [pet.species] }) {
                    #expect(pose.point == bed.point)
                } else {
                    let generic = world.spots.filter { $0.species == nil && ["sleep", "perch"].contains($0.kind) }
                    let single = HousePetContext(night: true, petIDs: [pet.id], changedAt: date)
                    let resting = behavior.pose(pet, world: world, context: single, at: date.addingTimeInterval(3600))
                    #expect(generic.contains { $0.point == resting.point })
                    #expect(generic.contains { $0.point == pose.point } || world.nodes.contains { $0.point == pose.point })
                }
                #expect(!world.spots.contains { !$0.accepts(pet) && $0.point == pose.point })
            }
        }
        let world = HousePetWorld(layout: layout, catalog: catalog, spots: source, decor: placements, items: items)
        let context = HousePetContext(night: true, petIDs: [cat.id], changedAt: date)
        var changed = cat; changed.species = "dog"; changed.rig = "dog-short"
        let catPose = behavior.pose(cat, world: world, context: context, at: date.addingTimeInterval(3600))
        let dogPose = behavior.pose(changed, world: world, context: context, at: date.addingTimeInterval(3600))
        #expect(catPose.point != dogPose.point)
    }
}
