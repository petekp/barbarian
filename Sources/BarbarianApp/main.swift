import AppKit
import BarbarianSystem

let arguments = CommandLine.arguments

if arguments.contains("--print-items") {
    ItemReport.print(MenuBarWindowList.items())
    exit(0)
}

if let flag = arguments.firstIndex(of: "--command") {
    let names = Command.allCases.map(\.rawValue).joined(separator: ", ")
    guard flag + 1 < arguments.count, let command = Command(rawValue: arguments[flag + 1]) else {
        FileHandle.standardError.write(Data("usage: Barbarian --command <\(names)>\n".utf8))
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
