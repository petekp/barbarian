import AppKit
import BarbarianCore
import BarbarianSystem
import Carbon.HIToolbox
import SwiftUI

/// Barbarian's Settings window. It opens by itself the first time Barbarian
/// runs, because its first section explains the dividers and the axe.
final class SettingsWindowController {
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
        let window = self.window ?? NSWindow.hosting(
            SettingsView(
                preferences: .shared,
                onShortcutRecording: { [weak controller] isRecording in
                    if isRecording { controller?.suspendHotKeys() } else { controller?.registerHotKeys() }
                }
            ),
            title: "Barbarian Settings",
            size: NSSize(width: 480, height: 640),
            styleMask: [.titled, .closable]
        )
        self.window = window
        window.bringForward()
    }
}

private struct SettingsView: View {
    @Bindable var preferences: Preferences
    let onShortcutRecording: (Bool) -> Void

    /// Read again whenever Barbarian becomes active, as it does when someone
    /// comes back from System Settings.
    @State private var opensAtLogin = LaunchAtLogin.isEnabled
    @State private var accessibilityGranted = AccessibilityPermission.isGranted
    @State private var screenRecordingGranted = ScreenRecordingPermission.isGranted

    var body: some View {
        Form {
            Section("How Barbarian works") {
                Explanation(symbol: Divider.hidden.symbolName, text: "Items left of the single chevron are Hidden. Click the axe, or rest the pointer on the empty part of the menu bar, to show them.")
                Explanation(symbol: Divider.alwaysHidden.symbolName, text: "Items left of the double chevron are Always Hidden. Option-click the axe to show them too.")
                Explanation(symbol: "list.bullet", text: "Right-click the axe for a list of every item, including items that don't fit. Pick one to open it.")
                Explanation(symbol: "hand.draw", text: "To move items between sections, Command-drag them in the menu bar, or choose Arrange Menu Bar from that list.")
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(
                    get: { opensAtLogin },
                    set: { enabled in
                        try? LaunchAtLogin.setEnabled(enabled)
                        opensAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                Picker("Hide items again after", selection: $preferences.rehideDelay) {
                    ForEach(Preferences.rehideDelayChoices, id: \.self) { seconds in
                        Text("\(Int(seconds)) seconds").tag(seconds)
                    }
                }
                Toggle("Show Hidden items when the pointer rests on the menu bar", isOn: $preferences.revealsOnHover)
                Toggle(isOn: Binding(
                    get: { preferences.showsItemImages },
                    set: { isOn in
                        preferences.showsItemImages = isOn
                        if isOn && !screenRecordingGranted { ScreenRecordingPermission.requestAndOpenSettings() }
                    }
                )) {
                    Text("Show items' own icons")
                    Text("Needs Screen Recording, which macOS asks you to confirm about once a month. When off, items show their app's icon.")
                }
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
                    isGranted: accessibilityGranted,
                    grant: AccessibilityPermission.requestAndOpenSettings
                )
                if preferences.showsItemImages {
                    PermissionRow(
                        title: "Screen Recording",
                        detail: "Needed to show items' own icons.",
                        isGranted: screenRecordingGranted,
                        grant: ScreenRecordingPermission.requestAndOpenSettings
                    )
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            opensAtLogin = LaunchAtLogin.isEnabled
            accessibilityGranted = AccessibilityPermission.isGranted
            screenRecordingGranted = ScreenRecordingPermission.isGranted
        }
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
/// `onRecording` reports when recording starts and stops.
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
        guard let output = RenderCommand.outputURL(after: "--render-settings", in: arguments, usage: "<file.png>") else {
            return 1
        }
        let view = NSHostingView(rootView: SettingsView(preferences: .shared, onShortcutRecording: { _ in }))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return RenderCommand.fail("Rendering failed.") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return RenderCommand.writePNG(bitmap, to: output)
    }
}
