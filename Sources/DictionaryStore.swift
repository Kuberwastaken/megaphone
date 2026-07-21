import Foundation
import Combine

struct DictionaryEntry: Codable, Identifiable, Equatable {
    enum Source: String, Codable, CaseIterable {
        case manual
        case learned
    }

    enum Status: String, Codable, CaseIterable {
        case suggested
        case active
        case rejected
    }

    var id: UUID
    var term: String
    var source: Source
    var status: Status
    var isEnabled: Bool
    var observationCount: Int
    var starred: Bool
    var usageCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        term: String,
        source: Source,
        status: Status,
        isEnabled: Bool = true,
        observationCount: Int = 0,
        starred: Bool = false,
        usageCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.term = term
        self.source = source
        self.status = status
        self.isEnabled = isEnabled
        self.observationCount = observationCount
        self.starred = starred
        self.usageCount = usageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Entries stored before starring/usage ranking shipped lack these keys;
    /// decode them with safe defaults so existing dictionaries keep loading.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        term = try container.decode(String.self, forKey: .term)
        source = try container.decode(Source.self, forKey: .source)
        status = try container.decode(Status.self, forKey: .status)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        observationCount = try container.decode(Int.self, forKey: .observationCount)
        starred = try container.decodeIfPresent(Bool.self, forKey: .starred) ?? false
        usageCount = try container.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    /// Prompt-facing ranking: starred terms first, then most-used, then
    /// alphabetical — so downstream caps (e.g. `prefix(40)`) keep the terms
    /// the user actually relies on.
    static func promptRanking(_ lhs: DictionaryEntry, _ rhs: DictionaryEntry) -> Bool {
        if lhs.starred != rhs.starred { return lhs.starred }
        if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }
        return lhs.term.localizedCaseInsensitiveCompare(rhs.term) == .orderedAscending
    }
}

enum DictionaryStoreError: LocalizedError, Equatable {
    case emptyTerm
    case duplicateTerm

    var errorDescription: String? {
        switch self {
        case .emptyTerm: return "Enter a word or phrase."
        case .duplicateTerm: return "That word or phrase is already in your Dictionary."
        }
    }
}

/// Local, privacy-preserving vocabulary used by speech recognition and cleanup.
/// Learned entries remain suggestions until independently observed several times.
final class DictionaryStore: ObservableObject {
    static let learningThreshold = 3
    static let learnedEntryLimit = 300
    static let suggestionLimit = 100
    static let shared = DictionaryStore()

    @Published private(set) var entries: [DictionaryEntry]
    @Published var automaticLearningEnabled: Bool {
        didSet { defaults.set(automaticLearningEnabled, forKey: automaticLearningKey) }
    }

    private let defaults: UserDefaults
    private let storageKey: String
    private let migrationKey: String
    private let legacyVocabularyKey: String
    private let automaticLearningKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "dictionary_entries_v1",
        migrationKey: String = "dictionary_migrated_custom_vocabulary_v1",
        legacyVocabularyKey: String = "custom_vocabulary",
        automaticLearningKey: String = "dictionary_automatic_learning_enabled"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.migrationKey = migrationKey
        self.legacyVocabularyKey = legacyVocabularyKey
        self.automaticLearningKey = automaticLearningKey
        self.entries = Self.load(from: defaults, key: storageKey)
        self.automaticLearningEnabled = defaults.object(forKey: automaticLearningKey) == nil
            ? true
            : defaults.bool(forKey: automaticLearningKey)
        migrateLegacyVocabularyIfNeeded()
    }

    var activeTerms: [String] {
        entries
            .filter { $0.status == .active && $0.isEnabled }
            .sorted(by: DictionaryEntry.promptRanking)
            .map(\.term)
    }

    /// Projection consumed by the existing newline-delimited vocabulary pipeline.
    var activeTermsText: String { activeTerms.joined(separator: "\n") }

    @discardableResult
    func addManual(_ term: String, at date: Date = Date()) throws -> DictionaryEntry {
        let term = Self.cleaned(term)
        guard !term.isEmpty else { throw DictionaryStoreError.emptyTerm }

        if let index = index(of: term) {
            guard entries[index].status != .active else {
                throw DictionaryStoreError.duplicateTerm
            }
            entries[index].term = term
            entries[index].source = .manual
            entries[index].status = .active
            entries[index].isEnabled = true
            entries[index].updatedAt = date
            persist()
            return entries[index]
        }

        let entry = DictionaryEntry(
            term: term,
            source: .manual,
            status: .active,
            isEnabled: true,
            observationCount: 0,
            createdAt: date,
            updatedAt: date
        )
        entries.append(entry)
        persist()
        return entry
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isEnabled = enabled
        entries[index].updatedAt = Date()
        persist()
    }

    func setStarred(_ starred: Bool, for id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].starred = starred
        entries[index].updatedAt = Date()
        persist()
    }

    /// Counts which enabled entries a finished dictation actually used, so the
    /// vocabulary ranking favors terms that keep showing up. Called once per
    /// successful dictation with the final pasted transcript; scans enabled
    /// active entries in a single pass and persists at most once.
    func recordUsage(in transcript: String) {
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        var didIncrement = false
        for index in entries.indices where entries[index].status == .active && entries[index].isEnabled {
            guard Self.containsWholeWord(entries[index].term, in: transcript) else { continue }
            entries[index].usageCount += 1
            didIncrement = true
        }
        if didIncrement { persist() }
    }

    /// Case- and diacritic-insensitive containment that only matches at word
    /// boundaries, so "AI" never matches inside "maintain".
    static func containsWholeWord(_ term: String, in text: String) -> Bool {
        guard !term.isEmpty else { return false }
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let found = text.range(
                  of: term,
                  options: [.caseInsensitive, .diacriticInsensitive],
                  range: searchStart..<text.endIndex
              ) {
            let boundedBefore = found.lowerBound == text.startIndex
                || !isWordCharacter(text[text.index(before: found.lowerBound)])
            let boundedAfter = found.upperBound == text.endIndex
                || !isWordCharacter(text[found.upperBound])
            if boundedBefore && boundedAfter { return true }
            searchStart = text.index(after: found.lowerBound)
        }
        return false
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    func acceptSuggestion(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = .active
        entries[index].isEnabled = true
        entries[index].updatedAt = Date()
        persist()
    }

    func dismissSuggestion(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].status = .rejected
        entries[index].isEnabled = false
        entries[index].updatedAt = Date()
        persist()
    }

    /// Records terms proposed by the on-device intelligence layer. A term is
    /// counted at most once per transcript/call, and activates after repeated
    /// observations rather than trusting a one-off recognition mistake.
    func observe(candidateTerms: [String], at date: Date = Date()) {
        guard automaticLearningEnabled else { return }
        let uniqueTerms = Dictionary(grouping: candidateTerms.map(Self.cleaned).filter { !$0.isEmpty }) {
            Self.canonical($0)
        }.compactMap { $0.value.first }

        guard !uniqueTerms.isEmpty else { return }
        let rejected = entries
            .filter { $0.source == .learned && $0.status == .rejected }
            .sorted { $0.updatedAt < $1.updatedAt }
        if rejected.count > Self.learnedEntryLimit {
            let expiredIDs = Set(rejected.prefix(rejected.count - Self.learnedEntryLimit).map(\.id))
            entries.removeAll { expiredIDs.contains($0.id) }
        }
        for term in uniqueTerms {
            if let index = index(of: term) {
                guard entries[index].source == .learned,
                      entries[index].status != .rejected else { continue }
                entries[index].observationCount += 1
                if entries[index].observationCount >= Self.learningThreshold {
                    entries[index].status = .active
                }
                entries[index].updatedAt = date
            } else {
                let learnedEntries = entries.filter { $0.source == .learned && $0.status != .rejected }
                guard learnedEntries.count < Self.learnedEntryLimit,
                      learnedEntries.filter({ $0.status == .suggested }).count < Self.suggestionLimit else {
                    continue
                }
                entries.append(DictionaryEntry(
                    term: term,
                    source: .learned,
                    status: Self.learningThreshold <= 1 ? .active : .suggested,
                    isEnabled: true,
                    observationCount: 1,
                    createdAt: date,
                    updatedAt: date
                ))
            }
        }
        persist()
    }

    private func migrateLegacyVocabularyIfNeeded() {
        guard !defaults.bool(forKey: migrationKey) else { return }
        let legacy = defaults.string(forKey: legacyVocabularyKey) ?? ""
        let terms = legacy
            .components(separatedBy: CharacterSet(charactersIn: "\n,;"))
            .map(Self.cleaned)
            .filter { !$0.isEmpty }

        let now = Date()
        for term in terms where index(of: term) == nil {
            entries.append(DictionaryEntry(
                term: term,
                source: .manual,
                status: .active,
                isEnabled: true,
                createdAt: now,
                updatedAt: now
            ))
        }
        persist()
        defaults.set(true, forKey: migrationKey)
    }

    private func index(of term: String) -> Int? {
        let canonicalTerm = Self.canonical(term)
        return entries.firstIndex { Self.canonical($0.term) == canonicalTerm }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func load(from defaults: UserDefaults, key: String) -> [DictionaryEntry] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([DictionaryEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func cleaned(_ term: String) -> String {
        term
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func canonical(_ term: String) -> String {
        cleaned(term).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

enum DictionaryTermLearner {
    private static let commonWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "do", "for",
        "from", "had", "has", "have", "he", "her", "here", "his", "how", "i", "if",
        "in", "is", "it", "its", "just", "me", "my", "no", "not", "of", "on", "or",
        "our", "please", "she", "so", "that", "the", "their", "them", "then", "there",
        "they", "this", "to", "up", "us", "was", "we", "were", "what", "when", "where",
        "which", "who", "will", "with", "would", "yes", "you", "your"
    ]

    /// Finds conservative names and technical tokens worth observing. A
    /// candidate still needs three separate successful dictations before the
    /// store activates it, so this intentionally favors precision over recall.
    static func candidates(from transcript: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"[\p{L}\p{N}][\p{L}\p{N}'’._+-]{1,63}"#
        ) else { return [] }

        let nsTranscript = transcript as NSString
        let matches = regex.matches(
            in: transcript,
            range: NSRange(location: 0, length: nsTranscript.length)
        )

        return matches.compactMap { match in
            let term = nsTranscript.substring(with: match.range)
            let folded = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !commonWords.contains(folded),
                  !term.contains("@"),
                  !term.lowercased().hasPrefix("http") else { return nil }

            let letters = term.unicodeScalars.filter { CharacterSet.letters.contains($0) }
            guard !letters.isEmpty else { return nil }
            let uppercaseCount = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
            let lowercaseCount = letters.filter { CharacterSet.lowercaseLetters.contains($0) }.count
            let hasNumber = term.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
            let hasTechnicalSeparator = term.contains("-") || term.contains("_") || term.contains("+")
            let isAcronym = uppercaseCount >= 2 && lowercaseCount == 0
            let hasInternalCapital = term.dropFirst().unicodeScalars.contains {
                CharacterSet.uppercaseLetters.contains($0)
            }

            // Capitalized words away from a sentence boundary are likely
            // proper names. Sentence-initial capitalization alone is weak.
            let prefix = nsTranscript.substring(to: match.range.location)
            let prior = prefix.trimmingCharacters(in: .whitespacesAndNewlines).last
            let isSentenceInitial = prior == nil || ".!?".contains(prior!)
            let isMidSentenceName = uppercaseCount >= 1 && !isSentenceInitial

            guard isAcronym || hasInternalCapital || hasNumber || hasTechnicalSeparator || isMidSentenceName else {
                return nil
            }
            return term
        }
    }
}
