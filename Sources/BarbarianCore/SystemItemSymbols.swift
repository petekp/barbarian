/// SF Symbols that look like macOS's own menu bar items. Barbarian draws an
/// item with one when it has no capture of the item, because these items'
/// apps, such as Control Center, have icons that look nothing like them.
public enum SystemItemSymbols {
    /// The symbol for the item with this Accessibility identifier, window
    /// title or owning app, checked in that order. Control Center reports
    /// identifiers through Accessibility; window titles need Screen Recording.
    public static func symbolName(accessibilityIdentifier: String?, title: String?, bundleIdentifier: String?) -> String? {
        if let accessibilityIdentifier, accessibilityIdentifier.hasPrefix(menuExtraPrefix),
           let symbol = byMenuExtra[String(accessibilityIdentifier.dropFirst(menuExtraPrefix.count))] {
            return symbol
        }
        if let title, let symbol = byWindowTitle[title] { return symbol }
        if let bundleIdentifier, let symbol = byApp[bundleIdentifier] { return symbol }
        return nil
    }

    private static let menuExtraPrefix = "com.apple.menuextra."

    private static let byMenuExtra = [
        "battery": "battery.100",
        "clock": "clock",
        "controlcenter": "switch.2",
        "focusmode": "moon.fill",
        "nowplaying": "play.fill",
        "screenmirroring": "rectangle.on.rectangle",
        "sound": "speaker.wave.2.fill",
        "wifi": "wifi",
    ]

    /// Control Center's window titles, which differ from its identifiers.
    private static let byWindowTitle = [
        "AudioVideoModule": "video.fill",
        "Battery": "battery.100",
        "BentoBox": "switch.2",
        "Clock": "clock",
        "FocusModes": "moon.fill",
        "NowPlaying": "play.fill",
        "ScreenMirroring": "rectangle.on.rectangle",
        "Sound": "speaker.wave.2.fill",
        "WiFi": "wifi",
    ]

    private static let byApp = [
        "com.apple.Spotlight": "magnifyingglass",
    ]
}
