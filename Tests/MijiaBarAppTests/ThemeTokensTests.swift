import SwiftUI
import Testing
@testable import MijiaBarApp

struct ThemeTokensTests {
    @Test func documentedRadii() {
        #expect(Theme.Radius.xs == 7)
        #expect(Theme.Radius.sm == 9)
        #expect(Theme.Radius.md == 12)
        #expect(Theme.Radius.lg == 14)
        #expect(Theme.Radius.xl == 20)
        #expect(Theme.Radius.card == 26)
    }

    @Test func documentedTypeSizes() {
        #expect(Theme.TypeSize.micro == 10)
        #expect(Theme.TypeSize.caption == 11)
        #expect(Theme.TypeSize.body == 12)
        #expect(Theme.TypeSize.callout == 13)
        #expect(Theme.TypeSize.title == 15)
    }

    @Test func concentricCorners() {
        #expect(Theme.Radius.inset(Theme.Radius.card, by: 18) == 8)
        #expect(Theme.Radius.inset(Theme.Radius.lg, by: 4) == 10)
        #expect(Theme.Radius.inset(Theme.Radius.sm, by: 0) == Theme.Radius.sm)
        #expect(Theme.Radius.inset(Theme.Radius.md, by: 12) == 0)
        #expect(Theme.Radius.inset(Theme.Radius.xs, by: 18) == 0)
        #expect(Theme.Radius.inset(0, by: 1) == 0)
    }
}

struct FocusChromeTests {
    @Test(arguments: [false, true], [false, true])
    func visibility(focused: Bool, forced: Bool) {
        #expect(FocusChrome.visible(focused: focused, forced: forced, enabled: true) == (focused || forced))
        #expect(!FocusChrome.visible(focused: focused, forced: forced, enabled: false))
    }

    @Test func staticRingGeometry() {
        #expect(FocusChrome.lineWidth == 2)
        #expect(FocusChrome.outset == 3)
        #expect(FocusChrome.outset > FocusChrome.lineWidth / 2)
        #expect(!EnvironmentValues().forceFocusChrome)
    }

    @MainActor @Test func snapshotEntryCompilesWithoutRunning() {
        let entry: (String) -> Void = Snapshot.uiPolish(dir:)
        _ = entry
    }
}
