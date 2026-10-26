import AppKit
import BarbarianSystem

let arguments = CommandLine.arguments

if arguments.contains("--print-items") {
    ItemReport.print(MenuBarWindowList.items())
    exit(0)
}

if arguments.contains("--render-app-icon") {
    exit(AppIconRenderer.run(arguments: arguments))
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

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
