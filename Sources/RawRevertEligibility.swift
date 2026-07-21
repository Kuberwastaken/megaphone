import Foundation

/// Decides whether a dictation can be reverted to its literal (pre-cleanup)
/// transcript — Wispr Flow calls this "AI edit undo". Pure string logic so it
/// stays unit-testable without AppKit; the accessibility half of the feature
/// (is the cleaned text still at the caret?) lives in AppContextService.
enum RawRevertEligibility {
    /// Returns the raw transcript that should replace the cleaned text, or
    /// nil when reverting would be pointless: nothing was dictated, nothing
    /// was pasted, or the cleanup made no edits at all.
    static func revertTarget(rawTranscript: String, cleanedTranscript: String) -> String? {
        let raw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = cleanedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !cleaned.isEmpty, raw != cleaned else { return nil }
        return raw
    }
}
