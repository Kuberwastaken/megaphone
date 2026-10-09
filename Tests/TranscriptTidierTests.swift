import Foundation

enum TranscriptTidierTests {
    static func run() {
        testFillers()
        testSafeRepeatedWordsAndStutters()
        testMeaningfulSpeechIsPreserved()
        testWhitespaceAndPunctuation()
        testCorrectionParsing()
        testCorrectionApplication()
        testReplacementTextIsNotProcessedAgain()
        testIdempotence()
        testEllipsesRemoved()
        testPauseCommasRemoved()
        testFalseSentenceBreaksJoined()
        testPunctuationKeptWhereMeaningful()
        testCorrectionsAreIdempotent()
    }

    // Inputs below are real SpeechAnalyzer output for speech with pauses.
    private static func restrain(_ text: String, _ style: TranscriptTidier.PunctuationStyle = .minimal, terms: [String] = []) -> String {
        TranscriptTidier.restrainPunctuation(text, style: style, protectedTerms: terms)
    }

    private static func testEllipsesRemoved() {
        expectEqual(
            restrain("Then I will... Head over to the office.", .noEllipses),
            "Then I will head over to the office."
        )
        expectEqual(restrain("And so...", .noEllipses), "And so.")
        expectEqual(restrain("Wait… what happened?", .noEllipses), "Wait what happened?")
        expectEqual(restrain("Well... I think so.", .noEllipses), "Well I think so.")
        expectEqual(restrain("Then... Head out", .standard), "Then... Head out")
    }

    private static func testPauseCommasRemoved() {
        expectEqual(
            restrain("So I was thinking, We should probably move the meeting."),
            "So I was thinking we should probably move the meeting."
        )
        expectEqual(
            restrain("The thing is, the client wants a new onboarding flow, with fewer steps."),
            "The thing is the client wants a new onboarding flow with fewer steps."
        )
        expectEqual(
            restrain("Maybe we could, try the Kubernetes deployment, Vercel style.", terms: ["Vercel"]),
            "Maybe we could try the Kubernetes deployment Vercel style."
        )
    }

    private static func testFalseSentenceBreaksJoined() {
        expectEqual(
            restrain("We should probably move the meeting. To Thursday afternoon, because the design review. Is not ready yet."),
            "We should probably move the meeting to Thursday afternoon because the design review is not ready yet."
        )
        expectEqual(restrain("It shipped. Then we celebrated."), "It shipped. Then we celebrated.")
        expectEqual(restrain("Use version 2. To start, run it."), "Use version 2. To start run it.")
        expectEqual(restrain("Let's talk. To be fair, it was late."), "Let's talk. To be fair it was late.")
    }

    private static func testPunctuationKeptWhereMeaningful() {
        let unchanged = [
            "I need to buy apples, oranges, and pears.",
            "It costs 1,000 dollars.",
            "Hi Sam,\nThanks for the notes.",
            "Use 0...5 as the range.",
            "Spread ...args into the call.",
            "Well, I asked Sarah."
        ]
        expectEqual(restrain(unchanged[0]), unchanged[0])
        expectEqual(restrain(unchanged[1]), unchanged[1])
        expectEqual(restrain(unchanged[2]), unchanged[2])
        expectEqual(restrain(unchanged[3]), unchanged[3])
        expectEqual(restrain(unchanged[4]), unchanged[4])
        expectEqual(restrain(unchanged[5]), "Well I asked Sarah.")
        expectEqual(restrain("I told him, Sarah would call."), "I told him Sarah would call.")
        expectEqual(restrain("Okay, I'll do it."), "Okay I'll do it.")
        expectEqual(restrain("We deploy, NASA reviews."), "We deploy NASA reviews.")
        expectEqual(restrain("Open it, iPhone first."), "Open it iPhone first.")
    }

    private static func testCorrectionsAreIdempotent() {
        let mappings = TranscriptTidier.CorrectionMapping.parse("""
        next -> Next.js
        cuban eats -> Kubernetes
        versel -> Vercel
        """)
        let once = TranscriptTidier.apply(corrections: mappings, to: "Try the Cuban Eats deployment on Versel with next.")
        expectEqual(once, "Try the Kubernetes deployment on Vercel with Next.js.")
        expectEqual(TranscriptTidier.apply(corrections: mappings, to: once), once)
    }

    private static func testFillers() {
        let cases = [
            ("Um I think we should ship it.", "I think we should ship it."),
            ("I, uh, think this works", "I think this works"),
            ("I—uh—think this works", "I think this works"),
            ("uh uhm erm", ""),
            ("UH, hello", "hello"),
            ("That was yummy and the umbra moved.", "That was yummy and the umbra moved.")
        ]
        expectCases(cases)
    }

    private static func testSafeRepeatedWordsAndStutters() {
        let cases = [
            ("I I think the the build works", "I think the build works"),
            ("we we we should go", "we should go"),
            ("th- the release is ready", "the release is ready"),
            ("I w- want this", "I want this")
        ]
        expectCases(cases)
    }

    private static func testMeaningfulSpeechIsPreserved() {
        let unchanged = [
            "This is very very important.",
            "I like the first design.",
            "Use uh_value and umbraColor.",
            "Visit https://example.com/a--b.",
            "हाँ यह बहुत बहुत ज़रूरी है।",
            "The go-go release is intentional."
        ]
        for input in unchanged { expectEqual(TranscriptTidier.tidy(input), input) }
    }

    private static func testWhitespaceAndPunctuation() {
        let cases = [
            ("  hello   world  ", "hello world"),
            ("hello , world !", "hello, world!"),
            ("um, hello", "hello"),
            ("hello, uh", "hello")
        ]
        expectCases(cases)
    }

    private static func testCorrectionParsing() {
        let parsed = TranscriptTidier.CorrectionMapping.parse("""
        # Personal vocabulary
        mega phone -> Megaphone
        jason => JSON
        cube air → Kuber
        bad line
         -> missing
        MEGA PHONE -> duplicate
        too -> many -> arrows
        """)
        expectEqual(parsed, [
            .init(spoken: "mega phone", replacement: "Megaphone"),
            .init(spoken: "jason", replacement: "JSON"),
            .init(spoken: "cube air", replacement: "Kuber")
        ])
    }

    private static func testCorrectionApplication() {
        let mappings = TranscriptTidier.CorrectionMapping.parse("""
        mega phone -> Megaphone
        jason -> JSON
        see plus plus -> C++
        """)
        expectEqual(
            TranscriptTidier.tidy("Use mega   phone with jason and see plus plus.", corrections: mappings),
            "Use Megaphone with JSON and C++."
        )
        expectEqual(
            TranscriptTidier.tidy("The megaphone uses jsonValue.", corrections: mappings),
            "The megaphone uses jsonValue."
        )
    }

    private static func testReplacementTextIsNotProcessedAgain() {
        let mappings = TranscriptTidier.CorrectionMapping.parse("""
        visual studio code -> VS Code
        code -> CODE
        """)
        expectEqual(TranscriptTidier.tidy("Open visual studio code.", corrections: mappings), "Open VS Code.")
    }

    private static func testIdempotence() {
        let inputs = [
            "Um I I think, uh, th- the build works.",
            "This is very very important.",
            "hello , world !"
        ]
        for input in inputs {
            let once = TranscriptTidier.tidy(input)
            expectEqual(TranscriptTidier.tidy(once), once)
        }
    }

    private static func expectCases(_ cases: [(String, String)]) {
        for (input, expected) in cases {
            expectEqual(TranscriptTidier.tidy(input), expected)
        }
    }

    private static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if actual != expected {
            fatalError("\(file):\(line): expected \(String(describing: expected)), got \(String(describing: actual))")
        }
    }
}
