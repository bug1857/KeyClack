import Foundation
import AppKit

/// Tracks the currently focused macOS application for per-app Smart Mute.
final class ActiveAppMonitor {
    var onFrontmostAppChanged: ((String?, String?) -> Void)?

    private var observer: NSObjectProtocol?

    var currentBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    var currentAppName: String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    func start() {
        stop()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.onFrontmostAppChanged?(app?.bundleIdentifier, app?.localizedName)
        }
        onFrontmostAppChanged?(currentBundleID, currentAppName)
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    /// Returns currently running regular macOS applications for one-click exclusion picking.
    static func runningRegularApps() -> [ExcludedApp] {
        let myBundleID = Bundle.main.bundleIdentifier
        var seen: Set<String> = []
        var apps: [ExcludedApp] = []

        for running in NSWorkspace.shared.runningApplications {
            guard running.activationPolicy == .regular,
                  let bundleID = running.bundleIdentifier,
                  bundleID != myBundleID,
                  !seen.contains(bundleID) else { continue }
            seen.insert(bundleID)
            let name = running.localizedName ?? bundleID
            apps.append(ExcludedApp(bundleIdentifier: bundleID, displayName: name))
        }
        return apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    deinit {
        stop()
    }
}
