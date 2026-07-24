import Foundation

/// Covers issue #14: the on-device model occasionally wraps its answer in a JSON
/// object or `<cleaned_text>` tags, which `normalizeCommandOutput` must peel so
/// the user gets their text and not the scaffolding.
enum StructuredOutputUnwrapTests {
    static func run() {
        testBareJSONObjectIsUnwrapped()
        testFencedJSONObjectIsUnwrapped()
        testCleanedTextTagsAreStripped()
        testGenuineDataObjectIsUntouched()
        testDictatedCodeBlockSurvives()
        testOrdinaryProseIsUnchanged()
    }

    private static func testBareJSONObjectIsUnwrapped() {
        expect("{\n  \"cleaned_text\": \"Testing, testing.\"\n}", becomes: "Testing, testing.")
        expect("{\"text\": \"- YOLO.\"}", becomes: "- YOLO.")
        expect("{\"clean_text\":\"What's up?\"}", becomes: "What's up?")
    }

    private static func testFencedJSONObjectIsUnwrapped() {
        expect("```json\n{\n  \"cleaned_text\": \"Testing, testing.\"\n}\n```", becomes: "Testing, testing.")
        expect("```\n{\"text\": \"- YOLO.\"}\n```", becomes: "- YOLO.")
    }

    private static func testCleanedTextTagsAreStripped() {
        expect("<cleaned_text>\nWhat's up, my fellow humans?\n</cleaned_text>", becomes: "What's up, my fellow humans?")
        expect("<clean_text>How do you do, fellow kids?</clean_text>", becomes: "How do you do, fellow kids?")
    }

    /// An object whose keys are not all answer-wrappers is real dictated content,
    /// not scaffolding, so it must pass through verbatim.
    private static func testGenuineDataObjectIsUntouched() {
        let object = "{\"name\": \"Ada\", \"text\": \"hello\"}"
        expect(object, becomes: object)
    }

    /// De-fencing is scoped to JSON wrappers, so a code block the user actually
    /// dictated (e.g. via a wake command) keeps its fence.
    private static func testDictatedCodeBlockSurvives() {
        let block = "```swift\nprint(\"hi\")\n```"
        expect(block, becomes: block)
    }

    private static func testOrdinaryProseIsUnchanged() {
        expect("Let's ship the release on Wednesday.", becomes: "Let's ship the release on Wednesday.")
        // A stray brace in prose is not a JSON object and must not be touched.
        expect("Use the {placeholder} token here.", becomes: "Use the {placeholder} token here.")
    }

    private static func expect(
        _ input: String,
        becomes expected: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let actual = AppleFoundationModelsPostProcessor.normalizeCommandOutput(input)
        if actual != expected {
            fatalError(
                "\(file):\(line): normalizeCommandOutput(\(input.debugDescription)) == "
                    + "\(actual.debugDescription), expected \(expected.debugDescription)"
            )
        }
    }
}
