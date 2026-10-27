import Foundation

enum HouseStylePackArchive {
    static func validate(_ data: Data) throws {
        func number(_ offset: Int, _ count: Int) throws -> Int {
            guard offset >= 0, offset <= data.count - count else { throw HouseStylePackError.badArchive }
            return (0..<count).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
        }
        func word(_ offset: Int) throws -> Int { try number(offset, 2) }
        func long(_ offset: Int) throws -> Int { try number(offset, 4) }
        guard data.count >= 22 else { throw HouseStylePackError.badArchive }
        let end = data.count - 22
        guard try long(end) == 0x06054b50, try word(end + 4) == 0, try word(end + 6) == 0,
              try word(end + 20) == 0 else { throw HouseStylePackError.badArchive }
        let count = try word(end + 10)
        let central = try long(end + 16)
        guard count > 0, count <= 2048, try word(end + 8) == count,
              try central + long(end + 12) == end else { throw HouseStylePackError.badArchive }
        var cursor = central, localEnd = 0, inflated = 0
        var names: Set<String> = []
        var modulePNG = false
        for _ in 0..<count {
            guard try long(cursor) == 0x02014b50 else { throw HouseStylePackError.badArchive }
            let flags = try word(cursor + 8), method = try word(cursor + 10)
            let compressed = try long(cursor + 20), expanded = try long(cursor + 24)
            let nameLength = try word(cursor + 28), extra = try word(cursor + 30), comment = try word(cursor + 32)
            let attributes = try long(cursor + 38), local = try long(cursor + 42)
            guard flags & ~0x806 == 0, [0, 8].contains(method), extra == 0, comment == 0,
                  try word(cursor + 34) == 0, local == localEnd,
                  nameLength > 0, cursor + 46 + nameLength <= end,
                  expanded <= 32_000_000 else { throw HouseStylePackError.badArchive }
            let nameData = data.subdata(in: cursor + 46..<cursor + 46 + nameLength)
            guard let name = String(data: nameData, encoding: .utf8), name.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }),
                  !name.contains("\\"), !name.contains(":"), !name.hasPrefix("/"), !name.split(separator: "/").contains(".."),
                  names.insert(name.lowercased()).inserted else { throw HouseStylePackError.unsafePath }
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            let directory = name == "modules/" || name == "classic/"
            let allowed = name == "manifest.json" || directory ||
                (parts.count == 2 && ["modules", "classic"].contains(String(parts[0])) &&
                 !parts[1].hasPrefix(".") && ["png", "json"].contains((String(parts[1]) as NSString).pathExtension))
            let kind = (attributes >> 16) & 0xf000
            guard allowed, kind == 0 || kind == (directory ? 0x4000 : 0x8000),
                  directory || attributes & 0x10 == 0 else { throw HouseStylePackError.unsafePath }
            if directory && expanded != 0 { throw HouseStylePackError.badArchive }
            guard try long(local) == 0x04034b50, try word(local + 6) == flags, try word(local + 8) == method,
                  try long(local + 14) == long(cursor + 16), try long(local + 18) == compressed,
                  try long(local + 22) == expanded, try word(local + 26) == nameLength, try word(local + 28) == 0,
                  local + 30 + nameLength + compressed <= central else { throw HouseStylePackError.badArchive }
            guard data.subdata(in: local + 30..<local + 30 + nameLength) == nameData else { throw HouseStylePackError.unsafePath }
            localEnd = local + 30 + nameLength + compressed
            inflated += expanded
            guard inflated <= 256_000_000 else { throw HouseStylePackError.badArchive }
            modulePNG = modulePNG || (name.hasPrefix("modules/") && name.hasSuffix(".png") && expanded > 0)
            cursor += 46 + nameLength
        }
        guard cursor == end, localEnd == central, names.contains("manifest.json"), modulePNG else { throw HouseStylePackError.badArchive }
    }
}
