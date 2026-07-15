import AppKit
import Darwin

// Megaphone's real binary is compiled against the macOS 26 SDK, so on older
// systems Launch Services refuses to start it with the opaque error -10825
// instead of saying why. This launcher is the bundle's main executable and
// deploys back to macOS 13: on macOS 26+ it replaces itself with the core
// binary via execv, and on anything older it explains the requirement.
@main
@MainActor
enum MegaphoneLauncher {
    static func main() {
        if #available(macOS 26.0, *) {
            launchCore()
        } else {
            presentRequirementAlert()
        }
    }

    private static var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "Megaphone"
    }

    private static func launchCore() -> Never {
        guard
            let coreName = Bundle.main.object(forInfoDictionaryKey: "MegaphoneCoreExecutable") as? String,
            let launcherURL = Bundle.main.executableURL
        else {
            fail("This copy of \(appName) is missing its core executable metadata. Please reinstall it.")
        }
        let corePath = launcherURL.deletingLastPathComponent()
            .appendingPathComponent(coreName).path
        guard FileManager.default.isExecutableFile(atPath: corePath) else {
            fail("This copy of \(appName) is damaged (\(coreName) is missing). Please reinstall it.")
        }
        var argv: [UnsafeMutablePointer<CChar>?] = CommandLine.arguments.map { strdup($0) }
        argv[0] = strdup(corePath)
        argv.append(nil)
        execv(corePath, argv)
        fail("\(appName)'s core process could not be started (errno \(errno)).")
    }

    private static func presentRequirementAlert() -> Never {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let current = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        fputs("\(appName) requires macOS 26 (Tahoe) or later; this Mac is running macOS \(current).\n", stderr)

        activate()
        let alert = NSAlert()
        alert.messageText = "\(appName) requires macOS 26"
        alert.informativeText = """
        \(appName)'s on-device dictation is built on Apple's SpeechAnalyzer, which ships with macOS 26 (Tahoe) and later. This Mac is running macOS \(current).

        Update in System Settings > General > Software Update, then open \(appName) again.
        """
        alert.addButton(withTitle: "Open Software Update")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn {
            openSoftwareUpdate()
        }
        exit(EXIT_FAILURE)
    }

    // The bundle is LSUIElement, so the process starts as an accessory with
    // no Dock presence; promote it so the alert reliably comes to the front.
    private static func activate() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(ignoringOtherApps: true)
        }
    }

    private static func openSoftwareUpdate() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/SoftwareUpdate.prefPane"))
    }

    private static func fail(_ message: String) -> Never {
        fputs("\(message)\n", stderr)
        activate()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "\(appName) could not start"
        alert.informativeText = message
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        exit(EXIT_FAILURE)
    }
}
