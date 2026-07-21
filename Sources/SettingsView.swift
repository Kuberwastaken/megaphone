import SwiftUI
import AVFoundation
import ServiceManagement
import FoundationModels

// MARK: - Shared Helpers

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private let iso8601DayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

/// Language picker plus model install status for Apple's on-device
/// SpeechAnalyzer. Transcription runs entirely on this Mac — there is no
/// provider, model ID, or API key to configure.
struct OnDeviceTranscriptionSettings: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Speech is transcribed on this Mac by Apple's on-device model. Audio never leaves your computer for transcription.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription Language")
                    .font(.caption.weight(.semibold))
                Picker("", selection: $appState.transcriptionLanguage) {
                    ForEach(appState.transcriptionLanguageOptions, id: \.code) { option in
                        Text(option.name).tag(option.code)
                    }
                }
                .accessibilityLabel("Transcription Language")
                .labelsHidden()
                Text("Languages supported by the on-device speech model. Auto uses your system language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SpeechModelStatusRow(
                modelManager: appState.speechModelManager,
                localePreference: appState.transcriptionLanguage
            )
        }
    }
}

/// Shows the install/download state of the on-device speech model for the
/// selected language, with a download button when assets are missing.
struct SpeechModelStatusRow: View {
    @ObservedObject var modelManager: SpeechModelManager
    let localePreference: String

    private var needsDownload: Bool {
        switch modelManager.status {
        case .needsDownload, .failed: return true
        default: return false
        }
    }

    private var isDownloading: Bool {
        if case .downloading = modelManager.status { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 8) {
            if isDownloading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
            }
            Text(modelManager.status.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if needsDownload {
                Button("Download") {
                    modelManager.download(localePreference: localePreference)
                }
                .font(.caption)
            }
        }
        .onAppear {
            modelManager.refresh(localePreference: localePreference)
        }
    }

    private var statusSymbol: String {
        switch modelManager.status {
        case .installed: return "checkmark.circle.fill"
        case .needsDownload: return "arrow.down.circle"
        case .unknown: return "circle.dotted"
        default: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch modelManager.status {
        case .installed: return .green
        case .needsDownload, .unknown: return .secondary
        default: return .orange
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.visibleCases) { tab in
                    Button {
                        appState.selectedSettingsTab = tab
                    } label: {
                        SettingsSidebarRow(title: tab.title, icon: tab.icon)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(appState.selectedSettingsTab == tab
                                          ? Color.accentColor.opacity(0.15)
                                          : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(10)
            .frame(width: 180)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Group {
                switch appState.selectedSettingsTab {
                case .general, .none:
                    GeneralSettingsView()
                case .dictionary:
                    DictionarySettingsView()
                case .smartCleanup:
                    SmartCleanupSettingsView()
                case .macros:
                    VoiceMacrosSettingsView()
                case .runLog:
                    RunLogView()
                case .debug:
                    DebugSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SettingsSidebarRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .regular))
                .frame(width: 16, height: 16, alignment: .center)
                .foregroundStyle(.primary)

            Text(title)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
    }
}

// MARK: - Debug Settings

struct DebugSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Debug")
                    .font(.largeTitle.bold())

                SettingsCard("Overlay", icon: "wrench.and.screwdriver") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Show the recording overlay with simulated audio levels.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(appState.isDebugOverlayActive ? "Stop Debug Overlay" : "Debug Overlay") {
                            appState.toggleDebugOverlay()
                        }
                    }
                }

                SettingsCard("Update Overlay", icon: "arrow.down.circle") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Display the update available overlay after dictation finishes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Toggle("Show after dictation", isOn: $appState.debugShowsUpdateReminderAfterDictation)

                        Button("Show Update Overlay Now") {
                            appState.showDebugUpdateAvailableOverlay()
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL
    @AppStorage("show_menu_bar_icon") private var showMenuBarIcon = false
    @AppStorage("overlay_display_id") private var overlayDisplayID = 0
    @AppStorage("use_compact_overlay") private var useCompactOverlay = true
    @State private var screensVersion = 0
    @State private var micPermissionGranted = false
    @State private var showMutedHint = false
    @State private var copiedBuildInfo = false
    @State private var copiedBuildInfoResetWorkItem: DispatchWorkItem?
    @StateObject private var githubCache = GitHubMetadataCache.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    private let megaphoneRepoURL = URL(string: "https://github.com/Kuberwastaken/megaphone")!

    private var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "\(AppName.displayName)"
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    private var appBuildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "MegaphoneBuildTag") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "unknown"
    }

    private var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var appArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private var buildDiagnosticsText: String {
        "\(appDisplayName) \(appVersion) (\(appBuildNumber))\nmacOS \(macOSVersion) (\(appArchitecture))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // App branding header
                VStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)

                    Text(AppName.displayName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))

                    Text("v\(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("SpeechAnalyzer transcribes while you talk. Megaphone prewarms Apple's on-device language model alongside it, then gives Smart Cleanup a brief moment to tidy the result. If Apple Intelligence is unavailable or slow, the instant Basic pass quietly takes over. Your voice and words stay on this Mac either way.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 430)

                    // GitHub card
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            AsyncImage(url: URL(string: "https://github.com/Kuberwastaken.png?size=88")) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    Color.gray.opacity(0.2)
                                }
                            }
                            .frame(width: 22, height: 22)
                            .clipShape(Circle())

                            Button {
                                openURL(megaphoneRepoURL)
                            } label: {
                                Text("Kuberwastaken/megaphone")
                                    .font(.system(.caption, design: .monospaced).weight(.medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)

                            Spacer()

                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption2)
                                if githubCache.isLoading {
                                    ProgressView().scaleEffect(0.5)
                                } else if let count = githubCache.starCount {
                                    Text("\(count.formatted()) \(count == 1 ? "star" : "stars")")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.yellow.opacity(0.14)))

                            Button {
                                openURL(megaphoneRepoURL)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "star")
                                    Text("Star")
                                }
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.yellow.opacity(0.18)))
                            }
                            .buttonStyle(.plain)
                        }

                        if !githubCache.recentStargazers.isEmpty {
                            Divider()
                            HStack(spacing: 8) {
                                HStack(spacing: -6) {
                                    ForEach(githubCache.recentStargazers) { star in
                                        Button {
                                            openURL(star.user.htmlUrl)
                                        } label: {
                                            AsyncImage(url: star.user.avatarThumbnailUrl) { phase in
                                                switch phase {
                                                case .success(let image):
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                default:
                                                    Color.gray.opacity(0.2)
                                                }
                                            }
                                            .frame(width: 22, height: 22)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .clipped()
                                Text("recently starred")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize()
                                Spacer()
                            }
                            .clipped()
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 4)

                SettingsCard("App", icon: "power") {
                    startupSection
                }
                SettingsCard("Updates", icon: "arrow.triangle.2.circlepath") {
                    updatesSection
                }
                SettingsCard("Transcription", icon: "waveform") {
                    OnDeviceTranscriptionSettings()
                }
                SettingsCard("Cleanup", icon: "sparkles") {
                    cleanupSection
                }
                SettingsCard("Output Language", icon: "globe") {
                    outputLanguageSection
                }
                SettingsCard("Dictation Shortcuts", icon: "keyboard.fill") {
                    hotkeySection
                }
                SettingsCard("Ask Megaphone", icon: "sparkles") {
                    wakeCommandSection
                }
                SettingsCard("Audio During Dictation", icon: "speaker.slash.fill") {
                    dictationAudioSection
                }
                SettingsCard("Recording Overlay", icon: "rectangle.dashed") {
                    overlaySection
                }
                SettingsCard("Edit Mode", icon: "pencil") {
                    commandModeSection
                }
                SettingsCard("Clipboard", icon: "doc.on.clipboard") {
                    clipboardSection
                }
                SettingsCard("Microphone", icon: "mic.fill") {
                    microphoneSection
                }
                SettingsCard("Sound Volume", icon: "speaker.wave.2.fill") {
                    soundVolumeSection
                }
                SettingsCard("Permissions", icon: "lock.shield.fill") {
                    permissionsSection
                }
                SettingsCard("Build", icon: "info.circle.fill") {
                    buildInfoSection
                }
            }
            .padding(24)
        }
        .onAppear {
            checkMicPermission()
            appState.refreshLaunchAtLoginStatus()
            Task { await githubCache.fetchIfNeeded() }
        }
    }

    // MARK: Startup

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Launch \(AppName.displayName) at login", isOn: $appState.launchAtLogin)
            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)

            if SMAppService.mainApp.status == .requiresApproval {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Login item requires approval in System Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                    .font(.caption)
                }
            }
        }
    }

    // MARK: Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updateManager.autoCheckEnabled },
                set: { updateManager.autoCheckEnabled = $0 }
            ))

            HStack(spacing: 10) {
                Button {
                    Task {
                        await updateManager.checkForUpdates(userInitiated: true)
                    }
                } label: {
                    if updateManager.isChecking {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking...")
                        }
                    } else {
                        Text("Check for Updates Now")
                    }
                }
                .disabled(updateManager.isChecking || updateManager.updateStatus != .idle)

                if let lastCheck = updateManager.lastCheckDate {
                    Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if updateManager.updateAvailable {
                VStack(alignment: .leading, spacing: 8) {
                    switch updateManager.updateStatus {
                    case .downloading:
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Downloading update...")
                                    .font(.caption.weight(.semibold))
                                ProgressView(value: updateManager.downloadProgress ?? 0)
                                    .progressViewStyle(.linear)
                                if let progress = updateManager.downloadProgress {
                                    Text("\(Int(progress * 100))%")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Cancel") {
                                updateManager.cancelDownload()
                            }
                            .font(.caption)
                        }

                    case .installing:
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Installing update...")
                                .font(.caption.weight(.semibold))
                        }

                    case .readyToRelaunch:
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Relaunching...")
                                .font(.caption.weight(.semibold))
                        }

                    case .error(let message):
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                            Spacer()
                            Button("Retry") {
                                updateManager.updateStatus = .idle
                                if let release = updateManager.latestRelease {
                                    updateManager.downloadAndInstall(release: release)
                                }
                            }
                            .font(.caption)
                        }

                    case .idle:
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                            Text(updateManager.latestReleaseVersion.isEmpty
                                ? "A new version of \(AppName.displayName) is available!"
                                : "\(AppName.displayName) v\(updateManager.latestReleaseVersion) is available!")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button("What's New") {
                                updateManager.showReleaseNotes()
                            }
                            .font(.caption)
                            Button("Update Now") {
                                if let release = updateManager.latestRelease {
                                    updateManager.downloadAndInstall(release: release)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
            }
        }
    }

    // MARK: Build

    private var buildInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Build number")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(appBuildNumber)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(alignment: .top, spacing: 12) {
                Text(buildDiagnosticsText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Spacer()

                Button {
                    copyBuildDiagnostics()
                } label: {
                    Label(copiedBuildInfo ? "Copied" : "Copy", systemImage: copiedBuildInfo ? "checkmark" : "doc.on.doc")
                }
                .font(.caption)
            }
        }
    }

    private func copyBuildDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(buildDiagnosticsText, forType: .string)
        copiedBuildInfo = true

        copiedBuildInfoResetWorkItem?.cancel()

        let resetWorkItem = DispatchWorkItem {
            copiedBuildInfo = false
            copiedBuildInfoResetWorkItem = nil
        }
        copiedBuildInfoResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: resetWorkItem)
    }

    // MARK: Output Language

    private static let outputLanguageOptions = [
        "", "English", "Chinese (Simplified)", "Chinese (Traditional)",
        "Spanish", "French", "Japanese", "Korean", "German", "Portuguese",
        "Hindi", "Hinglish", "Gujarati", "Gujlish",
    ]

    private var outputLanguageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Language", selection: $appState.outputLanguage) {
                Text("Same as spoken").tag("")
                ForEach(Self.outputLanguageOptions.dropFirst(), id: \.self) { language in
                    Text(language).tag(language)
                }
            }
            .pickerStyle(.menu)

            Text("Smart cleanup translates the final text into this language. Exact mode always keeps the spoken language.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Cleanup

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Cleanup Mode", selection: $appState.smartCleanupMode) {
                ForEach(SmartCleanupMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(cleanupModeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if appState.smartCleanupMode == .smart {
                Label("Uses Apple's on-device language model when available, with Basic cleanup as a fast fallback.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                foundationModelStatus
            }
        }
    }

    @ViewBuilder
    private var foundationModelStatus: some View {
        let model = SystemLanguageModel(
            useCase: .general,
            guardrails: .permissiveContentTransformations
        )
        switch model.availability {
        case .available:
            Label("Apple Intelligence is ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unavailable(let reason):
            Label("Basic fallback active: \(String(describing: reason))", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var cleanupModeDescription: String {
        switch appState.smartCleanupMode {
        case .smart:
            return "Removes fillers, resolves corrections, and improves punctuation using on-device intelligence."
        case .basic:
            return "Instant deterministic cleanup for fillers, stutters, repeated words, and spacing."
        case .exact:
            return "Preserves the words you spoke, with only the minimum formatting needed for insertion."
        }
    }

    // MARK: Dictation Shortcuts

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DictationShortcutEditor { isCapturing in
                if isCapturing {
                    appState.suspendHotkeyMonitoringForShortcutCapture()
                } else {
                    appState.resumeHotkeyMonitoringAfterShortcutCapture()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Shortcut Start Delay")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(appState.shortcutStartDelayMilliseconds) ms")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $appState.shortcutStartDelay,
                    in: 0...0.5,
                    step: 0.025
                )

                Text("Applies before recording starts for both hold and tap shortcuts. Stopping still happens immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Ask Megaphone

    private var wakeCommandSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Enable Ask Megaphone", isOn: $appState.wakeCommandsEnabled)
                Text("ALPHA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.purple.opacity(0.12)))
            }

            HStack {
                Text("“Hey Megaphone”")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("Always on")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .opacity(appState.wakeCommandsEnabled ? 1 : 0.5)

            Toggle(
                "Also use “Megaphone”",
                isOn: $appState.plainMegaphoneWakeWordEnabled
            )
            .disabled(!appState.wakeCommandsEnabled)

            Toggle(
                "Use on-screen text as context",
                isOn: $appState.wakeScreenContextEnabled
            )
            .disabled(!appState.wakeCommandsEnabled)

            Text("Inline AI is in alpha. Hold your normal dictation shortcut and start with “Hey Megaphone” to ask a question, generate text, or change your previous dictation — try “make that formal.” Megaphone uses the active app and recent text as on-device context, removes the phrase, and pastes the answer. The shorter trigger is optional. With on-screen text enabled, requests like “reply to this email” read the visible window entirely on-device — via accessibility, or a window snapshot when Screen Recording is already granted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Recording Overlay

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            OverlayStyleOptionRow(
                title: "Minimalist menu-bar overlay",
                subtitle: "Two slim wings flank the camera notch and stay inside the menu bar. Never covers app tabs or toolbars.",
                isMinimalist: true,
                selection: $useCompactOverlay
            )
            OverlayStyleOptionRow(
                title: "Drop-down pill",
                subtitle: "Single pill hangs below the menu bar during recording. Larger and more visible, but covers a thin strip of whatever app is active.",
                isMinimalist: false,
                selection: $useCompactOverlay
            )

            Divider()

            overlayDisplaySection
        }
    }

    // MARK: Audio During Dictation

    private var dictationAudioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "Mute audio when dictation starts",
                isOn: $appState.dictationAudioInterruptionEnabled
            )

            Text("\(AppName.displayName) restores the audio state it changed when dictation ends.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Picks which physical display the recording overlay drops down on.
    /// Without this, AppKit defaults to "the screen with the active key
    /// window" (NSScreen.main), which makes the pill follow focus across
    /// monitors — disorienting on multi-display setups.
    private var overlayDisplaySection: some View {
        HStack {
            Text("Show on")
                .font(.system(size: 13))
            Spacer()
            Picker("", selection: $overlayDisplayID) {
                Text("Active window (default)").tag(0)
                Text("Primary display").tag(-1)
                ForEach(connectedScreenEntries, id: \.tag) { entry in
                    Text(entry.name).tag(entry.tag)
                }
            }
            .labelsHidden()
            .accessibilityLabel("Show on")
            .pickerStyle(.menu)
            .frame(maxWidth: 240)
        }
        // Re-query NSScreen.screens whenever the display arrangement
        // changes so newly-attached monitors appear in the menu without
        // reopening Settings. screensVersion is just a cache-buster.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screensVersion &+= 1
        }
    }

    private var connectedScreenEntries: [(name: String, tag: Int)] {
        _ = screensVersion
        return NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }
            return (name: screen.localizedName, tag: Int(id))
        }
    }

    // MARK: Clipboard

    private var commandModeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Enable Edit Mode", isOn: Binding(
                get: { appState.isCommandModeEnabled },
                set: { _ = appState.setCommandModeEnabled($0) }
            ))

            Text("Transform highlighted text with a spoken instruction instead of dictating over it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Invocation Style", selection: Binding(
                get: { appState.commandModeStyle },
                set: { _ = appState.setCommandModeStyle($0) }
            )) {
                ForEach(CommandModeStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!appState.isCommandModeEnabled)

            if appState.commandModeStyle == .automatic {
                Text("When text is selected, your normal dictation shortcut applies the spoken instruction to it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Extra Modifier", selection: Binding(
                    get: { appState.commandModeManualModifier },
                    set: { _ = appState.setCommandModeManualModifier($0) }
                )) {
                    ForEach(CommandModeManualModifier.allCases) { modifier in
                        Text(modifier.title).tag(modifier)
                    }
                }
                .disabled(!appState.isCommandModeEnabled)
            }

            if let message = appState.commandModeManualModifierValidationMessage {
                Label(message, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var clipboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Preserve clipboard after paste", isOn: $appState.preserveClipboard)

            Text("\(AppName.displayName) will temporarily place the transcript on your clipboard to paste it, then restore whatever was there before. If you copy something else before the restore happens, \(AppName.displayName) leaves it alone.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 2)

            Toggle("Keep dictations in clipboard history", isOn: $appState.keepDictationInClipboardHistory)

            Text("When on, your clipboard manager (Paste, Raycast, Maccy, etc.) records each dictation so you can find it in your recent history. When off, \(AppName.displayName) marks dictations transient and your clipboard manager skips them.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 2)

            Toggle("Say \"press enter\" to submit after paste", isOn: $appState.isPressEnterVoiceCommandEnabled)

            Text("When the transcription ends with \"press enter\", \(AppName.displayName) removes those words before cleanup, pastes the remaining transcript, then presses Return.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Microphone

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select which microphone to use for recording.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                MicrophoneOptionRow(
                    name: "System Default",
                    isSelected: appState.selectedMicrophoneID == "default" || appState.selectedMicrophoneID.isEmpty,
                    action: { appState.selectedMicrophoneID = "default" }
                )
                ForEach(appState.availableMicrophones) { device in
                    MicrophoneOptionRow(
                        name: device.name,
                        isSelected: appState.selectedMicrophoneID == device.uid,
                        action: { appState.selectedMicrophoneID = device.uid }
                    )
                }
            }
        }
        .onAppear {
            appState.refreshAvailableMicrophones()
        }
    }

    // MARK: Sound Volume

    private var soundVolumeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Play alert sounds", isOn: $appState.alertSoundsEnabled)

            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Slider(value: $appState.soundVolume, in: 0...1, step: 0.1)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("\(Int(appState.soundVolume * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
            .disabled(!appState.alertSoundsEnabled)
            .opacity(appState.alertSoundsEnabled ? 1 : 0.5)

            HStack(spacing: 8) {
                Button("Preview") {
                    let muted = SystemAudioStatus.isDefaultOutputMuted()
                    let volume = SystemAudioStatus.defaultOutputVolume()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMutedHint = muted || (volume ?? 1) < 0.10
                    }
                    appState.playStartSound()
                }
                .font(.caption)
                .disabled(!appState.alertSoundsEnabled)

                if showMutedHint {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.slash.fill")
                            .foregroundStyle(.orange)
                        Text("System volume is muted or very low. Unmute to hear the preview.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .transition(.opacity)
                }
            }

            Divider()

            VStack(spacing: 8) {
                soundPickerRow("Recording start", selection: $appState.startSoundName)
                soundPickerRow("Recording stop", selection: $appState.stopSoundName)
                soundPickerRow("Error", selection: $appState.errorSoundName)
            }
            .disabled(!appState.alertSoundsEnabled)
            .opacity(appState.alertSoundsEnabled ? 1 : 0.5)
        }
        .onChange(of: appState.alertSoundsEnabled) { enabled in
            if !enabled { showMutedHint = false }
        }
    }

    /// The stock macOS alert sounds in /System/Library/Sounds, all loadable
    /// by name with NSSound(named:).
    private static let systemSoundNames = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    private func soundPickerRow(_ label: String, selection: Binding<String>) -> some View {
        // Include an off-catalog value (e.g. set via `defaults write`) so the
        // picker shows it instead of rendering blank.
        var options = Self.systemSoundNames
        if !options.contains(selection.wrappedValue) {
            options.append(selection.wrappedValue)
        }
        return HStack(spacing: 8) {
            Text(label)
                .font(.caption)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            Button {
                appState.playAlertSound(named: selection.wrappedValue)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Preview this sound")
        }
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            permissionRow(
                title: "Microphone",
                icon: "mic.fill",
                granted: micPermissionGranted,
                action: {
                    appState.requestMicrophoneAccess { granted in
                        micPermissionGranted = granted
                    }
                }
            )

            permissionRow(
                title: "Accessibility",
                icon: "hand.raised.fill",
                granted: appState.hasAccessibility,
                action: {
                    appState.openAccessibilitySettings()
                }
            )

        }
    }

    private func permissionRow(title: String, icon: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.blue)
            Text(title)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button("Grant Access") {
                    action()
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private func checkMicPermission() {
        micPermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

}

// MARK: - Microphone Option Row

struct MicrophoneOptionRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(name)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dictionary Settings

struct DictionarySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store = DictionaryStore.shared
    @State private var newTerm = ""
    @State private var searchText = ""
    @State private var addError: String?
    @FocusState private var newTermFocused: Bool

    private var suggestions: [DictionaryEntry] {
        store.entries.filter { $0.status == .suggested }
    }

    private var savedEntries: [DictionaryEntry] {
        store.entries.filter { $0.status == .active && matchesSearch($0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsCard("Your Dictionary", icon: "text.book.closed.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Teach Megaphone the names, products, acronyms, and technical terms that make your writing yours. Dictionary words give both transcription and Smart Cleanup the right spelling, and stay on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField("Add a name, term, or phrase", text: $newTerm)
                                .textFieldStyle(.roundedBorder)
                                .focused($newTermFocused)
                                .onSubmit(addTerm)
                            Button("Add", action: addTerm)
                                .buttonStyle(.borderedProminent)
                                .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if let addError {
                            Text(addError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                SettingsCard("Automatic Learning", icon: "sparkles") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Learn words I use often", isOn: $store.automaticLearningEnabled)
                        Text("Megaphone notices likely names and uncommon terms over time. New words start as suggestions and become active after they appear in three successful dictations; you can add, dismiss, disable, or remove them at any time.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !suggestions.isEmpty {
                    SettingsCard("Suggestions", icon: "lightbulb.fill") {
                        VStack(spacing: 0) {
                            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Divider() }
                                dictionaryRow(entry, isSuggestion: true)
                            }
                        }
                    }
                }

                SettingsCard("Saved Words", icon: "character.book.closed.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search dictionary", text: $searchText)
                                .textFieldStyle(.plain)
                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Clear search")
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.1)))

                        if savedEntries.isEmpty {
                            ContentUnavailableView {
                                Label(searchText.isEmpty ? "No saved words yet" : "No matching words", systemImage: "text.book.closed")
                            } description: {
                                Text(searchText.isEmpty ? "Add the words Megaphone should always get right." : "Try a different search.")
                            }
                            .frame(maxWidth: .infinity, minHeight: 130)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(savedEntries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 { Divider() }
                                    dictionaryRow(entry, isSuggestion: false)
                                }
                            }
                        }
                    }
                }

                SettingsCard("Exact Corrections", icon: "arrow.left.arrow.right") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("For words speech consistently hears the wrong way, add one replacement per line using “heard → wanted”.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $appState.wordCorrections)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 70, maxHeight: 130)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        Text("Example: mega phone → Megaphone")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func dictionaryRow(_ entry: DictionaryEntry, isSuggestion: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.term)
                    .font(.body.weight(.medium))
                HStack(spacing: 5) {
                    Text(entry.source == .manual ? "Added by you" : "Learned")
                    if entry.source == .learned && entry.observationCount > 1 {
                        Text("·")
                        Text("Heard \(entry.observationCount) times")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if isSuggestion {
                Button("Dismiss") { store.dismissSuggestion(id: entry.id) }
                    .buttonStyle(.borderless)
                Button("Add") { store.acceptSuggestion(id: entry.id) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Toggle("", isOn: Binding(
                    get: { entry.isEnabled },
                    set: { store.setEnabled($0, for: entry.id) }
                ))
                .labelsHidden()
                .help(entry.isEnabled ? "Stop using this word" : "Use this word")
                Button(role: .destructive) { store.remove(id: entry.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove from Dictionary")
            }
        }
        .padding(.vertical, 9)
    }

    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        do {
            try store.addManual(term)
            newTerm = ""
            addError = nil
            newTermFocused = true
        } catch {
            addError = error.localizedDescription
        }
    }

    private func matchesSearch(_ entry: DictionaryEntry) -> Bool {
        searchText.isEmpty || entry.term.localizedCaseInsensitiveContains(searchText)
    }
}

// MARK: - Prompts Settings

// MARK: - Smart Cleanup Settings

struct SmartCleanupSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var cleanupInstructions = ""
    @State private var contextInstructions = ""
    @FocusState private var cleanupFocused: Bool
    @FocusState private var contextFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsCard("Cleanup Instructions", icon: "text.bubble.fill") {
                    promptEditor(
                        text: $cleanupInstructions,
                        focused: $cleanupFocused,
                        description: "Tell Smart cleanup how you write. You can name trigger words, formatting preferences, or terms that must stay unchanged.",
                        placeholder: "Example: When I say ‘action item’, format the following sentence as a checkbox.",
                        onCommit: commitCleanupInstructions
                    )
                }
                SettingsCard("App Context", icon: "macwindow") {
                    promptEditor(
                        text: $contextInstructions,
                        focused: $contextFocused,
                        description: "Optional hints for using the active app, window title, and selected text to choose the right wording. Context remains on this Mac.",
                        placeholder: "Example: In Xcode, preserve Swift identifiers and Markdown backticks.",
                        onCommit: commitContextInstructions
                    )
                }
                SettingsCard("Safety", icon: "shield.lefthalf.filled") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Dictated prompts are always treated as text", systemImage: "checkmark.shield.fill")
                        Text("Treats dictated text as content to clean, never as a request for the model to answer.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            cleanupInstructions = appState.customSystemPrompt
            contextInstructions = appState.customContextPrompt
        }
        .onDisappear {
            commitCleanupInstructions()
            commitContextInstructions()
        }
    }

    private func promptEditor(
        text: Binding<String>, focused: FocusState<Bool>.Binding,
        description: String, placeholder: String, onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(description).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100, maxHeight: 180)
                .focused(focused)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            if text.wrappedValue.isEmpty {
                Text(placeholder).font(.caption2).foregroundStyle(.tertiary)
            }
            HStack {
                Text(text.wrappedValue.isEmpty ? "Using the built-in defaults" : "Using custom instructions")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !text.wrappedValue.isEmpty {
                    Button("Reset") { text.wrappedValue = ""; onCommit() }.font(.caption)
                }
            }
        }
        .onChange(of: focused.wrappedValue) { isFocused in if !isFocused { onCommit() } }
    }

    private func commitCleanupInstructions() {
        let value = cleanupInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if value != appState.customSystemPrompt {
            appState.customSystemPrompt = value
            appState.customSystemPromptLastModified = value.isEmpty ? "" : iso8601DayFormatter.string(from: Date())
        }
    }

    private func commitContextInstructions() {
        let value = contextInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if value != appState.customContextPrompt {
            appState.customContextPrompt = value
            appState.customContextPromptLastModified = value.isEmpty ? "" : iso8601DayFormatter.string(from: Date())
        }
    }
}

// MARK: - Run Log

struct RunLogView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run Log")
                        .font(.headline)
                    Text("Stored locally. Only the \(appState.maxPipelineHistoryCount) most recent runs are kept.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Clear History") {
                    appState.clearPipelineHistory()
                }
                .disabled(appState.pipelineHistory.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            if appState.pipelineHistory.isEmpty {
                VStack {
                    Spacer()
                    Text("No runs yet. Use dictation to populate history.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(appState.pipelineHistory) { item in
                            RunLogEntryView(item: item)
                        }
                    }
                    .padding(20)
                }
            }
        }
    }
}

// MARK: - Run Log Entry

struct RunLogEntryView: View {
    private let actionIconSize: CGFloat = 28
    let item: PipelineHistoryItem
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = false
    @State private var isRetrying = false
    @State private var showContextPrompt = false
    @State private var showPostProcessingPrompt = false
    @State private var copiedTranscript = false
    @State private var copiedTranscriptResetWorkItem: DispatchWorkItem?
    @State private var copiedRawTranscript = false
    @State private var copiedRawTranscriptResetWorkItem: DispatchWorkItem?
    @State private var copiedCleanedTranscript = false
    @State private var copiedCleanedTranscriptResetWorkItem: DispatchWorkItem?

    private var isError: Bool {
        item.postProcessingStatus.hasPrefix("Error:")
    }

    private var copyableTranscript: String {
        if !item.postProcessedTranscript.isEmpty {
            return item.postProcessedTranscript
        }
        return item.rawTranscript
    }

    @ViewBuilder
    private func actionIconButton(
        systemName: String,
        color: Color = .secondary,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: actionIconSize, height: actionIconSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header
            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: actionIconSize, height: actionIconSize)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        if isError {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.timestamp.formatted(date: .numeric, time: .standard))
                                .font(.subheadline.weight(.semibold))
                            Text(item.postProcessedTranscript.isEmpty ? "(no transcript)" : item.postProcessedTranscript)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    if isError && item.audioFileName != nil {
                        Button {
                            appState.retryTranscription(item: item)
                        } label: {
                            if isRetrying {
                                ProgressView()
                                    .controlSize(.mini)
                                    .frame(width: actionIconSize, height: actionIconSize)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .frame(width: actionIconSize, height: actionIconSize)
                                    .contentShape(Rectangle())
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isRetrying)
                        .help("Retry transcription")
                    } else {
                        Color.clear
                            .frame(width: actionIconSize, height: actionIconSize)
                    }

                    actionIconButton(systemName: "square.and.arrow.up", help: "Export run log") {
                        TestCaseExporter.exportWithSavePanel(
                            item: item,
                            audioDirURL: AppState.audioStorageDirectory()
                        )
                    }

                    actionIconButton(
                        systemName: copiedTranscript ? "checkmark" : "doc.on.doc",
                        color: copiedTranscript ? .green : .secondary,
                        help: copiedTranscript ? "Copied transcript" : "Copy transcript",
                        disabled: copyableTranscript.isEmpty
                    ) {
                        copyTranscriptToPasteboard()
                    }

                    actionIconButton(systemName: "trash", help: "Delete this run") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.deleteHistoryEntry(id: item.id)
                        }
                    }
                }
            }
            .padding(12)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 16) {
                    // Audio player
                    if let audioFileName = item.audioFileName {
                        let audioURL = AppState.audioStorageDirectory().appendingPathComponent(audioFileName)
                        AudioPlayerView(audioURL: audioURL)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("No audio recorded")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Dictionary context captured for this run
                    if !item.customVocabulary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Dictionary Context")
                                .font(.caption.weight(.semibold))
                            FlowLayout(spacing: 4) {
                                ForEach(parseVocabulary(item.customVocabulary), id: \.self) { word in
                                    Text(word)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentColor.opacity(0.12))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }

                    // Pipeline steps
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pipeline")
                            .font(.caption.weight(.semibold))

                        // Step 1: Context Capture
                        PipelineStepView(
                            number: 1,
                            title: "Capture Context",
                            content: {
                                VStack(alignment: .leading, spacing: 6) {
                                    if let dataURL = item.contextScreenshotDataURL,
                                       let image = imageFromDataURL(dataURL) {
                                        Image(nsImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(maxHeight: 120)
                                            .cornerRadius(4)
                                    }

                                    if let prompt = item.contextPrompt, !prompt.isEmpty {
                                        Button {
                                            showContextPrompt.toggle()
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(showContextPrompt ? "Hide Prompt" : "Show Prompt")
                                                    .font(.caption)
                                                Image(systemName: showContextPrompt ? "chevron.up" : "chevron.down")
                                                    .font(.caption2)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Color.accentColor)

                                        if showContextPrompt {
                                            Text(prompt)
                                                .font(.system(.caption2, design: .monospaced))
                                                .textSelection(.enabled)
                                                .padding(8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color(nsColor: .controlBackgroundColor))
                                                .cornerRadius(4)
                                        }
                                    }

                                    if !item.contextSummary.isEmpty {
                                        Text(item.contextSummary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    } else {
                                        Text("No context captured")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        )

                        // Step 2: Transcribe Audio
                        PipelineStepView(
                            number: 2,
                            title: "Transcribe Audio",
                            content: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Sent audio to the configured transcription model")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                    if !item.rawTranscript.isEmpty {
                                        Text(item.rawTranscript)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                            .padding(8)
                                            .padding(.trailing, 24)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(nsColor: .controlBackgroundColor))
                                            .cornerRadius(4)
                                            .overlay(alignment: .topTrailing) {
                                                Button {
                                                    copyRawTranscriptToPasteboard()
                                                } label: {
                                                    Image(systemName: copiedRawTranscript ? "checkmark" : "doc.on.doc")
                                                        .font(.caption)
                                                        .foregroundStyle(copiedRawTranscript ? .green : .secondary)
                                                        .padding(6)
                                                        .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                                .help(copiedRawTranscript ? "Copied literal transcript" : "Copy literal transcript")
                                            }
                                    } else {
                                        Text("(empty transcript)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        )

                        // Step 3: Post-Process
                        PipelineStepView(
                            number: 3,
                            title: "Post-Process",
                            content: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.postProcessingStatus)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)

                                    if let prompt = item.postProcessingPrompt, !prompt.isEmpty {
                                        Button {
                                            showPostProcessingPrompt.toggle()
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(showPostProcessingPrompt ? "Hide Prompt" : "Show Prompt")
                                                    .font(.caption)
                                                Image(systemName: showPostProcessingPrompt ? "chevron.up" : "chevron.down")
                                                    .font(.caption2)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(Color.accentColor)

                                        if showPostProcessingPrompt {
                                            Text(prompt)
                                                .font(.system(.caption2, design: .monospaced))
                                                .textSelection(.enabled)
                                                .padding(8)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .background(Color(nsColor: .controlBackgroundColor))
                                                .cornerRadius(4)
                                        }
                                    }

                                    if !item.postProcessedTranscript.isEmpty {
                                        Text(item.postProcessedTranscript)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                            .padding(8)
                                            .padding(.trailing, 24)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(nsColor: .controlBackgroundColor))
                                            .cornerRadius(4)
                                            .overlay(alignment: .topTrailing) {
                                                Button {
                                                    copyCleanedTranscriptToPasteboard()
                                                } label: {
                                                    Image(systemName: copiedCleanedTranscript ? "checkmark" : "doc.on.doc")
                                                        .font(.caption)
                                                        .foregroundStyle(copiedCleanedTranscript ? .green : .secondary)
                                                        .padding(6)
                                                        .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                                .help(copiedCleanedTranscript ? "Copied cleaned transcript" : "Copy cleaned transcript")
                                            }
                                    }
                                }
                            }
                        )
                    }

                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isError ? Color.red.opacity(0.4) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onReceive(appState.$retryingItemIDs) { ids in
            isRetrying = ids.contains(item.id)
        }
    }

    private func parseVocabulary(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func copyTranscriptToPasteboard() {
        guard !copyableTranscript.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyableTranscript, forType: .string)
        copiedTranscript = true

        copiedTranscriptResetWorkItem?.cancel()
        let resetWorkItem = DispatchWorkItem {
            copiedTranscript = false
            copiedTranscriptResetWorkItem = nil
        }
        copiedTranscriptResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: resetWorkItem)
    }

    private func copyRawTranscriptToPasteboard() {
        guard !item.rawTranscript.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.rawTranscript, forType: .string)
        copiedRawTranscript = true

        copiedRawTranscriptResetWorkItem?.cancel()
        let resetWorkItem = DispatchWorkItem {
            copiedRawTranscript = false
            copiedRawTranscriptResetWorkItem = nil
        }
        copiedRawTranscriptResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: resetWorkItem)
    }

    private func copyCleanedTranscriptToPasteboard() {
        guard !item.postProcessedTranscript.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.postProcessedTranscript, forType: .string)
        copiedCleanedTranscript = true

        copiedCleanedTranscriptResetWorkItem?.cancel()
        let resetWorkItem = DispatchWorkItem {
            copiedCleanedTranscript = false
            copiedCleanedTranscriptResetWorkItem = nil
        }
        copiedCleanedTranscriptResetWorkItem = resetWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: resetWorkItem)
    }
}

// MARK: - Pipeline Step View

struct PipelineStepView<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Audio Player

class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.onFinish?()
        }
    }
}

struct AudioPlayerView: View {
    let audioURL: URL
    @State private var player: AVAudioPlayer?
    @State private var delegate = AudioPlayerDelegate()
    @State private var isPlaying = false
    @State private var duration: TimeInterval = 0
    @State private var elapsed: TimeInterval = 0
    @State private var progressTimer: Timer?

    private var progress: Double {
        guard duration > 0 else { return 0 }
        return min(elapsed / duration, 1.0)
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.body)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.accentColor.opacity(0.15)))
            }
            .buttonStyle(.plain)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, geo.size.width * progress), height: 4)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 28)

            Text("\(formatDuration(elapsed)) / \(formatDuration(duration))")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .onAppear {
            loadDuration()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func loadDuration() {
        guard FileManager.default.fileExists(atPath: audioURL.path) else { return }
        if let p = try? AVAudioPlayer(contentsOf: audioURL) {
            duration = p.duration
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            guard FileManager.default.fileExists(atPath: audioURL.path) else { return }
            do {
                let p = try AVAudioPlayer(contentsOf: audioURL)
                delegate.onFinish = {
                    self.stopPlayback()
                }
                p.delegate = delegate
                p.play()
                player = p
                isPlaying = true
                elapsed = 0
                startProgressTimer()
            } catch {}
        }
    }

    private func stopPlayback() {
        progressTimer?.invalidate()
        progressTimer = nil
        player?.stop()
        player = nil
        isPlaying = false
        elapsed = 0
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if let p = player, p.isPlaying {
                elapsed = p.currentTime
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            guard index < result.positions.count else { break }
            let pos = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func layoutSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Voice Macros Settings

struct VoiceMacrosSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAddMacro = false
    @State private var editingMacro: VoiceMacro?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsCard("Voice Macros", icon: "music.mic") {
                    macrosSection
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showingAddMacro, onDismiss: { editingMacro = nil }) {
            VoiceMacroEditorView(isPresented: $showingAddMacro, macro: $editingMacro)
        }
    }

    private var macrosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bypass post-processing and immediately paste your predefined text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { showingAddMacro = true }) {
                    Text("Add Macro")
                }
            }

            if appState.voiceMacros.isEmpty {
                VStack {
                    Image(systemName: "music.mic")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                        .padding(.bottom, 4)
                    Text("No Voice Macros Yet")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Click 'Add Macro' to define your first voice macro.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                VStack(spacing: 1) {
                    ForEach(Array(appState.voiceMacros.enumerated()), id: \.element.id) { index, macro in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(macro.command)
                                    .font(.headline)
                                Spacer()
                                Button("Edit") {
                                    editingMacro = macro
                                    showingAddMacro = true
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                
                                Button("Delete") {
                                    appState.voiceMacros.removeAll { $0.id == macro.id }
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                            Text(macro.payload)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                    }
                }
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06), lineWidth: 1))
            }
        }
    }
}

struct VoiceMacroEditorView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @Binding var macro: VoiceMacro?

    @State private var command: String = ""
    @State private var payload: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text(macro == nil ? "Add Macro" : "Edit Macro")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Voice Command (What you say)")
                    .font(.caption.weight(.semibold))
                TextField("e.g. debugging prompt", text: $command)
                    .textFieldStyle(.roundedBorder)

                Text("Text (What gets pasted)")
                    .font(.caption.weight(.semibold))
                    .padding(.top, 8)
                TextEditor(text: $payload)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                    macro = nil
                }
                Spacer()
                Button("Save") {
                    let newMacro = VoiceMacro(
                        id: macro?.id ?? UUID(),
                        command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                        payload: payload
                    )
                    
                    if let existingIndex = appState.voiceMacros.firstIndex(where: { $0.id == newMacro.id }) {
                        appState.voiceMacros[existingIndex] = newMacro
                    } else {
                        appState.voiceMacros.append(newMacro)
                    }
                    isPresented = false
                    macro = nil
                }
                .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || payload.isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let m = macro {
                command = m.command
                payload = m.payload
            }
        }
    }
}
