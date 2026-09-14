import Foundation

struct ExcludedAppsTests {
    static func run() {
        testBundleIdentifierNormalization()
        testInitRejectsBlankBundleIdentifier()
        testInitFallsBackToBundleIdentifierAsName()
        testContainsIsCaseAndWhitespaceInsensitive()
        testInsertingDeduplicatesAndSorts()
        testRemoving()
        testSanitizedDropsBlanksAndDuplicates()
        testDecodeRoundTrip()
        testDecodeToleratesCorruptData()
        testSuppressionKeepsOnlyDeactivations()
        testSuppressionIsSkippedWhenItCannotChangeTheOutcome()
    }

    private static func app(_ bundleIdentifier: String, _ name: String) -> ExcludedApp {
        guard let app = ExcludedApp(bundleIdentifier: bundleIdentifier, name: name) else {
            fatalError("Expected a valid ExcludedApp for \(bundleIdentifier)")
        }
        return app
    }

    private static func testBundleIdentifierNormalization() {
        expect(
            ExcludedAppList.normalizedBundleIdentifier("  com.Apple.Terminal ") == "com.apple.terminal",
            "Bundle identifiers must be trimmed and lowercased"
        )
        expect(
            ExcludedAppList.normalizedBundleIdentifier("   ") == nil,
            "Whitespace-only bundle identifiers must normalize to nil"
        )
        expect(
            ExcludedAppList.normalizedBundleIdentifier(nil) == nil,
            "Missing bundle identifiers must normalize to nil"
        )
    }

    private static func testInitRejectsBlankBundleIdentifier() {
        expect(
            ExcludedApp(bundleIdentifier: "", name: "Nameless") == nil,
            "An app without a bundle identifier cannot be excluded"
        )
    }

    private static func testInitFallsBackToBundleIdentifierAsName() {
        let unnamed = app("com.apple.terminal", "   ")
        expect(unnamed.name == "com.apple.terminal", "A blank name falls back to the bundle identifier")

        let named = app("com.apple.terminal", "  Terminal  ")
        expect(named.name == "Terminal", "Names are trimmed")
    }

    private static func testContainsIsCaseAndWhitespaceInsensitive() {
        let apps = [app("com.apple.terminal", "Terminal")]
        expect(
            ExcludedAppList.contains(apps, bundleIdentifier: "com.Apple.Terminal"),
            "Matching must ignore case"
        )
        expect(
            ExcludedAppList.contains(apps, bundleIdentifier: " com.apple.terminal "),
            "Matching must ignore surrounding whitespace"
        )
        expect(
            !ExcludedAppList.contains(apps, bundleIdentifier: "com.apple.safari"),
            "Unrelated apps must not match"
        )
        expect(
            !ExcludedAppList.contains(apps, bundleIdentifier: nil),
            "A missing frontmost bundle identifier is never excluded"
        )
        expect(
            !ExcludedAppList.contains([], bundleIdentifier: "com.apple.terminal"),
            "An empty list excludes nothing"
        )
    }

    private static func testInsertingDeduplicatesAndSorts() {
        var apps = ExcludedAppList.inserting(app("com.apple.terminal", "Terminal"), into: [])
        apps = ExcludedAppList.inserting(app("com.figma.desktop", "Figma"), into: apps)
        expect(apps.map(\.name) == ["Figma", "Terminal"], "Excluded apps are sorted by display name")

        let duplicate = ExcludedAppList.inserting(app("com.Apple.Terminal", "Terminal 2"), into: apps)
        expect(duplicate.count == 2, "Re-adding an excluded app must not duplicate it")
        expect(
            duplicate.map(\.bundleIdentifier) == ["com.figma.desktop", "com.apple.terminal"],
            "Stored identifiers stay normalized and sorted by display name"
        )
    }

    private static func testRemoving() {
        let apps = [app("com.apple.terminal", "Terminal"), app("com.figma.desktop", "Figma")]
        let removed = ExcludedAppList.removing(bundleIdentifier: "com.APPLE.terminal", from: apps)
        expect(removed.map(\.bundleIdentifier) == ["com.figma.desktop"], "Removal must ignore case")
        expect(
            ExcludedAppList.removing(bundleIdentifier: nil, from: apps).count == 2,
            "Removing nil must leave the list untouched"
        )
    }

    private static func testSanitizedDropsBlanksAndDuplicates() {
        let decoded = ExcludedAppList.decoded(
            Data(
                """
                [
                  {"bundleIdentifier": "com.Apple.Terminal", "name": "Terminal"},
                  {"bundleIdentifier": "com.apple.terminal", "name": "Terminal Again"},
                  {"bundleIdentifier": "   ", "name": "Blank"}
                ]
                """.utf8
            )
        )
        expect(decoded.count == 1, "Duplicate and blank entries must be dropped on load")
        expect(decoded.first?.name == "Terminal", "The first entry wins when duplicates are stored")
        expect(
            decoded.first?.bundleIdentifier == "com.apple.terminal",
            "Identifiers stored unnormalized must be repaired on load so matching still works"
        )
    }

    private static func testDecodeRoundTrip() {
        let apps = [app("com.apple.terminal", "Terminal"), app("com.figma.desktop", "Figma")]
        guard let data = ExcludedAppList.encoded(apps) else {
            expect(false, "Excluded apps must encode")
            return
        }
        expect(ExcludedAppList.decoded(data) == ExcludedAppList.sorted(apps), "Excluded apps must round-trip")
    }

    private static func testDecodeToleratesCorruptData() {
        expect(ExcludedAppList.decoded(nil).isEmpty, "Missing preference data yields an empty list")
        expect(
            ExcludedAppList.decoded(Data("not json".utf8)).isEmpty,
            "Corrupt preference data yields an empty list instead of crashing"
        )
    }

    private static func testSuppressionKeepsOnlyDeactivations() {
        let events: [ShortcutEvent] = [
            .holdActivated,
            .toggleActivated,
            .copyAgainTriggered,
            .holdDeactivated,
            .toggleDeactivated
        ]
        expect(
            ShortcutSuppression.eventsAllowedWhileSuppressed(events) == [.holdDeactivated, .toggleDeactivated],
            "While an excluded app is frontmost only deactivations may fire"
        )
        expect(
            ShortcutSuppression.eventsAllowedWhileSuppressed([.holdActivated]).isEmpty,
            "Dictation must never start in an excluded app"
        )
    }

    private static func testSuppressionIsSkippedWhenItCannotChangeTheOutcome() {
        expect(
            !ShortcutSuppression.canSuppress(emittedEvents: [], wouldConsume: false),
            "An ordinary keystroke that fires nothing and is not consumed never needs the frontmost app"
        )
        expect(
            !ShortcutSuppression.canSuppress(emittedEvents: [.holdDeactivated], wouldConsume: false),
            "A deactivation that is not consumed fires either way, so the check is unnecessary"
        )
        expect(
            ShortcutSuppression.canSuppress(emittedEvents: [.holdActivated], wouldConsume: false),
            "An activation must be gated — it is what excluding an app prevents"
        )
        expect(
            ShortcutSuppression.canSuppress(emittedEvents: [.copyAgainTriggered], wouldConsume: false),
            "Paste Again must be gated like any other activation"
        )
        expect(
            ShortcutSuppression.canSuppress(emittedEvents: [.holdDeactivated], wouldConsume: true),
            "A key about to be swallowed must be gated even when only a deactivation fires"
        )
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition {
            print("ExcludedAppsTests failure: \(message)")
            exit(1)
        }
    }
}
