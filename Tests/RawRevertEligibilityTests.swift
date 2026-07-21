import Foundation

struct RawRevertEligibilityTests {
    static func run() {
        testRevertTargetWhenCleanupEditedTheText()
        testNoRevertWhenCleanupMadeNoEdits()
        testWhitespaceOnlyDifferencesAreNotEdits()
        testEmptySidesAreNeverRevertible()
        testRevertTargetIsTrimmed()
    }

    private static func testRevertTargetWhenCleanupEditedTheText() {
        expectEqual(
            RawRevertEligibility.revertTarget(
                rawTranscript: "um so basically ship it on friday",
                cleanedTranscript: "Ship it on Friday."
            ),
            "um so basically ship it on friday"
        )
    }

    private static func testNoRevertWhenCleanupMadeNoEdits() {
        expect(
            RawRevertEligibility.revertTarget(
                rawTranscript: "Ship it on Friday.",
                cleanedTranscript: "Ship it on Friday."
            ) == nil,
            "Identical raw and cleaned transcripts must not be revertible"
        )
    }

    private static func testWhitespaceOnlyDifferencesAreNotEdits() {
        expect(
            RawRevertEligibility.revertTarget(
                rawTranscript: "  Ship it on Friday.\n",
                cleanedTranscript: "Ship it on Friday."
            ) == nil,
            "Surrounding whitespace alone is not a cleanup edit"
        )
    }

    private static func testEmptySidesAreNeverRevertible() {
        expect(
            RawRevertEligibility.revertTarget(rawTranscript: "", cleanedTranscript: "Hello.") == nil,
            "An empty raw transcript has nothing to revert to"
        )
        expect(
            RawRevertEligibility.revertTarget(rawTranscript: "hello", cleanedTranscript: "") == nil,
            "Nothing was pasted, so there is nothing to replace"
        )
        expect(
            RawRevertEligibility.revertTarget(rawTranscript: "   \n", cleanedTranscript: "Hello.") == nil,
            "A whitespace-only raw transcript has nothing to revert to"
        )
    }

    private static func testRevertTargetIsTrimmed() {
        expectEqual(
            RawRevertEligibility.revertTarget(
                rawTranscript: "  hey there\n",
                cleanedTranscript: "Hey there."
            ),
            "hey there"
        )
    }

    private static func expectEqual(_ actual: String?, _ expected: String, file: StaticString = #file, line: UInt = #line) {
        expect(actual == expected, "Expected \(expected.debugDescription), got \((actual ?? "nil").debugDescription)", file: file, line: line)
    }

    private static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
