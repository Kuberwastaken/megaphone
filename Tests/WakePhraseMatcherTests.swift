import Foundation

enum WakePhraseMatcherTests {
    static func run() {
        testHeyMegaphoneIsAlwaysRecognized()
        testPlainMegaphoneToggle()
        testCommonRecognitionAliases()
        testPhraseBoundariesAndPosition()
        testTrailingDictation()
        testPartialResultSuppression()
        testCooldownAndRearming()
        testExplicitRearm()
    }

    private static func testHeyMegaphoneIsAlwaysRecognized() {
        let cases = [
            "hey megaphone",
            "HEY MEGAPHONE",
            "  Hey, Megaphone!",
            "…hey—megaphone"
        ]
        for transcript in cases {
            expectEqual(
                WakePhraseMatcher.detect(in: transcript),
                WakePhraseMatch(phrase: .heyMegaphone, trailingText: ""),
                "Did not recognize \(transcript.debugDescription)"
            )
        }
    }

    private static func testPlainMegaphoneToggle() {
        expectEqual(WakePhraseMatcher.detect(in: "Megaphone"), nil)
        expectEqual(
            WakePhraseMatcher.detect(in: "Megaphone", plainMegaphoneEnabled: true),
            WakePhraseMatch(phrase: .megaphone, trailingText: "")
        )
    }

    private static func testCommonRecognitionAliases() {
        let alwaysOn = [
            "hey mega phone, write this",
            "hey made a phone, write this",
            "he megaphone, write this",
            "he made a phone, write this"
        ]
        for transcript in alwaysOn {
            expectEqual(
                WakePhraseMatcher.detect(in: transcript),
                WakePhraseMatch(phrase: .heyMegaphone, trailingText: "write this"),
                "Did not normalize \(transcript.debugDescription)"
            )
        }

        for transcript in ["mega phone, write this", "made a phone, write this"] {
            expectEqual(WakePhraseMatcher.detect(in: transcript), nil)
            expectEqual(
                WakePhraseMatcher.detect(in: transcript, plainMegaphoneEnabled: true),
                WakePhraseMatch(phrase: .megaphone, trailingText: "write this")
            )
        }
    }

    private static func testPhraseBoundariesAndPosition() {
        let rejected = [
            "megaphones",
            "hey megaphones",
            "The megaphone is loud",
            "They said hey megaphone"
        ]
        for transcript in rejected {
            expectEqual(
                WakePhraseMatcher.detect(in: transcript, plainMegaphoneEnabled: true),
                nil,
                "False positive for \(transcript.debugDescription)"
            )
        }
    }

    private static func testTrailingDictation() {
        expectEqual(
            WakePhraseMatcher.detect(in: "Hey Megaphone, what's 2 + 3?"),
            WakePhraseMatch(phrase: .heyMegaphone, trailingText: "what's 2 + 3?")
        )
        expectEqual(
            WakePhraseMatcher.detect(in: "Hey Megaphone, write this down."),
            WakePhraseMatch(phrase: .heyMegaphone, trailingText: "write this down.")
        )
        expectEqual(
            WakePhraseMatcher.detect(in: "Megaphone — new paragraph", plainMegaphoneEnabled: true),
            WakePhraseMatch(phrase: .megaphone, trailingText: "new paragraph")
        )
    }

    private static func testPartialResultSuppression() {
        let start = Date(timeIntervalSince1970: 100)
        var matcher = WakePhraseMatcher(cooldown: 1)
        expectEqual(matcher.observe("hey megaphone", at: start)?.phrase, .heyMegaphone)
        expectEqual(matcher.observe("hey megaphone write", at: start.addingTimeInterval(0.2)), nil)
        expectEqual(matcher.observe("hey megaphone write this", at: start.addingTimeInterval(2)), nil)
    }

    private static func testCooldownAndRearming() {
        let start = Date(timeIntervalSince1970: 200)
        var matcher = WakePhraseMatcher(cooldown: 1)
        expectEqual(matcher.observe("hey megaphone", at: start)?.phrase, .heyMegaphone)
        expectEqual(matcher.observe("", at: start.addingTimeInterval(0.5)), nil)
        expectEqual(matcher.observe("hey megaphone", at: start.addingTimeInterval(0.6)), nil)
        expectEqual(matcher.observe("", at: start.addingTimeInterval(1.1)), nil)
        expectEqual(matcher.observe("hey megaphone", at: start.addingTimeInterval(1.2))?.phrase, .heyMegaphone)
    }

    private static func testExplicitRearm() {
        let start = Date(timeIntervalSince1970: 300)
        var matcher = WakePhraseMatcher(cooldown: 30)
        _ = matcher.observe("hey megaphone", at: start)
        matcher.rearm()
        expectEqual(matcher.observe("hey megaphone", at: start)?.phrase, .heyMegaphone)
    }

    private static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ message: String = "",
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard actual != expected else { return }
        let context = message.isEmpty ? "" : " \(message)"
        fatalError(
            "\(file):\(line): expected \(String(describing: expected)), got \(String(describing: actual)).\(context)"
        )
    }
}
