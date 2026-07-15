import Foundation
import AppKit

// MARK: - Data Models

struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String
    let publishedAt: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

struct SemanticVersion: Comparable, Equatable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [String]

    init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("v") || normalized.hasPrefix("V") {
            normalized.removeFirst()
        }

        let withoutBuildMetadata = normalized.split(separator: "+", maxSplits: 1).first.map(String.init) ?? normalized
        let versionAndPrerelease = withoutBuildMetadata
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        let coreComponents = versionAndPrerelease[0].split(separator: ".").map(String.init)

        guard coreComponents.count == 3,
              let major = Int(coreComponents[0]),
              let minor = Int(coreComponents[1]),
              let patch = Int(coreComponents[2]) else {
            return nil
        }

        let parsedPrerelease: [String]
        if versionAndPrerelease.count > 1 {
            let prereleaseRaw = versionAndPrerelease[1]
            guard !prereleaseRaw.isEmpty else { return nil }
            parsedPrerelease = prereleaseRaw
                .split(separator: ".", omittingEmptySubsequences: false)
                .map(String.init)
            guard parsedPrerelease.allSatisfy({ !$0.isEmpty }) else { return nil }
        } else {
            parsedPrerelease = []
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        prerelease = parsedPrerelease
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        if lhs.prerelease.isEmpty && rhs.prerelease.isEmpty { return false }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }

        for index in 0..<min(lhs.prerelease.count, rhs.prerelease.count) {
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            if left == right { continue }

            let leftNumber = Int(left)
            let rightNumber = Int(right)
            switch (leftNumber, rightNumber) {
            case let (leftNumber?, rightNumber?):
                return leftNumber < rightNumber
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return left < right
            }
        }

        return lhs.prerelease.count < rhs.prerelease.count
    }
}

struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadUrl: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

private struct SemanticRelease {
    let release: GitHubRelease
    let version: SemanticVersion
    let versionString: String
    let publishedDate: Date
    let releaseDateString: String
}

// MARK: - Update Status

enum UpdateStatus: Equatable {
    case idle
    case downloading
    case installing
    case readyToRelaunch
    case error(String)
}

// MARK: - Update Manager

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var updateAvailable = false
    @Published var latestRelease: GitHubRelease?
    @Published var latestReleaseVersion: String = ""
    @Published var latestReleaseDate: String = ""
    @Published var isChecking = false
    @Published var downloadProgress: Double?
    @Published var updateStatus: UpdateStatus = .idle
    @Published var lastCheckDate: Date? {
        didSet {
            if let date = lastCheckDate {
                UserDefaults.standard.set(date, forKey: "updateLastCheckDate")
            }
        }
    }

    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "updateAutoCheckEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "updateAutoCheckEnabled") }
    }

    private var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: "updateSkippedVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "updateSkippedVersion") }
    }

    private var lastPostTranscriptionReminderVersion: String? {
        get { UserDefaults.standard.string(forKey: "updateLastPostTranscriptionReminderVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "updateLastPostTranscriptionReminderVersion") }
    }

    private var lastPostTranscriptionReminderDate: Date? {
        get { UserDefaults.standard.object(forKey: "updateLastPostTranscriptionReminderDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "updateLastPostTranscriptionReminderDate") }
    }

    private let releasesURL = URL(string: "https://api.github.com/repos/Kuberwastaken/megaphone/releases?per_page=100")!
    private let stabilityBufferDays: TimeInterval = 3
    private let checkIntervalSeconds: TimeInterval = 7 * 24 * 60 * 60 // 7 days
    private let postTranscriptionReminderInterval: TimeInterval = 24 * 60 * 60 // 1 day
    private var periodicTimer: Timer?
    private var activeDownloadTask: Task<Void, Never>?

    private init() {
        lastCheckDate = UserDefaults.standard.object(forKey: "updateLastCheckDate") as? Date
    }

    // MARK: - Periodic Checks

    func startPeriodicChecks() {
        // Initial check after 5 second delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if self.shouldAutoCheck() {
                    await self.checkForUpdates(userInitiated: false)
                }
            }
        }

        // Re-evaluate hourly (handles sleep/wake)
        periodicTimer?.invalidate()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.shouldAutoCheck() {
                    await self.checkForUpdates(userInitiated: false)
                }
            }
        }
        // Exact firing time does not matter for an hourly check; tolerance
        // lets the system coalesce the wakeup with other timers to save power.
        periodicTimer?.tolerance = 300
    }

    private func shouldAutoCheck() -> Bool {
        guard autoCheckEnabled else { return false }
        guard let lastCheck = lastCheckDate else { return true }
        return Date().timeIntervalSince(lastCheck) > checkIntervalSeconds
    }

    // MARK: - Check for Updates

    @MainActor
    func checkForUpdates(userInitiated: Bool) async {
        let currentBuildTag = Bundle.main.infoDictionary?["MegaphoneBuildTag"] as? String
        let currentVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

        // Dev builds (no embedded tag): skip auto-checks, but allow manual checks
        if !userInitiated && currentBuildTag == nil {
            return
        }

        isChecking = true
        defer { isChecking = false }

        do {
            var request = URLRequest(url: releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                if userInitiated { showErrorAlert("Could not reach GitHub.") }
                return
            }

            // 404 means no releases exist yet
            if httpResponse.statusCode == 404 {
                lastCheckDate = Date()
                updateAvailable = false
                latestRelease = nil
                latestReleaseVersion = ""
                latestReleaseDate = ""
                if userInitiated { showUpToDateAlert() }
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if userInitiated { showErrorAlert("GitHub returned status \(httpResponse.statusCode).") }
                return
            }

            let decoder = JSONDecoder()
            let releases = try decoder.decode([GitHubRelease].self, from: data)
            lastCheckDate = Date()

            guard let currentVersion = SemanticVersion(currentVersionString) else {
                updateAvailable = false
                if userInitiated {
                    showErrorAlert("The current app version does not use semantic versioning.")
                }
                return
            }

            let semanticReleases = releaseCandidates(from: releases)
            guard let latestSemanticRelease = semanticReleases.last else {
                updateAvailable = false
                latestRelease = nil
                latestReleaseVersion = ""
                latestReleaseDate = ""
                if userInitiated {
                    showErrorAlert("No semantic version release was found.")
                }
                return
            }

            let latestVersion = latestSemanticRelease.version
            let release = latestSemanticRelease.release
            let includedReleases = semanticReleases
                .filter { currentVersion < $0.version && $0.version <= latestVersion }
                .map(\.release)
            latestRelease = releaseWithAggregatedNotes(latest: release, includedReleases: includedReleases)
            latestReleaseVersion = latestSemanticRelease.versionString
            latestReleaseDate = latestSemanticRelease.releaseDateString

            // If this is the same or an older semantic version, no update is available.
            if let currentTag = currentBuildTag, release.tagName == currentTag {
                updateAvailable = false
                if userInitiated { showUpToDateAlert() }
                return
            }

            if latestVersion <= currentVersion {
                updateAvailable = false
                if userInitiated { showUpToDateAlert() }
                return
            }

            // Check stability buffer (3 days since published)
            let daysSincePublished = Date().timeIntervalSince(latestSemanticRelease.publishedDate) / (24 * 60 * 60)
            if daysSincePublished < stabilityBufferDays {
                if !userInitiated {
                    // Auto-check: silently skip, too new
                    updateAvailable = false
                    return
                }
                // Manual check: let user know and offer the update anyway
                updateAvailable = true
                showRecentReleaseAlert(daysSincePublished: daysSincePublished)
                return
            }

            // Check if user skipped this version (only for auto checks)
            if !userInitiated && skippedVersion == release.tagName {
                updateAvailable = false
                return
            }

            updateAvailable = true

            if userInitiated {
                showUpdateAlert()
            }
        } catch {
            if userInitiated {
                showErrorAlert("Failed to check for updates: \(error.localizedDescription)")
            }
        }
    }

    private func releaseCandidates(from releases: [GitHubRelease]) -> [SemanticRelease] {
        releases.compactMap { release in
            guard let version = SemanticVersion(release.tagName),
                  let publishedDate = releasePublishedDate(from: release.publishedAt) else {
                return nil
            }

            return SemanticRelease(
                release: release,
                version: version,
                versionString: normalizedVersionString(from: release.tagName),
                publishedDate: publishedDate,
                releaseDateString: displayDateString(from: publishedDate)
            )
        }
        .sorted { lhs, rhs in
            if lhs.version == rhs.version {
                return lhs.publishedDate < rhs.publishedDate
            }
            return lhs.version < rhs.version
        }
    }

    private func releaseWithAggregatedNotes(latest: GitHubRelease, includedReleases: [GitHubRelease]) -> GitHubRelease {
        GitHubRelease(
            tagName: latest.tagName,
            name: latest.name,
            body: aggregatedReleaseNotes(from: includedReleases) ?? latest.body,
            htmlUrl: latest.htmlUrl,
            publishedAt: latest.publishedAt,
            assets: latest.assets
        )
    }

    private func aggregatedReleaseNotes(from releases: [GitHubRelease]) -> String? {
        let notes = releases.reversed().compactMap { releaseNotesBody(from: $0.body) }
        guard !notes.isEmpty else { return nil }
        return notes.joined(separator: "\n\n")
    }

    private func releasePublishedDate(from value: String) -> Date? {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let iso8601Basic = ISO8601DateFormatter()
        iso8601Basic.formatOptions = [.withInternetDateTime]

        return iso8601.date(from: value) ?? iso8601Basic.date(from: value)
    }

    private func displayDateString(from date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        return dateFormatter.string(from: date)
    }

    private func normalizedVersionString(from tagName: String) -> String {
        tagName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
            of: "^v",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    func shouldShowPostTranscriptionReminder() -> Bool {
        guard updateAvailable,
              let release = latestRelease,
              updateStatus == .idle,
              skippedVersion != release.tagName else {
            return false
        }

        guard lastPostTranscriptionReminderVersion == release.tagName,
              let lastReminder = lastPostTranscriptionReminderDate else {
            return true
        }

        return Date().timeIntervalSince(lastReminder) > postTranscriptionReminderInterval
    }

    func markPostTranscriptionReminderShown() {
        guard let release = latestRelease else { return }
        lastPostTranscriptionReminderVersion = release.tagName
        lastPostTranscriptionReminderDate = Date()
    }

    private func suppressPostTranscriptionReminder(for tagName: String) {
        lastPostTranscriptionReminderVersion = tagName
        lastPostTranscriptionReminderDate = Date()
    }

    private func clearAvailableUpdate() {
        updateAvailable = false
        latestRelease = nil
        latestReleaseVersion = ""
        latestReleaseDate = ""
    }

    // MARK: - Alerts

    func showUpdateAlert() {
        guard let release = latestRelease else { return }

        let alert = NSAlert()
        alert.messageText = "A New Version is Available"
        let versionText = latestReleaseVersion.isEmpty ? release.tagName : "v\(latestReleaseVersion)"
        alert.informativeText = "\(AppName.displayName) \(versionText) was released \(latestReleaseDate).\n\nWould you like to download the update?"
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "What's New")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Skip This Version")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            downloadAndInstall(release: release)
        case .alertSecondButtonReturn:
            showReleaseNotes(for: release)
            showUpdateAlert()
        case .alertThirdButtonReturn:
            suppressPostTranscriptionReminder(for: release.tagName)
        case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1):
            skippedVersion = release.tagName
            clearAvailableUpdate()
        default:
            break
        }
    }

    private func showRecentReleaseAlert(daysSincePublished: Double) {
        guard let release = latestRelease else { return }

        let hoursAgo = Int(daysSincePublished * 24)
        let ageText = hoursAgo < 1 ? "less than an hour ago" : hoursAgo < 24 ? "\(hoursAgo) hour\(hoursAgo == 1 ? "" : "s") ago" : "\(Int(daysSincePublished)) day\(Int(daysSincePublished) == 1 ? "" : "s") ago"

        let alert = NSAlert()
        alert.messageText = "New Release Available"
        let versionText = latestReleaseVersion.isEmpty ? release.tagName : "v\(latestReleaseVersion)"
        alert.informativeText = "\(AppName.displayName) \(versionText) was released \(ageText). It's very recent — you can download it now or wait a few days for stability.\n\nWould you like to download it?"
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "Download Now")
        alert.addButton(withTitle: "What's New")
        alert.addButton(withTitle: "Wait")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            downloadAndInstall(release: release)
        case .alertSecondButtonReturn:
            showReleaseNotes(for: release)
            showRecentReleaseAlert(daysSincePublished: daysSincePublished)
        default:
            suppressPostTranscriptionReminder(for: release.tagName)
            updateAvailable = false
        }
    }

    func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "You're running the latest version of \(AppName.displayName)."
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func showReleaseNotes() {
        guard let release = latestRelease else { return }
        showReleaseNotes(for: release)
    }

    private func showReleaseNotes(for release: GitHubRelease) {
        let alert = NSAlert()
        let versionText = latestReleaseVersion.isEmpty ? release.tagName : "v\(latestReleaseVersion)"
        alert.messageText = "What's New in \(AppName.displayName) \(versionText)"
        alert.informativeText = "Release notes from GitHub."
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.accessoryView = releaseNotesView(text: releaseNotesText(for: release))
        alert.addButton(withTitle: "OK")

        if let releaseURL = URL(string: release.htmlUrl) {
            alert.addButton(withTitle: "Open on GitHub")
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(releaseURL)
            }
        } else {
            alert.runModal()
        }
    }

    private func releaseNotesText(for release: GitHubRelease) -> String {
        guard let body = releaseNotesBody(from: release.body) else {
            return "No release notes were published for this version."
        }

        return body
    }

    private func releaseNotesBody(from body: String?) -> String? {
        guard let body = body?.trimmingCharacters(in: .whitespacesAndNewlines),
              !body.isEmpty else {
            return nil
        }

        if let downloadRange = body.range(of: "\n## Download") {
            let notes = String(body[..<downloadRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return notes.isEmpty ? nil : notes
        }

        return body
    }

    private func releaseNotesView(text: String) -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 280))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textStorage?.setAttributedString(releaseNotesAttributedString(from: text))

        scrollView.documentView = textView
        return scrollView
    }

    private func releaseNotesAttributedString(from text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let bulletFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let headingFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize + 3)
        let subheadingFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize + 1)
        let baseParagraph = NSMutableParagraphStyle()
        baseParagraph.lineSpacing = 2
        baseParagraph.paragraphSpacing = 6

        let bulletParagraph = NSMutableParagraphStyle()
        bulletParagraph.lineSpacing = 2
        bulletParagraph.paragraphSpacing = 4
        bulletParagraph.firstLineHeadIndent = 0
        bulletParagraph.headIndent = 16

        for rawLine in text.components(separatedBy: .newlines) {
            let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)
            let font: NSFont
            let paragraphStyle: NSParagraphStyle
            let renderedLine: String

            if trimmedLine.hasPrefix("### ") {
                font = subheadingFont
                paragraphStyle = baseParagraph
                renderedLine = String(trimmedLine.dropFirst(4))
            } else if trimmedLine.hasPrefix("## ") {
                font = headingFont
                paragraphStyle = baseParagraph
                renderedLine = String(trimmedLine.dropFirst(3))
            } else if trimmedLine.hasPrefix("- ") {
                font = bulletFont
                paragraphStyle = bulletParagraph
                renderedLine = "• \(trimmedLine.dropFirst(2))"
            } else {
                font = bodyFont
                paragraphStyle = baseParagraph
                renderedLine = rawLine
            }

            result.append(inlineMarkdownAttributedString(
                from: renderedLine,
                font: font,
                paragraphStyle: paragraphStyle
            ))
            result.append(NSAttributedString(string: "\n"))
        }

        return result
    }

    private func inlineMarkdownAttributedString(
        from text: String,
        font: NSFont,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = text[...]

        while let markerRange = remaining.range(of: "**") {
            appendPlainMarkdownText(
                String(remaining[..<markerRange.lowerBound]),
                to: result,
                font: font,
                paragraphStyle: paragraphStyle
            )

            let boldStart = markerRange.upperBound
            guard let boldEndRange = remaining[boldStart...].range(of: "**") else {
                appendPlainMarkdownText(
                    String(remaining[markerRange.lowerBound...]),
                    to: result,
                    font: font,
                    paragraphStyle: paragraphStyle
                )
                return result
            }

            let boldText = String(remaining[boldStart..<boldEndRange.lowerBound])
            let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            appendPlainMarkdownText(
                boldText,
                to: result,
                font: boldFont,
                paragraphStyle: paragraphStyle
            )
            remaining = remaining[boldEndRange.upperBound...]
        }

        appendPlainMarkdownText(String(remaining), to: result, font: font, paragraphStyle: paragraphStyle)
        return result
    }

    private func appendPlainMarkdownText(
        _ text: String,
        to result: NSMutableAttributedString,
        font: NSFont,
        paragraphStyle: NSParagraphStyle
    ) {
        result.append(NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle
            ]
        ))
    }

    private func showErrorAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Download and Install

    func cancelDownload() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        downloadProgress = nil
        updateStatus = .idle
    }

    func downloadAndInstall(release: GitHubRelease) {
        guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            if let url = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        guard let downloadURL = URL(string: dmgAsset.browserDownloadUrl) else { return }

        activeDownloadTask?.cancel()
        activeDownloadTask = Task {
            await performUpdate(
                downloadURL: downloadURL,
                expectedSize: dmgAsset.size,
                expectedVersion: normalizedVersionString(from: release.tagName)
            )
        }
    }

    private func performUpdate(downloadURL: URL, expectedSize: Int, expectedVersion: String) async {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("megaphone-update-\(UUID().uuidString)")

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            updateStatus = .error("Failed to create temp directory: \(error.localizedDescription)")
            return
        }

        let dmgPath = tempDir.appendingPathComponent("Megaphone.dmg")

        // MARK: Download phase
        updateStatus = .downloading
        downloadProgress = 0

        do {
            var request = URLRequest(url: downloadURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let totalSize = (response as? HTTPURLResponse)
                .flatMap { Int($0.value(forHTTPHeaderField: "Content-Length") ?? "") }
                ?? expectedSize

            let outputHandle = try FileHandle(forWritingTo: {
                fm.createFile(atPath: dmgPath.path, contents: nil)
                return dmgPath
            }())

            // Run the byte-iteration and file I/O off the main thread
            let mgr = self
            let downloadTask = Task.detached {
                defer { try? outputHandle.close() }
                var receivedBytes = 0
                let bufferSize = 65_536
                var buffer = Data()
                buffer.reserveCapacity(bufferSize)
                var lastProgressUpdate = CFAbsoluteTimeGetCurrent()

                for try await byte in asyncBytes {
                    try Task.checkCancellation()
                    buffer.append(byte)
                    if buffer.count >= bufferSize {
                        outputHandle.write(buffer)
                        receivedBytes += buffer.count
                        buffer.removeAll(keepingCapacity: true)

                        // Throttle progress updates to ~30fps
                        let now = CFAbsoluteTimeGetCurrent()
                        if totalSize > 0 && (now - lastProgressUpdate) >= 0.033 {
                            lastProgressUpdate = now
                            let progress = Double(receivedBytes) / Double(totalSize)
                            await MainActor.run {
                                mgr.downloadProgress = progress
                            }
                        }
                    }
                }

                // Write remaining bytes
                if !buffer.isEmpty {
                    outputHandle.write(buffer)
                    receivedBytes += buffer.count
                }
                return receivedBytes
            }

            let receivedBytes = try await downloadTask.value
            if expectedSize > 0 && receivedBytes != expectedSize {
                throw NSError(domain: "UpdateManager", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "Downloaded update size did not match the release asset"
                ])
            }
            downloadProgress = 1.0

        } catch is CancellationError {
            try? fm.removeItem(at: tempDir)
            return
        } catch let error as URLError where error.code == .cancelled {
            try? fm.removeItem(at: tempDir)
            return
        } catch {
            updateStatus = .error("Download failed: \(error.localizedDescription)")
            downloadProgress = nil
            try? fm.removeItem(at: tempDir)
            return
        }

        // MARK: Install phase - mount DMG, extract app
        updateStatus = .installing
        downloadProgress = nil

        do {
            let mountPoint = try await Task.detached {
                try self.mountDMG(at: dmgPath)
            }.value

            defer {
                // Always try to detach
                let detach = Process()
                detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                detach.arguments = ["detach", mountPoint, "-quiet"]
                try? detach.run()
                detach.waitUntilExit()
            }

            // Find the .app inside the mounted volume
            let volumeURL = URL(fileURLWithPath: mountPoint)
            let contents = try fm.contentsOfDirectory(at: volumeURL, includingPropertiesForKeys: nil)
            guard let appBundle = contents.first(where: { $0.pathExtension == "app" }) else {
                updateStatus = .error("No .app found in DMG.")
                try? fm.removeItem(at: tempDir)
                return
            }

            // Copy app to staging directory
            let stagingDir = fm.temporaryDirectory.appendingPathComponent("megaphone-staged-\(UUID().uuidString)")
            try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            do {
                let stagedApp = stagingDir.appendingPathComponent(appBundle.lastPathComponent)
                try fm.copyItem(at: appBundle, to: stagedApp)

                try await Task.detached {
                    try self.validateStagedApp(
                        stagedApp,
                        currentApp: Bundle.main.bundleURL,
                        expectedVersion: expectedVersion
                    )
                }.value

                // Clean up DMG (detach happens in defer above, delete temp dir)
                try? fm.removeItem(at: tempDir)

                // MARK: Replace & relaunch
                updateStatus = .readyToRelaunch
                try replaceAndRelaunch(
                    stagedApp: stagedApp,
                    stagingDir: stagingDir,
                    expectedVersion: expectedVersion
                )
            } catch {
                // Once the helper launches it owns this directory. Before then,
                // validation and launch failures should not leave staged apps behind.
                try? fm.removeItem(at: stagingDir)
                throw error
            }

        } catch {
            updateStatus = .error("Install failed: \(error.localizedDescription)")
            try? fm.removeItem(at: tempDir)
        }
    }

    nonisolated private func mountDMG(at path: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", path.path, "-nobrowse", "-noverify", "-noautoopen", "-plist"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "UpdateManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "hdiutil attach failed with exit code \(process.terminationStatus)"
            ])
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        // Parse the plist output to find mount point
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw NSError(domain: "UpdateManager", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not parse hdiutil output"
            ])
        }

        // Find the mount point from the entities
        for entity in entities {
            if let mountPoint = entity["mount-point"] as? String {
                return mountPoint
            }
        }

        throw NSError(domain: "UpdateManager", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "No mount point found in hdiutil output"
        ])
    }

    nonisolated private func validateStagedApp(
        _ stagedApp: URL,
        currentApp: URL,
        expectedVersion: String
    ) throws {
        guard let info = NSDictionary(contentsOf: stagedApp.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == "com.kuberwastaken.megaphone",
              info["CFBundleShortVersionString"] as? String == expectedVersion else {
            throw NSError(domain: "UpdateManager", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "The downloaded app has an unexpected identity or version"
            ])
        }

        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        verify.arguments = ["--verify", "--deep", "--strict", stagedApp.path]
        verify.standardOutput = Pipe()
        verify.standardError = Pipe()
        try verify.run()
        verify.waitUntilExit()
        guard verify.terminationStatus == 0 else {
            throw NSError(domain: "UpdateManager", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "The downloaded app failed code-signature verification"
            ])
        }

        guard try designatedRequirement(of: stagedApp) == designatedRequirement(of: currentApp) else {
            throw NSError(domain: "UpdateManager", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "The downloaded app was not signed by the expected publisher"
            ])
        }
    }

    nonisolated private func designatedRequirement(of app: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "-r-", app.path]
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        // `codesign` has emitted the designated requirement on stderr on
        // older macOS versions and stdout on newer ones. Read both; otherwise
        // a valid update can be rejected simply because the tool changed
        // which stream it uses.
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = [outputData, errorData]
            .compactMap { String(data: $0, encoding: .utf8) }
            .joined(separator: "\n")
        guard process.terminationStatus == 0,
              let requirement = output.components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("designated => ") }) else {
            throw NSError(domain: "UpdateManager", code: 8, userInfo: [
                NSLocalizedDescriptionKey: "Could not verify the app publisher"
            ])
        }
        return requirement
    }

    private func replaceAndRelaunch(
        stagedApp: URL,
        stagingDir: URL,
        expectedVersion: String
    ) throws {
        let currentAppPath = Bundle.main.bundlePath
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let backupPath = stagingDir.appendingPathComponent("Megaphone Backup.app").path
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Megaphone", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let logPath = logsDirectory.appendingPathComponent("updater.log").path

        // Keep the /Applications/Megaphone.app directory itself in place.
        // macOS App Management may reject renaming/removing that directory,
        // while allowing an updater to replace its children in place.
        let script = """
        exec >>"$7" 2>&1
        echo "$(date -u +%FT%TZ) updater started: expected $6"
        for ((attempt = 0; attempt < 150; attempt++)); do
            kill -0 "$1" 2>/dev/null || break
            sleep 0.2
        done
        kill -0 "$1" 2>/dev/null && { echo "timed out waiting for app to quit"; exit 1; }
        /usr/bin/ditto "$2" "$5" \
            && /usr/bin/codesign --verify --deep --strict "$5" \
            || { echo "backup failed; leaving staged files at $4"; exit 1; }
        if /usr/bin/find "$2" -mindepth 1 -delete \
            && /usr/bin/ditto "$3" "$2" \
            && /usr/bin/codesign --verify --deep --strict "$2" \
            && test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$2/Contents/Info.plist")" = "$6"; then
            echo "install verified; relaunching $6"
            if /usr/bin/open "$2"; then
                /bin/rm -rf "$4"
                exit 0
            fi
            echo "relaunch failed; restoring previous app"
        else
            echo "install failed; restoring previous app"
        fi
        if /usr/bin/find "$2" -mindepth 1 -delete \
            && /usr/bin/ditto "$5" "$2" \
            && /usr/bin/codesign --verify --deep --strict "$2" \
            && test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$2/Contents/Info.plist")" = "$8" \
            && /usr/bin/open "$2"; then
            echo "rollback verified; relaunched $8"
            exit 1
        fi
        echo "CRITICAL: rollback failed; recovery files retained at $4"
        exit 2
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script, "--",
                             pid,                // $1
                             currentAppPath,     // $2
                             stagedApp.path,      // $3
                             stagingDir.path,     // $4
                             backupPath,          // $5
                             expectedVersion,     // $6
                             logPath,             // $7
                             currentVersion]      // $8
        try process.run()

        // Quit only after the durable helper successfully launches.
        NSApp.terminate(nil)
    }
}
