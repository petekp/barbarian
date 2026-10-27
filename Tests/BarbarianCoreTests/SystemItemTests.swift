import Testing
import BarbarianCore

@Test func aControlCenterItemIsKnownByItsAccessibilityIdentifierOrWindowTitle() {
    #expect(SystemItem(accessibilityIdentifier: "com.apple.menuextra.wifi", title: nil, bundleIdentifier: nil) == .wifi)
    #expect(SystemItem(accessibilityIdentifier: nil, title: "WiFi", bundleIdentifier: nil) == .wifi)
    #expect(SystemItem(accessibilityIdentifier: nil, title: "FocusModes", bundleIdentifier: nil) == .focus)
}

@Test func spotlightIsKnownByItsApp() {
    #expect(SystemItem(accessibilityIdentifier: nil, title: nil, bundleIdentifier: "com.apple.Spotlight") == .spotlight)
}

@Test func anotherAppsItemIsNotASystemItem() {
    #expect(SystemItem(accessibilityIdentifier: nil, title: "Item-0", bundleIdentifier: "com.getdropbox.dropbox") == nil)
}
