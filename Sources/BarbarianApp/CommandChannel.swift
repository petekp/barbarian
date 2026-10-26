import Foundation

/// Commands a terminal can send to the running app, for scripts and checks:
/// `Barbarian --command show-hidden`. Distributed notifications need no
/// permission.
enum Command: String, CaseIterable {
    case showHidden = "show-hidden"
    case showAll = "show-all"
    case hide
    case openMenu = "open-menu"
    case openLayout = "open-layout"
    case closeLayout = "close-layout"
}

enum CommandChannel {
    private static let name = Notification.Name("com.petepetrash.barbarian.command")

    static func send(_ command: Command) {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: command.rawValue, userInfo: nil, deliverImmediately: true
        )
    }

    static func listen(_ handler: @escaping @MainActor (Command) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { notification in
            guard let raw = notification.object as? String, let command = Command(rawValue: raw) else { return }
            MainActor.assumeIsolated { handler(command) }
        }
    }
}
