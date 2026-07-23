import Foundation

enum SmartCleanupValidationTests {
    static func run() {
        testSpokenProfanitySurvives()
        testTruncatedTranscriptIsRejected()
        testOrdinaryCleanupIsAccepted()
        testListFormattingIsAllowed()
        testBlockMarkdownIsRejected()
        testSelectionTransformsAreUnaffected()
    }

    /// The on-device model sometimes truncates at, or paraphrases around, profanity even
    /// though the system prompt asks it to preserve it. Falling back to basic cleanup keeps
    /// the speaker's words instead of silently censoring them.
    private static func testSpokenProfanitySurvives() {
        expectRejected("What", source: "What the fuck?")
        expectRejected("I think we should ship this.", source: "What the fuck?")
        expectRejected("This is nonsense and I'm annoyed.", source: "This is bullshit and I'm pissed")

        expectAccepted("What the fuck?", source: "What the fuck?")
        expectAccepted("What the fuck, man.", source: "what the fuck man")
        expectAccepted("This is bullshit and I'm pissed.", source: "this is bullshit and I'm pissed")
    }

    private static func testTruncatedTranscriptIsRejected() {
        expectRejected(
            "Let's ship.",
            source: "Let's ship the release on Wednesday once the build finishes and QA signs off."
        )
    }

    private static func testOrdinaryCleanupIsAccepted() {
        expectAccepted("I think we should ship it.", source: "um so I think we should uh ship it you know")
        expectAccepted(
            "Let's meet Wednesday after lunch.",
            source: "let's meet Thursday no actually Wednesday after lunch"
        )
        expectAccepted("Is this working properly now?", source: "Is this working properly now?")
    }

    private static func testListFormattingIsAllowed() {
        expectAccepted("- option one\n- option two", source: "Give me the two options.")
        expectAccepted("1. First\n2. Second", source: "What are the steps?")
    }

    /// Bullets are fine, but fencing or heading plain dictated prose never is.
    private static func testBlockMarkdownIsRejected() {
        expectRejected("```\nShip the build.\n```", source: "Ship the build.")
        expectRejected("# Ship the build.", source: "Ship the build.")
        expectRejected("> Ship the build.", source: "Ship the build.")

        expectAccepted(
            "```\nwrap the next line in a code block\n```",
            source: "wrap the next line in a code block"
        )
    }

    /// Selection rewrites legitimately shorten, expand, or reword text on request.
    private static func testSelectionTransformsAreUnaffected() {
        expectAccepted("Short.", source: "A much longer sentence that the user asked to shorten.", allowsExpansion: true)
        expectAccepted("Please review this.", source: "review this damn thing", allowsExpansion: true)
    }

    private static func expectRejected(
        _ output: String,
        source: String,
        allowsExpansion: Bool = false,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        expect(
            !accepts(output, source: source, allowsExpansion: allowsExpansion),
            "Expected \(output.debugDescription) to be rejected for source \(source.debugDescription)",
            file: file,
            line: line
        )
    }

    private static func expectAccepted(
        _ output: String,
        source: String,
        allowsExpansion: Bool = false,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        expect(
            accepts(output, source: source, allowsExpansion: allowsExpansion),
            "Expected \(output.debugDescription) to be accepted for source \(source.debugDescription)",
            file: file,
            line: line
        )
    }

    private static func accepts(_ output: String, source: String, allowsExpansion: Bool) -> Bool {
        do {
            try AppleFoundationModelsPostProcessor.validate(
                output,
                source: source,
                allowsExpansion: allowsExpansion
            )
            return true
        } catch {
            return false
        }
    }

    private static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
