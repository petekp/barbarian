import AppKit
import BarbarianSystem
import Carbon.HIToolbox
import SwiftUI

/// Barbarian's Settings window. It opens by itself the first time Barbarian
/// runs, because its first section explains the dividers and the axe.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private unowned let controller: AppController
    private var window: NSWindow?

    private static let hasOpenedKey = "SettingsOpenedAtFirstLaunch"

    init(controller: AppController) {
        self.controller = controller
    }

    func showOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: Self.hasOpenedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.hasOpenedKey)
        show()
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Barbarian Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(
            preferences: .shared,
            onShortcutRecording: { [weak controller] isRecording in
                if isRecording { controller?.suspendHotKeys() } else { controller?.registerHotKeys() }
            }
        ))
        window.center()
        return window
    }
}

private struct SettingsView: View {
    @Bindable var preferences: Preferences
    let onShortcutRecording: (Bool) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Form {
                Section("How Barbarian works") {
                    Explanation(symbol: "chevron.left", text: "Items left of the single chevron are Hidden. Click the axe, or rest the pointer on the empty part of the menu bar, to show them.")
                    Explanation(symbol: "chevron.left.2", text: "Items left of the double chevron are Always Hidden. Option-click the axe to show them too.")
                    Explanation(symbol: "list.bullet", text: "Right-click the axe for a list of every item, including items that don't fit. Pick one to open it.")
                    Explanation(symbol: "hand.draw", text: "To move items between sections, Command-drag them in the menu bar, or choose Arrange Menu Bar from that list.")
                }

                Section("General") {
                    Toggle("Open at login", isOn: Binding(
                        get: { LaunchAtLogin.isEnabled },
                        set: { try? LaunchAtLogin.setEnabled($0) }
                    ))
                    Picker("Hide items again after", selection: $preferences.rehideDelay) {
                        ForEach(Preferences.rehideDelayChoices, id: \.self) { seconds in
                            Text("\(Int(seconds)) seconds").tag(seconds)
                        }
                    }
                    Toggle("Show Hidden items when the pointer rests on the menu bar", isOn: $preferences.revealsOnHover)
                }

                Section("Shortcuts") {
                    LabeledContent("Show Hidden items") {
                        ShortcutRecorder(shortcut: $preferences.showHiddenShortcut, onRecording: onShortcutRecording)
                    }
                    LabeledContent("Open the item list") {
                        ShortcutRecorder(shortcut: $preferences.itemsMenuShortcut, onRecording: onShortcutRecording)
                    }
                }

                Section("Permissions") {
                    PermissionRow(
                        title: "Accessibility",
                        detail: "Needed to open items that don't fit and to move items.",
                        isGranted: AccessibilityPermission.isGranted,
                        grant: { AccessibilityPermission.request(); AccessibilityPermission.openSettings() }
                    )
                    PermissionRow(
                        title: "Screen Recording",
                        detail: "Optional. Shows each item's own icon and name instead of its app's.",
                        isGranted: ScreenRecordingPermission.isGranted,
                        grant: { ScreenRecordingPermission.request(); ScreenRecordingPermission.openSettings() }
                    )
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 480)
        .frame(minHeight: 560)
    }
}

private struct Explanation: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 20)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let grant: () -> Void

    var body: some View {
        LabeledContent {
            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Open Settings", action: grant)
            }
        } label: {
            Text(title)
            Text(detail)
        }
    }
}

/// A button that records the next shortcut typed. Escape cancels.
private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut?
    let onRecording: (Bool) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(isRecording ? "Type a shortcut" : (shortcut?.displayName ?? "None")) {
                isRecording ? stopRecording() : startRecording()
            }
            .frame(minWidth: 110)
            if shortcut != nil && !isRecording {
                Button {
                    shortcut = nil
                    onRecording(false)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear shortcut")
            }
        }
    }

    private func startRecording() {
        isRecording = true
        onRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if Int(event.keyCode) == kVK_Escape {
                    stopRecording()
                } else if let typed = Shortcut(event: event) {
                    shortcut = typed
                    stopRecording()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onRecording(false)
    }
}

/// `Barbarian --render-settings <file.png>` draws the Settings window's
/// content to a PNG without opening the window.
enum SettingsSnapshot {
    static func run(arguments: [String]) -> Int32 {
        guard let flag = arguments.firstIndex(of: "--render-settings"), flag + 1 < arguments.count else {
            FileHandle.standardError.write(Data("usage: Barbarian --render-settings <file.png>\n".utf8))
            return 1
        }
        _ = NSApplication.shared
        let view = NSHostingView(rootView: SettingsView(preferences: .shared, onShortcutRecording: { _ in }))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 1 }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do {
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[flag + 1]))
        } catch {
            FileHandle.standardError.write(Data("Could not write the image: \(error.localizedDescription)\n".utf8))
            return 1
        }
        return 0
    }
}
