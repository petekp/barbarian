/// One of macOS's own menu bar items. Control Center owns most of them, and
/// its app name and icon say nothing about which item is which, so Barbarian
/// names and draws these items itself.
public enum SystemItem: CaseIterable, Sendable {
    case accessibilityShortcuts
    case battery
    case cameraAndMicrophone
    case clock
    case controlCenter
    case focus
    case keyboardBrightness
    case musicRecognition
    case nowPlaying
    case screenMirroring
    case sound
    case spotlight
    case stageManager
    case userSwitcher
    case wifi

    /// The item with this Accessibility identifier, window title or owning
    /// app, checked in that order. Control Center reports identifiers such
    /// as `com.apple.menuextra.wifi` through Accessibility; window titles
    /// need Screen Recording.
    public init?(accessibilityIdentifier: String?, title: String?, bundleIdentifier: String?) {
        let byIdentifier = accessibilityIdentifier.flatMap { identifier in
            Self.allCases.first { $0.menuExtraIdentifier.map { Self.menuExtraPrefix + $0 } == identifier }
        }
        let byTitle = title.flatMap { title in Self.allCases.first { $0.windowTitle == title } }
        let byApp = bundleIdentifier.flatMap { bundle in Self.allCases.first { $0.bundleIdentifier == bundle } }
        guard let match = byIdentifier ?? byTitle ?? byApp else { return nil }
        self = match
    }

    private static let menuExtraPrefix = "com.apple.menuextra."

    public var name: String {
        switch self {
        case .accessibilityShortcuts: "Accessibility Shortcuts"
        case .battery: "Battery"
        case .cameraAndMicrophone: "Camera and Mic"
        case .clock: "Clock"
        case .controlCenter: "Control Center"
        case .focus: "Focus"
        case .keyboardBrightness: "Keyboard Brightness"
        case .musicRecognition: "Music Recognition"
        case .nowPlaying: "Now Playing"
        case .screenMirroring: "Screen Mirroring"
        case .sound: "Sound"
        case .spotlight: "Spotlight"
        case .stageManager: "Stage Manager"
        case .userSwitcher: "Fast User Switching"
        case .wifi: "Wi-Fi"
        }
    }

    /// An SF Symbol that looks like the item.
    public var symbolName: String {
        switch self {
        case .accessibilityShortcuts: "accessibility"
        case .battery: "battery.100"
        case .cameraAndMicrophone: "video.fill"
        case .clock: "clock"
        case .controlCenter: "switch.2"
        case .focus: "moon.fill"
        case .keyboardBrightness: "light.max"
        case .musicRecognition: "shazam.logo"
        case .nowPlaying: "play.fill"
        case .screenMirroring: "rectangle.on.rectangle"
        case .sound: "speaker.wave.2.fill"
        case .spotlight: "magnifyingglass"
        case .stageManager: "squares.leading.rectangle"
        case .userSwitcher: "person.crop.circle"
        case .wifi: "wifi"
        }
    }

    /// When macOS shows the item, for items it shows only some of the time,
    /// worded to follow "while".
    public var showsWhile: String? {
        switch self {
        case .cameraAndMicrophone: "in use"
        case .focus: "on"
        case .nowPlaying: "playing"
        default: nil
        }
    }

    /// Whether the item draws text, as the clock draws the time. Text is
    /// unreadable at icon size, so the symbol stands in even when the item
    /// has been captured.
    public var drawsText: Bool {
        self == .clock
    }

    /// The part after `com.apple.menuextra.`, for the items seen reporting
    /// one.
    private var menuExtraIdentifier: String? {
        switch self {
        case .battery: "battery"
        case .clock: "clock"
        case .controlCenter: "controlcenter"
        case .focus: "focusmode"
        case .nowPlaying: "nowplaying"
        case .screenMirroring: "screenmirroring"
        case .sound: "sound"
        case .wifi: "wifi"
        default: nil
        }
    }

    /// Control Center's window title for the item.
    private var windowTitle: String? {
        switch self {
        case .accessibilityShortcuts: "AccessibilityShortcuts"
        case .battery: "Battery"
        case .cameraAndMicrophone: "AudioVideoModule"
        case .clock: "Clock"
        case .controlCenter: "BentoBox"
        case .focus: "FocusModes"
        case .keyboardBrightness: "KeyboardBrightness"
        case .musicRecognition: "MusicRecognition"
        case .nowPlaying: "NowPlaying"
        case .screenMirroring: "ScreenMirroring"
        case .sound: "Sound"
        case .stageManager: "StageManager"
        case .userSwitcher: "UserSwitcher"
        case .wifi: "WiFi"
        case .spotlight: nil
        }
    }

    private var bundleIdentifier: String? {
        self == .spotlight ? "com.apple.Spotlight" : nil
    }
}
