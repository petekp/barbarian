import AppKit
import SwiftUI

/// A short message in a popover under Barbarian's icon, for a failure that
/// needs no decision. It closes on its own or on a click elsewhere.
final class StatusMessage {
    private var popover: NSPopover?
    private var closeTask: Task<Void, Never>?

    private static let visibleFor: Duration = .seconds(6)

    func show(_ text: String, below button: NSStatusBarButton) {
        popover?.close()
        closeTask?.cancel()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView:
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)
                .padding(14)
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
        closeTask = Task {
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }
            popover.close()
        }
    }
}
