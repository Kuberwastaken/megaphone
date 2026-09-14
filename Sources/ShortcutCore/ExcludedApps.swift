import Foundation

/// One app in which Megaphone's dictation shortcuts are ignored entirely:
/// nothing starts, and the keys are never swallowed, so they reach the app
/// exactly as the app expects.
struct ExcludedApp: Codable, Identifiable, Hashable {
    /// Always stored lowercased so matching against the frontmost app's
    /// bundle identifier is case-insensitive without re-normalizing per event.
    let bundleIdentifier: String
    var name: String

    var id: String { bundleIdentifier }

    init?(bundleIdentifier: String?, name: String?) {
        guard let normalized = ExcludedAppList.normalizedBundleIdentifier(bundleIdentifier) else {
            return nil
        }
        self.bundleIdentifier = normalized
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = trimmedName.isEmpty ? normalized : trimmedName
    }
}

/// Pure list operations for the excluded-app list: normalization, membership,
/// insertion order, and tolerant persistence decoding.
enum ExcludedAppList {
    static func normalizedBundleIdentifier(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }

    static func contains(_ apps: [ExcludedApp], bundleIdentifier: String?) -> Bool {
        guard let normalized = normalizedBundleIdentifier(bundleIdentifier) else { return false }
        return apps.contains { $0.bundleIdentifier == normalized }
    }

    /// Adds `app` unless its bundle identifier is already excluded, keeping the
    /// list sorted by display name so the settings list never reshuffles.
    static func inserting(_ app: ExcludedApp, into apps: [ExcludedApp]) -> [ExcludedApp] {
        guard !contains(apps, bundleIdentifier: app.bundleIdentifier) else { return apps }
        return sorted(apps + [app])
    }

    static func removing(bundleIdentifier: String?, from apps: [ExcludedApp]) -> [ExcludedApp] {
        guard let normalized = normalizedBundleIdentifier(bundleIdentifier) else { return apps }
        return apps.filter { $0.bundleIdentifier != normalized }
    }

    static func sorted(_ apps: [ExcludedApp]) -> [ExcludedApp] {
        apps.sorted { lhs, rhs in
            let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if comparison == .orderedSame {
                return lhs.bundleIdentifier < rhs.bundleIdentifier
            }
            return comparison == .orderedAscending
        }
    }

    /// Repairs what a hand-edited or older preference could leave behind:
    /// drops blank identifiers and duplicates, and re-normalizes identifiers
    /// that were stored before they went through `ExcludedApp.init`.
    static func sanitized(_ apps: [ExcludedApp]) -> [ExcludedApp] {
        var seen: Set<String> = []
        var result: [ExcludedApp] = []
        for app in apps {
            guard let normalized = ExcludedApp(
                bundleIdentifier: app.bundleIdentifier,
                name: app.name
            ) else { continue }
            guard seen.insert(normalized.bundleIdentifier).inserted else { continue }
            result.append(normalized)
        }
        return sorted(result)
    }

    static func decoded(_ data: Data?) -> [ExcludedApp] {
        guard let data,
              let decoded = try? JSONDecoder().decode([ExcludedApp].self, from: data) else {
            return []
        }
        return sanitized(decoded)
    }

    static func encoded(_ apps: [ExcludedApp]) -> Data? {
        try? JSONEncoder().encode(apps)
    }
}

/// What survives while the frontmost app is excluded. Activations are dropped
/// so dictation never starts there; deactivations still flow so a session
/// started in a normal app ends cleanly if focus moves to an excluded app
/// mid-hold.
enum ShortcutSuppression {
    static func isDeactivation(_ event: ShortcutEvent) -> Bool {
        switch event {
        case .holdDeactivated, .toggleDeactivated:
            return true
        case .holdActivated, .toggleActivated, .copyAgainTriggered:
            return false
        }
    }

    static func eventsAllowedWhileSuppressed(_ events: [ShortcutEvent]) -> [ShortcutEvent] {
        events.filter(isDeactivation)
    }

    /// Whether excluding the frontmost app could change this result at all.
    /// When false, suppressing and not suppressing do exactly the same thing —
    /// the same events fire and the key passes through either way — so the
    /// caller can skip asking which app is in front. This is what keeps the
    /// check off the path of ordinary typing: the event tap sees every
    /// keystroke on the system, but only the ones that engage the configured
    /// shortcut have an outcome worth gating.
    static func canSuppress(emittedEvents: [ShortcutEvent], wouldConsume: Bool) -> Bool {
        wouldConsume || emittedEvents.contains { !isDeactivation($0) }
    }
}
