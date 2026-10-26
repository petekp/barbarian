import ApplicationServices

extension AXUIElement {
    /// The element for an app, with calls to it giving up after `timeout`
    /// seconds so a hung app cannot stall Barbarian.
    static func application(_ pid: Int32, timeout: Float) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }

    func attribute<Value>(_ name: String) -> Value? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? Value
    }

    /// The element's frame in window-list coordinates.
    var frame: CGRect? {
        guard
            let positionValue: AXValue = attribute(kAXPositionAttribute),
            let sizeValue: AXValue = attribute(kAXSizeAttribute)
        else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue, .cgPoint, &position)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
