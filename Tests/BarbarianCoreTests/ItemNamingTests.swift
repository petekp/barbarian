import Testing
import BarbarianCore

@Test func anAppWithOneItemIsNamedForTheApp() {
    #expect(ItemNaming.name(appName: "Dropbox", isSystemProcess: false, appItemCount: 1, title: "Item-0", accessibilityName: "Dropbox, up to date") == "Dropbox")
}

@Test func anItemOfASharedOrSystemOwnerIsNamedForItself() {
    #expect(ItemNaming.name(appName: "Control Center", isSystemProcess: true, appItemCount: 6, title: "WiFi", accessibilityName: "Wi-Fi, connected") == "Wi-Fi")
    #expect(ItemNaming.name(appName: "SystemUIServer", isSystemProcess: true, appItemCount: 1, title: nil, accessibilityName: "Siri") == "Siri")
    #expect(ItemNaming.name(appName: "Stats", isSystemProcess: false, appItemCount: 2, title: "Battery_battery", accessibilityName: nil) == "Battery_battery")
}

@Test func aMadeUpWindowTitleFallsBackToTheAppName() {
    #expect(ItemNaming.name(appName: "ChatGPT", isSystemProcess: false, appItemCount: 2, title: "Item-1", accessibilityName: nil) == "ChatGPT")
}
