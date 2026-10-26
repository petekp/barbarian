import Testing
@testable import BarbarianCore

@Test func aControlCenterItemIsKnownByItsAccessibilityIdentifierOrWindowTitle() {
    #expect(SystemItemSymbols.symbolName(accessibilityIdentifier: "com.apple.menuextra.wifi", title: nil, bundleIdentifier: nil) == "wifi")
    #expect(SystemItemSymbols.symbolName(accessibilityIdentifier: nil, title: "WiFi", bundleIdentifier: nil) == "wifi")
    #expect(SystemItemSymbols.symbolName(accessibilityIdentifier: nil, title: "FocusModes", bundleIdentifier: nil) == "moon.fill")
}

@Test func spotlightIsKnownByItsApp() {
    #expect(SystemItemSymbols.symbolName(accessibilityIdentifier: nil, title: nil, bundleIdentifier: "com.apple.Spotlight") == "magnifyingglass")
}

@Test func anotherAppsItemHasNoSymbol() {
    #expect(SystemItemSymbols.symbolName(accessibilityIdentifier: nil, title: "Item-0", bundleIdentifier: "com.getdropbox.dropbox") == nil)
}
