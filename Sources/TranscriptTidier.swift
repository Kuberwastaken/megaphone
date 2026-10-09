import Foundation
import NaturalLanguage

/// Fast, deterministic cleanup for literal speech transcripts.
///
/// This deliberately handles only transformations that are unlikely to alter
/// meaning. Semantic rewrites and self-corrections belong to the smart cleanup
/// provider, not this type.
struct TranscriptTidier {
    struct CorrectionMapping: Equatable {
        let spoken: String
        let replacement: String

        /// Parses one mapping per line in either `spoken -> replacement` or
        /// `spoken => replacement` form. Blank lines and `#` comments are
        /// ignored; malformed and empty-sided entries are skipped.
        static func parse(_ text: String) -> [CorrectionMapping] {
            var seen = Set<String>()

            return text.components(separatedBy: .newlines).compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

                let separator: String
                if line.contains("->") {
                    separator = "->"
                } else if line.contains("=>") {
                    separator = "=>"
                } else if line.contains("→") {
                    separator = "→"
                } else {
                    return nil
                }

                let parts = line.components(separatedBy: separator)
                guard parts.count == 2 else { return nil }
                let spoken = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let replacement = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !spoken.isEmpty, !replacement.isEmpty else { return nil }

                let identity = spoken.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
                guard seen.insert(identity).inserted else { return nil }
                return CorrectionMapping(spoken: spoken, replacement: replacement)
            }
        }
    }

    private static let fillerWords: Set<String> = ["uh", "uhh", "uhhh", "uhm", "um", "umm", "ummm", "erm"]
    private static let safelyCollapsibleWords: Set<String> = [
        "a", "an", "and", "are", "at", "but", "for", "he", "i", "in", "is", "it", "of", "or", "she",
        "that", "the", "they", "this", "to", "we", "was", "were", "will", "with", "you"
    ]

    static func tidy(_ transcript: String, corrections: [CorrectionMapping] = []) -> String {
        var result = normalizeWhitespace(transcript)
        guard !result.isEmpty else { return "" }

        result = removeFillers(from: result)
        result = collapseSafeRepeatedWords(in: result)
        result = collapseObviousStutterFragments(in: result)
        result = apply(corrections: corrections, to: result)
        result = normalizePunctuationSpacing(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func apply(corrections: [CorrectionMapping], to transcript: String) -> String {
        let ordered = corrections
            .filter { !$0.spoken.isEmpty && !$0.replacement.isEmpty }
            .sorted { $0.spoken.count > $1.spoken.count }
        guard !ordered.isEmpty else { return transcript }

        let alternatives = ordered.map { mapping in
            mapping.spoken
                .split(whereSeparator: { $0.isWhitespace })
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: #"\s+"#)
        }
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{M}\p{N}_])(?:"# + alternatives.joined(separator: "|") + #")(?![\p{L}\p{M}\p{N}_])"#,
            options: [.caseInsensitive]
        ) else { return transcript }

        let result = NSMutableString(string: transcript)
        let matches = regex.matches(in: transcript, range: NSRange(location: 0, length: result.length))
        for match in matches.reversed() {
            let heard = result.substring(with: match.range)
            let normalizedHeard = heard.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard let mapping = ordered.first(where: {
                $0.spoken.compare(normalizedHeard, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) else { continue }
            // Corrections are re-applied to Smart output that may already
            // contain the replacement; "next -> Next.js" must not produce
            // "Next.js.js" on the second pass.
            let tail = result.substring(from: match.range.location)
            if tail.hasPrefix(mapping.replacement) { continue }
            result.replaceCharacters(in: match.range, with: mapping.replacement)
        }
        return result as String
    }

    // MARK: - Pause punctuation

    /// How much of the speech model's pause-driven punctuation to keep.
    /// SpeechAnalyzer turns pauses into commas, ellipses, and premature
    /// sentence breaks ("the meeting. To Thursday"); this dial strips them.
    enum PunctuationStyle: String, CaseIterable, Identifiable {
        case standard
        case noEllipses
        case minimal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .standard: return "As recognised"
            case .noEllipses: return "No ellipses"
            case .minimal: return "Minimal"
            }
        }
    }

    /// Words that almost never begin a written sentence. A period followed by
    /// one of these is a pause the speech model mistook for a sentence end.
    private static let continuationWords: Set<String> = [
        "and", "or", "nor", "because", "to", "is", "are", "was", "were", "of", "than",
        "with", "which", "whereas", "unless", "until", "into", "onto", "from", "by"
    ]

    /// Removes pause punctuation according to `style`.
    ///
    /// - Parameter adjustCase: lowercase words the speech model capitalized
    ///   only because they followed a pause mark. Disable for text that has
    ///   already been through Smart cleanup, whose capitalization is trusted.
    /// - Parameter protectedTerms: dictionary terms whose casing is never
    ///   changed.
    static func restrainPunctuation(
        _ text: String,
        style: PunctuationStyle,
        adjustCase: Bool = true,
        protectedTerms: [String] = []
    ) -> String {
        guard style != .standard, !text.isEmpty else { return text }
        let protected = Set(protectedTerms.map { $0.lowercased() })
        var result = removeEllipses(from: text, adjustCase: adjustCase, protected: protected)
        if style == .minimal {
            result = removePauseCommas(from: result, adjustCase: adjustCase, protected: protected)
            result = joinFalseSentenceBreaks(in: result)
        }
        return result
    }

    /// "Then I will... Head over" -> "Then I will head over"; a trailing
    /// ellipsis becomes a period. Numeric ranges like `0...5` and leading
    /// spreads like `...args` are left alone.
    private static func removeEllipses(from text: String, adjustCase: Bool, protected: Set<String>) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![\d.])[ \t]*(?:\.{3,}|…)(?=\s|$|["”’)])[ \t]*"#
        ) else { return text }
        let result = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed() {
            let before = result.substring(to: match.range.location)
            let after = result.substring(from: match.range.location + match.range.length)
            let atStart = before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let atEnd = after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let afterStartsLine = after.first?.isNewline == true
            let replacement: String
            if atStart {
                replacement = ""
            } else if atEnd || afterStartsLine {
                replacement = before.last.map { ".!?:;,".contains($0) } == true ? "" : "."
            } else {
                replacement = " "
            }
            result.replaceCharacters(in: match.range, with: replacement)
            if replacement == " ", adjustCase {
                lowercasePauseCapital(in: result, at: match.range.location + 1, protected: protected)
            }
        }
        return result as String
    }

    /// Drops commas followed by a space, which is how SpeechAnalyzer marks a
    /// pause. Digit grouping (`1,000`), line-ending commas ("Hi Sam,") and
    /// genuine lists ("apples, oranges, and pears") are kept.
    private static func removePauseCommas(from text: String, adjustCase: Bool, protected: Set<String>) -> String {
        guard let segmentRegex = try? NSRegularExpression(pattern: #"[^.!?;:\n]+"#),
              let commaRegex = try? NSRegularExpression(pattern: #",[ \t]+"#) else { return text }
        let result = NSMutableString(string: text)
        for segment in segmentRegex.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed() {
            let segmentText = result.substring(with: segment.range)
            guard segmentText.contains(","), !looksLikeList(segmentText) else { continue }
            for comma in commaRegex.matches(in: segmentText, range: NSRange(location: 0, length: (segmentText as NSString).length)).reversed() {
                let location = segment.range.location + comma.range.location
                result.replaceCharacters(in: NSRange(location: location, length: comma.range.length), with: " ")
                if adjustCase {
                    lowercasePauseCapital(in: result, at: location + 1, protected: protected)
                }
            }
        }
        return result as String
    }

    /// A list has at least three comma-separated items, short middle items,
    /// and a final item introduced by "and" or "or".
    private static func looksLikeList(_ segment: String) -> Bool {
        let parts = segment.components(separatedBy: ",").map {
            $0.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() }
        }
        guard parts.count >= 3, let last = parts.last, let first = last.first,
              first == "and" || first == "or" else { return false }
        return parts.dropFirst().dropLast().allSatisfy { (1...4).contains($0.count) }
    }

    /// "the meeting. To Thursday" -> "the meeting to Thursday".
    private static func joinFalseSentenceBreaks(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<=[\p{L}\p{N}])\.[ \t]+(\p{Lu}[\p{Ll}]*)(?![\p{L}\p{N}_'’.])"#) else {
            return text
        }
        let result = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed() {
            let word = result.substring(with: match.range(at: 1))
            guard continuationWords.contains(word.lowercased()) else { continue }
            // "To start, run it." is a real sentence; "To Thursday" is not.
            if word == "To", startsWithInfinitive(result.substring(from: match.range(at: 1).location)) { continue }
            result.replaceCharacters(in: match.range, with: " " + word.lowercased())
        }
        return result as String
    }

    private static func startsWithInfinitive(_ sentence: String) -> Bool {
        let sample = String(sentence.prefix(60))
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = sample
        var classes: [NLTag] = []
        tagger.enumerateTags(in: sample.startIndex..<sample.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, _ in
            if let tag { classes.append(tag) }
            return classes.count < 2
        }
        return classes.count == 2 && classes[1] == .verb
    }

    /// Lowercases the word at `location` when the speech model capitalized it
    /// only because it followed a pause. "I"-forms, acronyms, mixed-case
    /// identifiers, dictionary terms, and recognisable names keep their case.
    private static func lowercasePauseCapital(in text: NSMutableString, at location: Int, protected: Set<String>) {
        guard location < text.length else { return }
        let rest = text.substring(from: location)
        guard let first = rest.first, first.isUppercase else { return }
        let word = String(rest.prefix { $0.isLetter || $0 == "'" || $0 == "’" })
        guard !word.isEmpty else { return }
        let letters = word.filter(\.isLetter)
        let base = word.split(whereSeparator: { $0 == "'" || $0 == "’" }).first.map(String.init) ?? word
        if base == "I" { return }
        if letters.count > 1, letters.dropFirst().contains(where: \.isUppercase) { return }
        if protected.contains(word.lowercased()) || protected.contains(base.lowercased()) { return }
        if isLikelyName(word, in: rest) { return }
        text.replaceCharacters(
            in: NSRange(location: location, length: (word as NSString).length),
            with: word.prefix(1).lowercased() + word.dropFirst()
        )
    }

    private static func isLikelyName(_ word: String, in context: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.nameType])
        let sample = "and " + context.prefix(80)
        tagger.string = sample
        let range = sample.range(of: word) ?? sample.startIndex..<sample.endIndex
        let (tag, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .nameType)
        return tag == .personalName || tag == .placeName || tag == .organizationName
    }

    private static func removeFillers(from text: String) -> String {
        let fillers = fillerWords.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern).joined(separator: "|")
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{M}\p{N}_])(?:"# + fillers + #")(?![\p{L}\p{M}\p{N}_])"#,
            options: [.caseInsensitive]
        ) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static func collapseSafeRepeatedWords(in text: String) -> String {
        var result = text
        for word in safelyCollapsibleWords {
            guard let regex = try? NSRegularExpression(
                pattern: #"(?<![\p{L}\p{M}\p{N}_])("# + NSRegularExpression.escapedPattern(for: word) + #")(?:\s+\1)+(?![\p{L}\p{M}\p{N}_])"#,
                options: [.caseInsensitive]
            ) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
        }
        return result
    }

    private static func collapseObviousStutterFragments(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![\p{L}\p{M}\p{N}_])([\p{L}]{1,3})[-–—]\s+\1([\p{L}\p{M}]+)(?![\p{L}\p{M}\p{N}_])"#,
            options: [.caseInsensitive]
        ) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1$2")
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizePunctuationSpacing(_ text: String) -> String {
        var result = text
        // Removing a filler from between matching pause marks should remove
        // the empty pause too: "I, uh, think" -> "I think".
        result = result.replacingOccurrences(of: #",\s*,"#, with: " ", options: .regularExpression)
        // ASCII `--` is common in URLs, flags, and source code. Only collapse
        // paired typographic pause dashes left behind by filler removal.
        result = result.replacingOccurrences(of: #"[–—]\s*[–—]"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"([,.;:!?]){2,}"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"([,;:])\s*([.!?])"#, with: "$2", options: .regularExpression)
        result = result.replacingOccurrences(of: #"^\s*[,;:]\s*"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s*[,;:]\s*$"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result
    }
}
