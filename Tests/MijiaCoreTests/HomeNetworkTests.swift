import Testing
@testable import MijiaCore

@Suite struct HomeNetworkTests {
    let ifs: [(UInt32, UInt32)] = [(HomeNetwork.v4("10.0.5.20")!, 0xFFFF_FF00)]
    @Test func inSubnet() { #expect(HomeNetwork.evaluate(deviceIPs: ["10.0.5.99"], interfaces: ifs) == true) }
    @Test func away() { #expect(HomeNetwork.evaluate(deviceIPs: ["10.0.6.99"], interfaces: ifs) == false) }
    @Test func unknown() { #expect(HomeNetwork.evaluate(deviceIPs: [], interfaces: ifs) == nil) }
}
