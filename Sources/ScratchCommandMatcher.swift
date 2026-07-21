import Foundation

/// Recognizes whole-utterance "scratch that" commands that ask Megaphone to
/// delete the previously inserted dictation instead of pasting new text.
///
/// Matching is deliberately strict: after trimming, casing, and punctuation
/// tolerance, the entire utterance must be one of a small set of phrases.
/// "Scratch that itch, please" is regular dictation, not a command.
enum ScratchCommandMatcher {
    static func matches(_ transcript: String) -> Bool {
        let normalized = normalize(transcript)
        guard !normalized.isEmpty else { return false }
        return phrases.contains(normalized)
    }

    /// Lowercases and collapses every run of whitespace, punctuation, or
    /// symbols into a single separator so "Scratch that." and "scratch, that!"
    /// normalize to the same key.
    private static func normalize(_ transcript: String) -> String {
        transcript
            .lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static let phrases: Set<String> = [
        "scratch that",
        "scratch this",
        "delete that",
        "delete this"
    ]

    private static let separators = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)
}
