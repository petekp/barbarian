import AppKit
import BarbarianSystem

let arguments = CommandLine.arguments
// Screen and window server queries need the app object, even in the
// commands below that exit without running it.
let app = NSApplication.shared

// Development commands, left out of release builds. `--command` drives the
// running app, which holds Accessibility permission, and its channel is open
// to every process on the Mac.
#if DEBUG
if arguments.contains("--print-items") {
    ItemReport.print()
    exit(0)
}

if arguments.contains("--render-app-icon") {
    exit(AppIconRenderer.run(arguments: arguments))
}

if arguments.contains("--render-settings") {
    exit(SettingsSnapshot.run(arguments: arguments))
}

if arguments.contains("--render-arrange") {
    exit(ArrangeSnapshot.run(arguments: arguments))
}

if let flag = arguments.firstIndex(of: "--command") {
    guard let command = Command(arguments: Array(arguments[(flag + 1)...])) else {
        FileHandle.standardError.write(Data("usage: Barbarian --command <\(Command.usage)>\n".utf8))
        exit(2)
    }
    CommandChannel.send(command)
    exit(0)
}
#endif

let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
