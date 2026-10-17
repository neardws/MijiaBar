import Foundation
import Metal

/// SPM 可执行文件没有 App Bundle 的 default.metallib，需从资源编译或加载 metallib。
enum HouseMetalLibrary {
    static func load(device: MTLDevice) -> Result<MTLLibrary, String> {
        if let lib = device.makeDefaultLibrary() {
            return .success(lib)
        }
        if let url = Bundle.module.url(forResource: "HouseMetal", withExtension: "metallib"),
           let lib = try? device.makeLibrary(URL: url) {
            return .success(lib)
        }
        guard let metalURL = Bundle.module.url(forResource: "HouseMetal", withExtension: "metal") else {
            return .failure("HouseMetal.metal missing from Bundle.module — check Package.swift resources")
        }
        do {
            let source = try String(contentsOf: metalURL, encoding: .utf8)
            let lib = try device.makeLibrary(source: source, options: nil)
            return .success(lib)
        } catch {
            return .failure("makeLibrary(source: HouseMetal.metal) failed: \(error)")
        }
    }
}
