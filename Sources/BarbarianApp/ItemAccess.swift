import AppKit
import BarbarianCore
import BarbarianSystem

/// Opens a menu bar item the user picked from Barbarian's menu, wherever it
/// currently is.
///
/// With Accessibility permission, an item that is off screen moves next to
/// Barbarian's icon, gets clicked, and moves back once its menu closes.
/// Without it, Barbarian reveals the item's section and the user clicks the
/// item, which works only when it fits.
final class ItemAccess {
    private unowned let controller: AppController
    private(set) var isBusy = false

    init(controller: AppController) {
        self.controller = controller
    }

    func open(_ item: MenuBarItem) {
        guard AccessibilityPermission.isGranted else {
            revealSection(of: item)
            return
        }
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await openWithEvents(item)
            } catch {
                Self.showError(error)
            }
        }
    }

    private func openWithEvents(_ item: MenuBarItem) async throws {
        guard let layout = controller.currentLayout() else { return }
        let current = MenuBarWindowList.items().first { $0.windowID == item.windowID } ?? item
        if current.isOnScreen {
            try await MenuBarItemEvents.click(item.windowID, ownerPID: item.ownerPID)
            return
        }

        let returnDestination = Self.returnDestination(for: item, in: layout)
        try await MenuBarItemEvents.move(item.windowID, ownerPID: item.ownerPID, to: .leftOf(layout.controls.icon))
        try await Task.sleep(for: .milliseconds(150))
        try await MenuBarItemEvents.click(item.windowID, ownerPID: item.ownerPID)
        await waitForMenuToClose(ownedBy: item.ownerPID)
        if let returnDestination {
            try await MenuBarItemEvents.move(item.windowID, ownerPID: item.ownerPID, to: returnDestination)
        }
    }

    /// The spot the item came from: left of its old right neighbor, or right
    /// of its old left neighbor when it was rightmost. An item that had no
    /// position goes back to the far left, where items that do not fit sit.
    static func returnDestination(for item: MenuBarItem, in layout: MenuBarLayout) -> MoveDestination? {
        let ids = layout.entries.map(\.id)
        guard let index = ids.firstIndex(of: item.windowID) else {
            return ids.first.map { .leftOf($0) }
        }
        if index + 1 < ids.count { return .leftOf(ids[index + 1]) }
        if index > 0 { return .rightOf(ids[index - 1]) }
        return nil
    }

    private func waitForMenuToClose(ownedBy pid: Int32) async {
        let start = Date()
        let maximumWait: TimeInterval = 60
        let waitForMenuToAppear: TimeInterval = 3
        var menuWasOpen = false
        while Date().timeIntervalSince(start) < maximumWait {
            let isOpen = MenuBarWindowList.hasOpenMenu(ownedBy: pid)
            if isOpen { menuWasOpen = true }
            if menuWasOpen && !isOpen { return }
            if !menuWasOpen && Date().timeIntervalSince(start) > waitForMenuToAppear { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func revealSection(of item: MenuBarItem) {
        switch controller.currentLayout()?.section(of: item.windowID) {
        case .hidden: controller.setState(.showingHidden)
        case .alwaysHidden: controller.setState(.showingAll)
        case .shown, nil: break
        }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            let fits = MenuBarWindowList.items().first { $0.windowID == item.windowID }?.isOnScreen ?? false
            if !fits { Self.askForAccessibility(itemName: ItemPresentation(items: [item]).name(of: item)) }
        }
    }

    private static func askForAccessibility(itemName: String) {
        let alert = NSAlert()
        alert.messageText = "\(itemName) doesn't fit in the menu bar"
        alert.informativeText = "Allow Barbarian in Accessibility settings and it can bring the item into view and open it for you."
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityPermission.request()
            AccessibilityPermission.openSettings()
        }
    }

    private static func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Barbarian couldn't open that item"
        alert.informativeText = String(describing: error)
        NSApp.activate()
        alert.runModal()
    }
}
