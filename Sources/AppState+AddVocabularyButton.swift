import AppKit

// MARK: - Add Vocabulary Button Extension

@MainActor
extension AppState {
    /// Pastes a word (or words) from the macOS pasteboard into the user's custom vocabulary.
    /// Returns the pasted text if successful, or nil otherwise.
    @discardableResult
    func pasteWordToVocabulary() -> String? {
        // Read text from pasteboard (macOS native clipboard API)
        // Check if there's any non-whitespace content to paste
        guard let pastedString = NSPasteboard.general.string(forType: .string),
              !pastedString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        // Clean and prepare the new word(s)
        let wordsToAdd = pastedString
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        guard !wordsToAdd.isEmpty else { return nil }
        
        var added: [String] = []
        for word in wordsToAdd {
            if (try? DictionaryStore.shared.addManual(word)) != nil {
                added.append(word)
            }
        }
        guard !added.isEmpty else { return nil }
        return added.joined(separator: ", ")
    }
}
