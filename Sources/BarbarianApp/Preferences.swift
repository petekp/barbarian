import AppKit
import Carbon.HIToolbox
import Observation

/// A key and modifiers for a system-wide shortcut, as Carbon hot keys take
/// them.
struct Shortcut: Codable, Equatable {
    /// A virtual key code such as `kVK_ANSI_B`.
    let keyCode: Int
    /// A Carbon modifier mask such as `cmdKey | optionKey`.
    let carbonModifiers: Int
    /// The key as typed, shown in Settings.
    let key: String

    var displayName: String {
        var symbols = ""
        if carbonModifiers & controlKey != 0 { symbols += "⌃" }
        if carbonModifiers & optionKey != 0 { symbols += "⌥" }
        if carbonModifiers & shiftKey != 0 { symbols += "⇧" }
        if carbonModifiers & cmdKey != 0 { symbols += "⌘" }
        return symbols + key
    }

    /// A shortcut needs Command, Control or Option, so it cannot swallow
    /// plain typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        guard modifiers & (controlKey | optionKey | cmdKey) != 0,
              let key = event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty
        else {
            return nil
        }
        self.init(keyCode: Int(event.keyCode), carbonModifiers: modifiers, key: key)
    }

    init(keyCode: Int, carbonModifiers: Int, key: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.key = key
    }

    static let defaultShowHidden = Shortcut(keyCode: kVK_ANSI_B, carbonModifiers: controlKey | optionKey | cmdKey, key: "B")
    static let defaultItemsMenu = Shortcut(keyCode: kVK_ANSI_M, carbonModifiers: controlKey | optionKey | cmdKey, key: "M")
}

/// The settings people can change, saved in user defaults.
@Observable
final class Preferences {
    static let shared = Preferences()

    static let rehideDelayChoices: [TimeInterval] = [2, 4, 8, 15, 30]

    var rehideDelay: TimeInterval {
        didSet { defaults.set(rehideDelay, forKey: Key.rehideDelay) }
    }

    var revealsOnHover: Bool {
        didSet { defaults.set(revealsOnHover, forKey: Key.revealsOnHover) }
    }

    /// Nil when the person cleared the shortcut.
    var showHiddenShortcut: Shortcut? {
        didSet { save(showHiddenShortcut, forKey: Key.showHiddenShortcut) }
    }

    var itemsMenuShortcut: Shortcut? {
        didSet { save(itemsMenuShortcut, forKey: Key.itemsMenuShortcut) }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Key {
        static let rehideDelay = "RehideDelay"
        static let revealsOnHover = "RevealsOnHover"
        static let showHiddenShortcut = "ShowHiddenShortcut"
        static let itemsMenuShortcut = "ItemsMenuShortcut"
    }

    private init() {
        let defaults = UserDefaults.standard
        rehideDelay = defaults.object(forKey: Key.rehideDelay) as? TimeInterval ?? 4
        revealsOnHover = defaults.object(forKey: Key.revealsOnHover) as? Bool ?? true
        showHiddenShortcut = Self.load(Key.showHiddenShortcut, from: defaults, default: .defaultShowHidden)
        itemsMenuShortcut = Self.load(Key.itemsMenuShortcut, from: defaults, default: .defaultItemsMenu)
    }

    /// A cleared shortcut is saved as empty data, so it stays cleared.
    private func save(_ shortcut: Shortcut?, forKey key: String) {
        defaults.set(shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: key)
    }

    private static func load(_ key: String, from defaults: UserDefaults, default fallback: Shortcut) -> Shortcut? {
        guard let data = defaults.data(forKey: key) else { return fallback }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }
}
