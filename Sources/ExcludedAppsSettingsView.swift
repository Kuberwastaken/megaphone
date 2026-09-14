import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings UI for the apps that ignore Megaphone's dictation shortcuts.
/// Rendered inside a settings card by the caller.
struct ExcludedAppsSettingsSection: View {
    @EnvironmentObject private var appState: AppState
    @State private var runningApps: [RunningAppOption] = []
    @State private var addError: String?

    private let workspaceCenter = NSWorkspace.shared.notificationCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("While one of these apps is in front, Megaphone's dictation shortcuts do nothing and the keys pass straight through — useful for games and apps that need Fn, Right Option, or your custom shortcut for themselves. Dictation already in progress still finishes.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if appState.excludedApps.isEmpty {
                Text("No excluded apps. Shortcuts work everywhere.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(appState.excludedApps.enumerated()), id: \.element.id) { index, app in
                        if index > 0 { Divider() }
                        excludedAppRow(app)
                    }
                }
            }

            HStack(spacing: 8) {
                Menu {
                    if runningApps.isEmpty {
                        Text("No other apps running")
                    } else {
                        ForEach(runningApps) { option in
                            Button {
                                add(bundleIdentifier: option.bundleIdentifier, name: option.name)
                            } label: {
                                Text(option.name)
                            }
                        }
                    }
                    Divider()
                    Button("Choose App…") { chooseAppFromDisk() }
                } label: {
                    Label("Add App", systemImage: "plus")
                }
                .fixedSize()

                Spacer()

                if let addError {
                    Text(addError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .controlSize(.small)
        }
        .onAppear(perform: refreshRunningApps)
        .onReceive(workspaceCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshRunningApps()
        }
        .onReceive(workspaceCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshRunningApps()
        }
        .onReceive(workspaceCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            refreshRunningApps()
        }
    }

    private func excludedAppRow(_ app: ExcludedApp) -> some View {
        HStack(spacing: 10) {
            AppIconView(bundleIdentifier: app.bundleIdentifier)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body.weight(.medium))
                Text(app.bundleIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                appState.removeExcludedApp(bundleIdentifier: app.bundleIdentifier)
                addError = nil
                refreshRunningApps()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Use dictation shortcuts in \(app.name) again")
        }
        .padding(.vertical, 8)
    }

    private func add(bundleIdentifier: String?, name: String?) {
        if appState.excludeApp(bundleIdentifier: bundleIdentifier, name: name) {
            addError = nil
            refreshRunningApps()
        } else {
            addError = "That app is already excluded."
        }
    }

    private func chooseAppFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.title = "Exclude App"
        panel.message = "Choose apps that should ignore Megaphone's dictation shortcuts."
        panel.prompt = "Exclude"
        panel.begin { response in
            guard response == .OK else { return }
            var failures: [String] = []
            var added = false
            for url in panel.urls {
                let name = FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
                guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else {
                    failures.append(name)
                    continue
                }
                if appState.excludeApp(bundleIdentifier: bundleIdentifier, name: name) {
                    added = true
                } else {
                    failures.append(name)
                }
            }
            if failures.isEmpty {
                addError = nil
            } else {
                addError = added
                    ? "Skipped \(failures.joined(separator: ", "))."
                    : "Couldn't exclude \(failures.joined(separator: ", "))."
            }
            refreshRunningApps()
        }
    }

    /// Apps a user could plausibly pick: regular (Dock-showing) apps that are
    /// not Megaphone itself and are not already excluded.
    private func refreshRunningApps() {
        let ownBundleIdentifier = ExcludedAppList.normalizedBundleIdentifier(Bundle.main.bundleIdentifier)
        let options = NSWorkspace.shared.runningApplications.compactMap { app -> RunningAppOption? in
            guard app.activationPolicy == .regular,
                  let bundleIdentifier = ExcludedAppList.normalizedBundleIdentifier(app.bundleIdentifier),
                  bundleIdentifier != ownBundleIdentifier,
                  !appState.isAppExcluded(bundleIdentifier: bundleIdentifier) else {
                return nil
            }
            return RunningAppOption(
                bundleIdentifier: bundleIdentifier,
                name: app.localizedName ?? bundleIdentifier
            )
        }
        var seen: Set<String> = []
        runningApps = options
            .filter { seen.insert($0.bundleIdentifier).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct RunningAppOption: Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}

/// Renders an app's Finder icon from its bundle identifier, falling back to a
/// generic glyph when the app is not installed on this Mac anymore.
private struct AppIconView: View {
    let bundleIdentifier: String

    var body: some View {
        if let icon = AppIconCache.icon(for: bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "questionmark.app.dashed")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }
}

/// Bundle-identifier lookups hit Launch Services, so results are memoized —
/// SwiftUI rebuilds these rows on every settings redraw.
private enum AppIconCache {
    private static var icons: [String: NSImage?] = [:]

    static func icon(for bundleIdentifier: String) -> NSImage? {
        if let cached = icons[bundleIdentifier] { return cached }
        let icon = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[bundleIdentifier] = icon
        return icon
    }
}
