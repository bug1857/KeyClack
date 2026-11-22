import Foundation
import ServiceManagement

/// Manages macOS Launch at Login via ServiceManagement (SMAppService.mainApp, macOS 13+).
enum LaunchAtLoginManager {
    static var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard isRunningFromAppBundle else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard isRunningFromAppBundle else {
            throw NSError(
                domain: "com.keyclack.login",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Build and run KeyClack.app (via ./build-app.sh --install) to enable Launch at Login."
                ]
            )
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
