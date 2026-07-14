import Foundation

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
            result.replaceCharacters(in: match.range, with: mapping.replacement)
        }
        return result as String
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
