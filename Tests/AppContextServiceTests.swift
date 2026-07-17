import Foundation

@main
struct AppContextServiceTests {
    static func main() {
        testQwenRawOutputIsSummarized()
        testQwenReasoningOutputIsStripped()
        testNonStrippingModelPreservesExistingBehavior()
        testWakeCommandIncludesPreviousTextAndScreenContext()
        testWakeCommandResponseWrappersAreRemoved()
        testAppWritingContextClassification()
        testCleanupPromptUsesLocalAppStyle()
        TranscriptTidierTests.run()
        DictionaryStoreTests.run()
        WakePhraseMatcherTests.run()
        print("MegaphoneTests passed")
    }

    private static func testQwenRawOutputIsSummarized() {
        let output = """
        The user is replying to an email about the product launch. They likely intend to confirm the next steps. This third sentence should be dropped.
        """

        let summary = AppContextService.activitySummary(from: output, model: "qwen/qwen3.6-27b")

        expectEqual(
            summary,
            "The user is replying to an email about the product launch. They likely intend to confirm the next steps."
        )
    }

    private static func testQwenReasoningOutputIsStripped() {
        let output = """
        <think>
        Hidden chain of thought should never appear in context.
        It contains misleading details.
        </think>
        The user is editing a project note in Megaphone. They likely intend to tighten the release wording.
        """

        let summary = AppContextService.activitySummary(from: output, model: "qwen/qwen3.6-27b")

        expectEqual(
            summary,
            "The user is editing a project note in Megaphone. They likely intend to tighten the release wording."
        )
        expect(summary?.contains("Hidden chain of thought") == false, "Qwen reasoning leaked into summary")
    }

    private static func testNonStrippingModelPreservesExistingBehavior() {
        let output = "<think>Visible for non-stripping models.</think> The user is writing a status update."

        let summary = AppContextService.activitySummary(
            from: output,
            model: "meta-llama/llama-4-scout-17b-16e-instruct"
        )

        expectEqual(summary, output)
    }

    private static func testWakeCommandIncludesPreviousTextAndScreenContext() {
        let prompt = AppleFoundationModelsPostProcessor.commandPrompt(
            command: "make that formal",
            appName: "Mail",
            bundleIdentifier: "com.apple.mail",
            windowTitle: "Draft — Project update",
            contextSummary: "The user is composing an email reply.",
            selectedText: "Earlier text selected in the draft.",
            previousText: "hey, can you send this over by friday?",
            vocabulary: ["Megaphone"]
        )

        expect(prompt.contains("RECENT TEXT INSERTED BY THE USER:"), "Previous-text label missing")
        expect(prompt.contains("hey, can you send this over by friday?"), "Previous dictation missing")
        expect(prompt.contains("Destination app: Mail"), "Destination app context missing")
        expect(prompt.contains("Writing context: email"), "Email writing context missing")
        expect(prompt.contains("Do not invent a greeting, sign-off, subject, or details."), "Safe email guidance missing")
        expect(prompt.contains("Window: Draft — Project update"), "Window context missing")
        expect(prompt.contains("Context: The user is composing an email reply."), "Screen context missing")
        expect(prompt.contains("Current selected text: Earlier text selected in the draft."), "Selected screen text missing")
        expect(prompt.contains("make that formal"), "Spoken follow-up missing")
    }

    private static func testAppWritingContextClassification() {
        expect(
            AppWritingContext.classify(appName: "Mail", bundleIdentifier: "com.apple.mail", windowTitle: nil) == .email,
            "Mail should use email writing context"
        )
        expect(
            AppWritingContext.classify(appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", windowTitle: nil) == .workChat,
            "Slack should use work-chat writing context"
        )
        expect(
            AppWritingContext.classify(appName: "Discord", bundleIdentifier: "com.hnc.Discord", windowTitle: nil) == .casualChat,
            "Discord should use casual-chat writing context"
        )
        expect(
            AppWritingContext.classify(appName: "Terminal", bundleIdentifier: "com.apple.Terminal", windowTitle: nil) == .codeOrTerminal,
            "Terminal should preserve technical writing"
        )
        expect(
            AppWritingContext.classify(appName: "Safari", bundleIdentifier: "com.apple.Safari", windowTitle: "Roadmap - Google Docs") == .document,
            "Google Docs should use document writing context"
        )
    }

    private static func testCleanupPromptUsesLocalAppStyle() {
        let request = SmartCleanupRequest(
            transcript: "uh hey can you send that by friday",
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            windowTitle: "Megaphone | project",
            selectedText: nil,
            contextSummary: "",
            vocabulary: [],
            corrections: [],
            outputLanguage: "English",
            customInstructions: ""
        )
        let prompt = AppleFoundationModelsPostProcessor.cleanupPrompt(for: request)

        expect(prompt.contains("Writing context: work chat"), "Cleanup prompt lost Slack context")
        expect(prompt.contains("concise, professional chat formatting"), "Slack cleanup guidance missing")
        expect(prompt.contains("do not make the message more formal unless asked"), "Cleanup should preserve tone")
    }

    private static func testWakeCommandResponseWrappersAreRemoved() {
        let cases = [
            ("<response>Hello</response>", "Hello"),
            ("  <RESPONSE >\nHello\n</Response >  ", "Hello"),
            ("<response><response>Hello</response></response>", "Hello"),
            ("<response>Hello", "Hello"),
            ("Hello</response>", "Hello"),
            ("Use <response> as the element name.", "Use <response> as the element name."),
            ("ordinary text", "ordinary text"),
            ("<response></response>", "")
        ]

        for (raw, expected) in cases {
            expectEqual(
                AppleFoundationModelsPostProcessor.normalizeCommandOutput(raw),
                expected
            )
        }
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
