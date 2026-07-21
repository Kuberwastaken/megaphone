import Foundation

enum ScratchCommandMatcherTests {
    static func run() {
        testWholeUtterancePhrases()
        testPunctuationAndCasingVariants()
        testNonCommandsAreRejected()
    }

    private static func testWholeUtterancePhrases() {
        let commands = [
            "scratch that",
            "scratch this",
            "delete that",
            "delete this"
        ]
        for transcript in commands {
            expect(
                ScratchCommandMatcher.matches(transcript),
                "Did not recognize \(transcript.debugDescription)"
            )
        }
    }

    private static func testPunctuationAndCasingVariants() {
        let variants = [
            "Scratch that.",
            "SCRATCH THAT!",
            "  scratch that…  ",
            "Scratch, that",
            "scratch — that",
            "Delete that?",
            "“Delete this.”",
            "Scratch that\n"
        ]
        for transcript in variants {
            expect(
                ScratchCommandMatcher.matches(transcript),
                "Did not tolerate \(transcript.debugDescription)"
            )
        }
    }

    private static func testNonCommandsAreRejected() {
        let rejected = [
            "",
            "   ",
            "scratch",
            "that",
            "scratch that itch please",
            "please scratch that",
            "scratch that and start over",
            "you can scratch that",
            "delete that file from the repo",
            "we should scratch that idea",
            "scratched that",
            "scratch thats"
        ]
        for transcript in rejected {
            expect(
                !ScratchCommandMatcher.matches(transcript),
                "False positive for \(transcript.debugDescription)"
            )
        }
    }

    private static func expect(
        _ condition: Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard !condition else { return }
        fatalError("\(file):\(line): \(message)")
    }
}
