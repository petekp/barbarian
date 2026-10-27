import Testing
import BarbarianCore

@Test func anAppWithOneItemIsNamedForTheApp() {
    #expect(ItemNaming.name(appName: "Dropbox", isSystemProcess: false, appItemCount: 1, systemItem: nil, title: "Item-0", accessibilityName: "Dropbox, up to date") == "Dropbox")
}

@Test func aKnownSystemItemIsNamedForWhatItIs() {
    #expect(ItemNaming.name(appName: "Control Center", isSystemProcess: true, appItemCount: 6, systemItem: .wifi, title: nil, accessibilityName: "Wi-Fi, connected") == "Wi-Fi")
}

@Test func anItemOfASharedOrSystemOwnerIsNamedForItself() {
    #expect(ItemNaming.name(appName: "SystemUIServer", isSystemProcess: true, appItemCount: 1, systemItem: nil, title: nil, accessibilityName: "Siri") == "Siri")
    #expect(ItemNaming.name(appName: "Stats", isSystemProcess: false, appItemCount: 2, systemItem: nil, title: "Battery_battery", accessibilityName: nil) == "Battery_battery")
}

@Test func aMadeUpWindowTitleFallsBackToTheAppName() {
    #expect(ItemNaming.name(appName: "ChatGPT", isSystemProcess: false, appItemCount: 2, systemItem: nil, title: "Item-1", accessibilityName: nil) == "ChatGPT")
}
