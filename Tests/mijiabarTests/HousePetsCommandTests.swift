import Foundation
import Testing
import ImageIO
import MijiaCore
@testable import mijiabar

@Suite struct HousePetsCommandTests {
    @Test func parsesPetFlagsWithoutConsumingNamesAsPositionals() throws {
        #expect(try housePetArguments([]) == ["list"])
        #expect(try housePetArguments(["--json"]) == ["list"])
        #expect(try housePetArguments(["analyze", "/tmp/two words.jpg", "--json"]) == ["analyze", "/tmp/two words.jpg"])
        #expect(try housePetArguments(["analyze", "/tmp/cat.jpg"]) == ["analyze", "/tmp/cat.jpg"])
        #expect(try housePetArguments(["add", "--photo", "/tmp/cat.jpg", "--name", "Two Words", "--palette", "base=#AABBCC"]) == ["add"])
        #expect(try housePetArguments(["add", "--species", "dog", "--rig", "dog-short"]) == ["add"])
        #expect(try housePetArguments(["set", "Mochi", "--enabled", "false", "--room", "auto"]) == ["set", "Mochi"])
        #expect(try housePetArguments(["preview", "p_1234", "--out", "/tmp/pet.png", "--action", "sit", "--phase", "night"]) == ["preview", "p_1234"])
    }
    @Test func rejectsMalformedOrInapplicableFlags() {
        for args in [["add", "--photo"], ["add", "--oops", "yes"], ["set"], ["remove", "one", "two"],
                     ["on", "--photo", "/tmp/a"], ["preview", "one", "--photo", "/tmp/a"], ["set", "one", "--name", "--room"],
                     ["add", "--name", "one", "--name", "two"], ["analyze"], ["analyze", "one", "two"],
                     ["analyze", "cat.jpg", "--home", "h"], ["analyze", "--photo", "cat.jpg"]] {
            #expect(throws: (any Error).self) { try housePetArguments(args) }
        }
    }
    @Test func petToolsAndSchemaAreValidJSON() throws {
        let pets = houseMCPTools.filter { ($0["name"] as? String)?.hasSuffix("house_pets") == true }
        #expect(pets.count == 2)
        #expect(JSONSerialization.isValidJSONObject(pets))
        #expect(JSONSerialization.isValidJSONObject(houseSchema))
        let definitions = try #require(houseSchema["$defs"] as? [String: Any])
        #expect(definitions["pet"] != nil && definitions["petPalette"] != nil)
        let definition = try #require(definitions["pet"] as? [String: Any])
        let fields = try #require(definition["properties"] as? [String: Any])
        #expect((fields["species"] as? [String: [String]])?["enum"] == ["cat", "dog"])
        #expect((fields["rig"] as? [String: [String]])?["enum"] == ["cat-short", "dog-short"])
        let mutation = try #require(pets.first { $0["name"] as? String == "set_house_pets" })
        let input = try #require(mutation["inputSchema"] as? [String: Any])
        let properties = try #require(input["properties"] as? [String: Any])
        #expect((properties["species"] as? [String: [String]])?["enum"] == ["cat", "dog"])
        #expect((properties["pattern"] as? [String: [String]])?["enum"] == HousePetRig.allPatterns)
    }

    @Test func analysisDiagnosticsSerializeAndPrintOnOneLine() throws {
        let result = try HousePetPhoto.analyze(rgba: [128, 128, 128, 255], width: 1, height: 1)
        let analysis = try #require(housePetJSON(result) as? [String: Any])
        let diagnostics = try #require(analysis["diagnostics"] as? [String: Any])
        #expect(Set(diagnostics.keys) == Set(["white", "neutralDark", "warm", "grey", "cream", "striped", "maskCoverage", "whiteBalanceApplied"]))
        #expect(diagnostics["grey"] as? Double == 1)
        #expect(diagnostics["striped"] as? Bool == false)
        #expect(diagnostics["whiteBalanceApplied"] as? Bool == false)
        let text = housePetDiagnosticsText(diagnostics)
        #expect(text.hasPrefix("diagnostics: ") && !text.contains("\n"))
        #expect(text.contains("\"whiteBalanceApplied\":false"))
        let decoded = try JSONDecoder().decode(HousePetPhoto.Diagnostics.self, from: Data(text.dropFirst("diagnostics: ".count).utf8))
        #expect(decoded == result.diagnostics)
    }

    @Test(arguments: ["cat", "dog"]) func previewWritesScaledContactSheetWithoutLaunchingAnApp(_ species: String) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("Sources/MijiaBarApp/Resources/House/pets")
        let rig = try HousePetRig.load(from: directory.appendingPathComponent(species + "-short.json"))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("pet-preview-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: output) }
        let count = try housePetPreview(pet: .init(id: "p_1234", species: species, rig: rig.id), rig: rig, directory: directory, output: output, action: "sit", phase: "night")
        #expect(count == 8)
        let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == rig.columns * rig.frameSize[0] * rig.cellPx)
        #expect(image.height == rig.frameSize[1] * rig.cellPx)
        #expect(throws: HousePetError.self) { try housePetPreview(pet: .init(), rig: rig, directory: directory, output: output, action: "missing") }
    }
}
