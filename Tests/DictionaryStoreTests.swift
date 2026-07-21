import Foundation

enum DictionaryStoreTests {
    static func run() {
        testManualTermsAndProjection()
        testConservativeLearning()
        testAutomaticLearningToggle()
        testManualEntryPromotesSuggestion()
        testLegacyMigrationRunsOnce()
        testPersistence()
        testConservativeCandidateExtraction()
        testDismissedSuggestionStaysDismissed()
        testDecodesEntriesStoredBeforeRanking()
        testPromptRankingOrder()
        testUsageMatchingRespectsWordBoundaries()
        testUsageIncrementsOnlyEnabledEntries()
        testStarAndUsagePersist()
    }

    private static func testManualTermsAndProjection() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        let first = try! store.addManual("  Megaphone  ")
        _ = try! store.addManual("SpeechAnalyzer")
        expectEqual(store.activeTerms, ["Megaphone", "SpeechAnalyzer"])
        store.setEnabled(false, for: first.id)
        expectEqual(store.activeTermsText, "SpeechAnalyzer")
        expectThrows(.duplicateTerm) { try store.addManual("megaphone") }
        expectThrows(.emptyTerm) { try store.addManual("   ") }
    }

    private static func testConservativeLearning() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        store.observe(candidateTerms: ["Kuber", "Kuber"])
        expectEqual(store.entries.first?.observationCount, 1)
        expectEqual(store.entries.first?.status, .suggested)
        expect(store.activeTerms.isEmpty, "A one-off suggestion became active")
        store.observe(candidateTerms: ["kuber"])
        expectEqual(store.entries.first?.observationCount, 2)
        store.observe(candidateTerms: ["Kuber"])
        expectEqual(store.entries.first?.status, .active)
        expectEqual(store.activeTerms, ["Kuber"])
    }

    private static func testManualEntryPromotesSuggestion() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        store.observe(candidateTerms: ["Obsidian"])
        let entry = try! store.addManual("Obsidian")
        expectEqual(entry.source, .manual)
        expectEqual(entry.status, .active)
        expectEqual(store.entries.count, 1)
    }

    private static func testAutomaticLearningToggle() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }
        store.automaticLearningEnabled = false
        store.observe(candidateTerms: ["Cursor"])
        expect(store.entries.isEmpty, "Learning toggle was ignored")

        let reloaded = DictionaryStore(
            defaults: defaults,
            storageKey: "entries",
            migrationKey: "migrated",
            legacyVocabularyKey: "legacy"
        )
        expect(!reloaded.automaticLearningEnabled, "Learning toggle was not persisted")
    }

    private static func testLegacyMigrationRunsOnce() {
        let suite = "DictionaryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set("Megaphone\nSpeechAnalyzer, Kuber; Foundation Models", forKey: "legacy")
        let store = DictionaryStore(
            defaults: defaults,
            storageKey: "entries",
            migrationKey: "migrated",
            legacyVocabularyKey: "legacy"
        )
        expectEqual(Set(store.activeTerms), Set(["Megaphone", "SpeechAnalyzer", "Kuber", "Foundation Models"]))

        defaults.set("A later legacy edit", forKey: "legacy")
        let reloaded = DictionaryStore(
            defaults: defaults,
            storageKey: "entries",
            migrationKey: "migrated",
            legacyVocabularyKey: "legacy"
        )
        expectEqual(Set(reloaded.activeTerms), Set(["Megaphone", "SpeechAnalyzer", "Kuber", "Foundation Models"]))
        defaults.removePersistentDomain(forName: suite)
    }

    private static func testPersistence() {
        let suite = "DictionaryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = DictionaryStore(defaults: defaults, storageKey: "entries", migrationKey: "migrated")
        _ = try! store.addManual("Foundation Models")
        let reloaded = DictionaryStore(defaults: defaults, storageKey: "entries", migrationKey: "migrated")
        expectEqual(reloaded.activeTerms, ["Foundation Models"])
        defaults.removePersistentDomain(forName: suite)
    }

    private static func testConservativeCandidateExtraction() {
        let candidates = DictionaryTermLearner.candidates(
            from: "Please send this to Kuber and keep SpeechAnalyzer, GPT-5, and JSON intact."
        )
        expect(candidates.contains("Kuber"), "Missed a mid-sentence name")
        expect(candidates.contains("SpeechAnalyzer"), "Missed an internal-cap technical term")
        expect(candidates.contains("GPT-5"), "Missed a versioned technical term")
        expect(candidates.contains("JSON"), "Missed an acronym")
        expect(!candidates.contains("Please"), "Learned sentence-initial capitalization")
        expect(!candidates.contains("send"), "Learned an ordinary word")
    }

    private static func testDismissedSuggestionStaysDismissed() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }
        store.observe(candidateTerms: ["Kuber"])
        let entry = store.entries[0]
        store.dismissSuggestion(id: entry.id)
        store.observe(candidateTerms: ["Kuber"])
        expectEqual(store.entries[0].status, .rejected)
        expectEqual(store.entries[0].observationCount, 1)
        let restored = try! store.addManual("Kuber")
        expectEqual(restored.status, .active)
        expectEqual(restored.source, .manual)
    }

    private static func testDecodesEntriesStoredBeforeRanking() {
        let suite = "DictionaryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        // A stored blob from before `starred`/`usageCount` existed.
        let legacyBlob = """
        [{"id":"1B8F4E2A-6C1D-4E5B-9A3F-2D7C8E0B4A61","term":"Megaphone","source":"manual",\
        "status":"active","isEnabled":true,"observationCount":0,"createdAt":776000000,"updatedAt":776000000}]
        """
        defaults.set(Data(legacyBlob.utf8), forKey: "entries")
        defaults.set(true, forKey: "migrated")
        let store = DictionaryStore(
            defaults: defaults,
            storageKey: "entries",
            migrationKey: "migrated",
            legacyVocabularyKey: "legacy"
        )
        expectEqual(store.entries.count, 1)
        expectEqual(store.entries.first?.term, "Megaphone")
        expectEqual(store.entries.first?.starred, false)
        expectEqual(store.entries.first?.usageCount, 0)
        expectEqual(store.activeTerms, ["Megaphone"])
        defaults.removePersistentDomain(forName: suite)
    }

    private static func testPromptRankingOrder() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        _ = try! store.addManual("Obsidian")
        _ = try! store.addManual("Kuber")
        let starredEntry = try! store.addManual("Zig")
        _ = try! store.addManual("Apple")
        store.setStarred(true, for: starredEntry.id)
        store.recordUsage(in: "Ship the Kuber build")
        store.recordUsage(in: "Ping Kuber about Obsidian")

        // Starred beats usage, usage beats alphabetical, alphabetical breaks ties.
        expectEqual(store.activeTerms, ["Zig", "Kuber", "Obsidian", "Apple"])
    }

    private static func testUsageMatchingRespectsWordBoundaries() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        _ = try! store.addManual("AI")
        store.recordUsage(in: "We maintain the daily chain")
        expectEqual(store.entries.first?.usageCount, 0)
        store.recordUsage(in: "The AI pipeline, obviously.")
        expectEqual(store.entries.first?.usageCount, 1)
        // Punctuation is a boundary; repeats within one dictation count once.
        store.recordUsage(in: "ai, ai everywhere")
        expectEqual(store.entries.first?.usageCount, 2)
        expect(DictionaryStore.containsWholeWord("Foundation Models", in: "use Foundation Models."), "Missed a multi-word phrase")
        expect(!DictionaryStore.containsWholeWord("Foundation Models", in: "foundation modelscope"), "Matched inside a longer word")
    }

    private static func testUsageIncrementsOnlyEnabledEntries() {
        let (store, defaults) = makeStore()
        defer { clear(defaults) }

        _ = try! store.addManual("SpeechAnalyzer")
        let disabled = try! store.addManual("Obsidian")
        store.setEnabled(false, for: disabled.id)
        store.observe(candidateTerms: ["Claurst"]) // suggested, not active
        store.recordUsage(in: "SpeechAnalyzer feeds Obsidian and Claurst")
        expectEqual(store.entries.first { $0.term == "SpeechAnalyzer" }?.usageCount, 1)
        expectEqual(store.entries.first { $0.term == "Obsidian" }?.usageCount, 0)
        expectEqual(store.entries.first { $0.term == "Claurst" }?.usageCount, 0)
    }

    private static func testStarAndUsagePersist() {
        let suite = "DictionaryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = DictionaryStore(defaults: defaults, storageKey: "entries", migrationKey: "migrated")
        let entry = try! store.addManual("Megaphone")
        store.setStarred(true, for: entry.id)
        store.recordUsage(in: "Megaphone shipped")
        let reloaded = DictionaryStore(defaults: defaults, storageKey: "entries", migrationKey: "migrated")
        expectEqual(reloaded.entries.first?.starred, true)
        expectEqual(reloaded.entries.first?.usageCount, 1)
        defaults.removePersistentDomain(forName: suite)
    }

    private static func makeStore() -> (DictionaryStore, UserDefaults) {
        let suite = "DictionaryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (
            DictionaryStore(defaults: defaults, storageKey: "entries", migrationKey: "migrated", legacyVocabularyKey: "legacy"),
            defaults
        )
    }

    private static func clear(_ defaults: UserDefaults) {
        guard let suite = defaults.volatileDomainNames.first(where: { $0.hasPrefix("DictionaryStoreTests.") }) else { return }
        defaults.removePersistentDomain(forName: suite)
    }

    private static func expectThrows(_ expected: DictionaryStoreError, operation: () throws -> Void) {
        do {
            try operation()
            fatalError("Expected \(expected)")
        } catch let error as DictionaryStoreError {
            expectEqual(error, expected)
        } catch {
            fatalError("Expected DictionaryStoreError, got \(error)")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }

    private static func expectEqual<T: Equatable>(_ actual: T, _ expected: T) {
        if actual != expected { fatalError("Expected \(expected), got \(actual)") }
    }
}
