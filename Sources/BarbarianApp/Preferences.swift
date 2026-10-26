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

    /// Each modifier's Carbon mask, AppKit flag and symbol, in the order
    /// macOS shows them.
    private static let modifiers: [(carbon: Int, flag: NSEvent.ModifierFlags, symbol: String)] = [
        (controlKey, .control, "⌃"),
        (optionKey, .option, "⌥"),
        (shiftKey, .shift, "⇧"),
        (cmdKey, .command, "⌘"),
    ]

    var displayName: String {
        Self.modifiers.filter { carbonModifiers & $0.carbon != 0 }.map(\.symbol).joined() + key
    }

    static let defaultShowHidden = Shortcut(keyCode: kVK_ANSI_B, carbonModifiers: controlKey | optionKey | cmdKey, key: "B")
    static let defaultItemsMenu = Shortcut(keyCode: kVK_ANSI_M, carbonModifiers: controlKey | optionKey | cmdKey, key: "M")
}

extension Shortcut {
    /// A shortcut needs Command, Control or Option, so it cannot swallow
    /// plain typing.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = Self.modifiers.filter { flags.contains($0.flag) }.reduce(0) { $0 | $1.carbon }
        guard modifiers & (controlKey | optionKey | cmdKey) != 0,
              let key = event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty
        else {
            return nil
        }
        self.init(keyCode: Int(event.keyCode), carbonModifiers: modifiers, key: key)
    }
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

    /// Off by default: capturing items needs Screen Recording, and macOS asks
    /// people to confirm that permission again from time to time.
    var showsItemImages: Bool {
        didSet { defaults.set(showsItemImages, forKey: Key.showsItemImages) }
    }

    /// Nil when the person cleared the shortcut.
    var showHiddenShortcut: Shortcut? {
        didSet {
            save(showHiddenShortcut, forKey: Key.showHiddenShortcut)
            onShortcutsChange?()
        }
    }

    var itemsMenuShortcut: Shortcut? {
        didSet {
            save(itemsMenuShortcut, forKey: Key.itemsMenuShortcut)
            onShortcutsChange?()
        }
    }

    /// Called after either shortcut changes, to register the new ones.
    @ObservationIgnored var onShortcutsChange: (() -> Void)?

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Key {
        static let rehideDelay = "RehideDelay"
        static let revealsOnHover = "RevealsOnHover"
        static let showsItemImages = "ShowsItemImages"
        static let showHiddenShortcut = "ShowHiddenShortcut"
        static let itemsMenuShortcut = "ItemsMenuShortcut"
    }

    private init() {
        let defaults = UserDefaults.standard
        rehideDelay = defaults.object(forKey: Key.rehideDelay) as? TimeInterval ?? 4
        revealsOnHover = defaults.object(forKey: Key.revealsOnHover) as? Bool ?? true
        showsItemImages = defaults.bool(forKey: Key.showsItemImages)
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
