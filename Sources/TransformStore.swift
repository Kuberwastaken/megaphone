import Foundation

/// A named, reusable rewrite directive applied to the user's most recent
/// dictation by voice: "Hey Megaphone, polish that".
struct Transform: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var instruction: String
    var isBuiltIn: Bool = false

    /// Only user-defined transforms are persisted; built-ins live in code so
    /// their wording can improve between releases. Anything decoded from
    /// storage is therefore a user transform, never a built-in.
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case instruction
    }
}

/// Built-in transforms plus deterministic voice-invocation matching.
///
/// Matching is intentionally not model-routed: a spoken wake command either
/// names a transform exactly (in one of a few fixed forms) and runs it, or it
/// falls through unchanged to the normal wake-command model.
enum TransformStore {
    static let polishInstruction = """
    Tighten the grammar and flow of the text. Remove filler words and fix awkward or repeated phrasing. Keep the original meaning, tone, and length. Never add information, opinions, or new sentences.
    """

    static let promptInstruction = """
    Restructure the text into a clear instruction for an AI assistant. First line: the goal as one direct imperative sentence. Then the constraints, conditions, and context from the text as short bullet points starting with "-". Keep every requirement from the text; add nothing new and answer nothing.
    """

    static let builtIns: [Transform] = [
        Transform(
            id: UUID(uuidString: "E1A7C7D2-4B1B-4F5A-9A64-6D0B4C8F1A01")!,
            name: "Polish",
            instruction: polishInstruction,
            isBuiltIn: true
        ),
        Transform(
            id: UUID(uuidString: "E1A7C7D2-4B1B-4F5A-9A64-6D0B4C8F1A02")!,
            name: "Prompt",
            instruction: promptInstruction,
            isBuiltIn: true
        )
    ]

    /// Built-ins merged with the user's transforms. A user transform whose
    /// name collides with a built-in (case- and punctuation-insensitively)
    /// shadows it, so "polish" can be re-purposed with custom wording.
    static func resolved(userTransforms: [Transform]) -> [Transform] {
        let userNames = Set(userTransforms.map { normalize($0.name) })
        let visibleBuiltIns = builtIns.filter { !userNames.contains(normalize($0.name)) }
        return visibleBuiltIns + userTransforms
    }

    /// Matches a wake command (wake phrase already stripped) against a
    /// transform invocation. Recognized forms, case- and
    /// punctuation-insensitive: "<name>", "<name> that", "<name> this", and
    /// "apply <name>". Names match whole — "polish that thing up" is not an
    /// invocation and falls through to the normal wake-command path.
    static func match(command: String, in transforms: [Transform]) -> Transform? {
        let normalizedCommand = normalize(command)
        guard !normalizedCommand.isEmpty else { return nil }
        return transforms.first { transform in
            let name = normalize(transform.name)
            guard !name.isEmpty else { return false }
            return normalizedCommand == name
                || normalizedCommand == name + " that"
                || normalizedCommand == name + " this"
                || normalizedCommand == "apply " + name
        }
    }

    /// Lowercases, strips punctuation and symbols, and collapses whitespace
    /// so spoken forms ("Polish that.") match stored names ("polish").
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.punctuationCharacters.union(.symbols))
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
