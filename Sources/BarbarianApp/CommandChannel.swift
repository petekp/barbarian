import BarbarianCore
import Foundation

/// Commands a terminal can send to the running app, for scripts and checks:
/// `Barbarian --command show-hidden`. Distributed notifications need no
/// permission.
enum Command: Equatable {
    case showHidden
    case showAll
    case hide
    case openMenu
    case openLayout
    case closeLayout
    /// Opens an item as picking it from Barbarian's menu does.
    case openItem(WindowID)

    static let usage = "show-hidden, show-all, hide, open-menu, open-layout, close-layout, open-item <window ID>"

    init?(arguments: [String]) {
        switch arguments {
        case ["show-hidden"]: self = .showHidden
        case ["show-all"]: self = .showAll
        case ["hide"]: self = .hide
        case ["open-menu"]: self = .openMenu
        case ["open-layout"]: self = .openLayout
        case ["close-layout"]: self = .closeLayout
        case let arguments where arguments.count == 2 && arguments[0] == "open-item":
            guard let id = WindowID(arguments[1]) else { return nil }
            self = .openItem(id)
        default: return nil
        }
    }

    var arguments: [String] {
        switch self {
        case .showHidden: ["show-hidden"]
        case .showAll: ["show-all"]
        case .hide: ["hide"]
        case .openMenu: ["open-menu"]
        case .openLayout: ["open-layout"]
        case .closeLayout: ["close-layout"]
        case .openItem(let id): ["open-item", String(id)]
        }
    }
}

enum CommandChannel {
    private static let name = Notification.Name("com.petepetrash.barbarian.command")

    static func send(_ command: Command) {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: command.arguments.joined(separator: " "), userInfo: nil, deliverImmediately: true
        )
    }

    static func listen(_ handler: @escaping @MainActor (Command) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { notification in
            guard
                let message = notification.object as? String,
                let command = Command(arguments: message.split(separator: " ").map(String.init))
            else {
                return
            }
            MainActor.assumeIsolated { handler(command) }
        }
    }
}
