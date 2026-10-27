import Foundation
import Testing
import MijiaCore
@testable import MijiaBarApp

@Suite struct HouseFixtureNamesTests {
    @Test func everyFixtureHasLocalizedTitle() throws {
        var ids = Set(HouseModule.allCases.flatMap { HouseCatalog.fixtures($0).map(\.id) })
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for path in ["Sources/MijiaBarApp/Resources/House", "assets/house"] {
            let directory = root.appendingPathComponent(path)
            let files = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
            var tables = 0
            for case let file as URL in files where file.pathExtension == "json" {
                let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                let fixtureIDs = try Self.fixtureIDs(in: json)
                if !fixtureIDs.isEmpty { tables += 1 }
                ids.formUnion(fixtureIDs)
            }
            #expect(tables > 0, "No fixture tables found in \(path)")
        }
        #expect(!ids.isEmpty)
        for id in ids.sorted() {
            let title = HouseFixtureNames.title(id)
            #expect(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "Empty fixture title for \(id) in \(currentLang.rawValue)")
            #expect(title != id, "Unlocalized fixture title for \(id) in \(currentLang.rawValue)")
        }
    }

    @Test func applianceTitlesMatchDeviceNames() {
        #expect(HouseFixtureNames.title("curtain") == L("窗帘位", "Curtain"))
        #expect(HouseFixtureNames.title("fridge") == L("冰箱位", "Fridge"))
        #expect(HouseFixtureNames.title("washer") == L("洗衣机位", "Washer"))
        #expect(HouseFixtureNames.title("water_heater") == L("热水器位", "Water heater"))
        #expect(HouseFixtureNames.title("fan") == L("风扇位", "Fan"))
        #expect(HouseFixtureNames.title("air_purifier") == L("空气净化器位", "Air purifier"))
        #expect(HouseFixtureNames.title("dehumidifier") == L("除湿机位", "Dehumidifier"))
        #expect(HouseFixtureNames.title("heater") == L("取暖器位", "Heater"))
        #expect(HouseFixtureNames.title("humidifier") == L("加湿器位", "Humidifier"))
        #expect(HouseFixtureNames.title("vacuum") == L("扫地机位", "Vacuum"))
    }

    private static func fixtureIDs(in json: Any) throws -> Set<String> {
        var ids = Set<String>()
        if let object = json as? [String: Any] {
            if let lights = object["lights"] {
                for light in try #require(lights as? [[String: Any]]) {
                    ids.insert(try #require(light["id"] as? String))
                }
            }
            for value in object.values { ids.formUnion(try fixtureIDs(in: value)) }
        } else if let array = json as? [Any] {
            for value in array { ids.formUnion(try fixtureIDs(in: value)) }
        }
        return ids
    }
}
