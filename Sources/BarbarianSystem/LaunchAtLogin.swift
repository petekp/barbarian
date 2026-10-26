import Foundation
import ServiceManagement

/// Whether macOS opens Barbarian when the user logs in. Without it, a
/// restart leaves every menu bar item showing until Barbarian is opened.
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    private static let firstLaunchKey = "LaunchAtLoginWasTurnedOnAtFirstLaunch"

    /// Turns launch at login on the first time Barbarian runs. Turning it off
    /// afterwards sticks.
    public static func enableOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: firstLaunchKey) else { return }
        UserDefaults.standard.set(true, forKey: firstLaunchKey)
        try? setEnabled(true)
    }
}
