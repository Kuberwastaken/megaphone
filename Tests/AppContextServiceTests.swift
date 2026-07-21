import Foundation

@main
struct AppContextServiceTests {
    static func main() {
        testWakeCommandIncludesPreviousTextAndScreenContext()
        testWakeCommandIncludesVisibleWindowText()
        testWakeCommandResponseWrappersAreRemoved()
        testWakeCommandOutputTagRepair()
        testWakeCommandRoutingIsParsed()
        testAppWritingContextClassification()
        testMarkdownSurfaceDetection()
        testCleanupPromptUsesLocalAppStyle()
        testCleanupPromptIncludesTextBeforeCaret()
        testCaretContextCaseHarmonization()
        testCaretContextRepetitionStripping()
        testSelectionPromptUsesDestinationContext()
        testTransformInstructionsAndPrompt()
        testTransformSourceTextEchoIsRemoved()
        testWritingFormalityGuidance()
        testWritingFormalityPromptPlumbing()
        testWritingFormalityStorageRoundTrip()
        TranscriptTidierTests.run()
        DictionaryStoreTests.run()
        WakePhraseMatcherTests.run()
        TransformStoreTests.run()
        ScratchCommandMatcherTests.run()
        print("MegaphoneTests passed")
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
        expect(!prompt.contains("com.apple.mail"), "Raw bundle identifier should not enter the model prompt")
        expect(prompt.contains("Writing context: email"), "Email writing context missing")
        expect(prompt.contains("Do not invent a greeting, sign-off, subject, or details."), "Safe email guidance missing")
        expect(prompt.contains("Window: Draft — Project update"), "Window context missing")
        expect(prompt.contains("Context: The user is composing an email reply."), "Screen context missing")
        expect(prompt.contains("Current selected text: Earlier text selected in the draft."), "Selected screen text missing")
        expect(prompt.contains("make that formal"), "Spoken follow-up missing")
    }

    private static func testWakeCommandIncludesVisibleWindowText() {
        let withScreen = AppleFoundationModelsPostProcessor.commandPrompt(
            command: "reply to this email saying thanks",
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "Inbox - Gmail",
            contextSummary: "",
            selectedText: nil,
            previousText: nil,
            screenText: "From: Sam\nSubject: Trying Megaphone\nLoving the app so far!",
            vocabulary: []
        )
        expect(withScreen.contains("VISIBLE WINDOW TEXT"), "Screen text section missing")
        expect(withScreen.contains("Loving the app so far!"), "Screen text content missing")

        let withoutScreen = AppleFoundationModelsPostProcessor.commandPrompt(
            command: "reply to this email saying thanks",
            appName: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "Inbox - Gmail",
            contextSummary: "",
            selectedText: nil,
            previousText: nil,
            screenText: nil,
            vocabulary: []
        )
        expect(!withoutScreen.contains("VISIBLE WINDOW TEXT"), "Screen text section should be omitted when empty")
    }

    private static func testWakeCommandOutputTagRepair() {
        let echoed = """
        <previous_text>
        I want to do three things: wash the dishes, get the Coke, buy coffee.
        </previous_text>
        <bulleted_list>
        <item>Wash the dishes</item>
        <item>Get the Coke</item>
        <item>Buy coffee</item>
        </bulleted_list>
        """
        expectEqual(
            AppleFoundationModelsPostProcessor.normalizeCommandOutput(echoed),
            "- Wash the dishes\n- Get the Coke\n- Buy coffee"
        )
        expectEqual(
            AppleFoundationModelsPostProcessor.normalizeCommandOutput("<answer>Sounds good, see you at 5.</answer>"),
            "Sounds good, see you at 5."
        )
        expectEqual(
            AppleFoundationModelsPostProcessor.normalizeCommandOutput("Use a <strong>bold</strong> tag here."),
            "Use a <strong>bold</strong> tag here."
        )
    }

    private static func testMarkdownSurfaceDetection() {
        expect(
            AppWritingContext.supportsMarkdown(appName: "Obsidian", bundleIdentifier: "md.obsidian", windowTitle: "Daily note"),
            "Obsidian should be a markdown surface"
        )
        expect(
            AppWritingContext.supportsMarkdown(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", windowTitle: "Editing megaphone/README.md at main · Kuberwastaken/megaphone · GitHub"),
            "GitHub in a browser should be a markdown surface"
        )
        expect(
            !AppWritingContext.supportsMarkdown(appName: "WhatsApp", bundleIdentifier: "net.whatsapp.WhatsApp", windowTitle: nil),
            "WhatsApp must not be a markdown surface"
        )
        expect(
            !AppWritingContext.supportsMarkdown(appName: "Notes", bundleIdentifier: "com.apple.Notes", windowTitle: "Notes – 7 notes"),
            "Apple Notes must not be a markdown surface"
        )

        let obsidianPrompt = AppleFoundationModelsPostProcessor.cleanupPrompt(for: SmartCleanupRequest(
            transcript: "first wash the dishes second buy coffee",
            appName: "Obsidian",
            bundleIdentifier: "md.obsidian",
            windowTitle: "Daily note",
            selectedText: nil,
            contextSummary: "",
            vocabulary: [],
            corrections: [],
            outputLanguage: "",
            customInstructions: ""
        ))
        expect(obsidianPrompt.contains("Markdown renders here"), "Obsidian cleanup prompt lost markdown guidance")

        let whatsappPrompt = AppleFoundationModelsPostProcessor.cleanupPrompt(for: SmartCleanupRequest(
            transcript: "first wash the dishes second buy coffee",
            appName: "WhatsApp",
            bundleIdentifier: "net.whatsapp.WhatsApp",
            windowTitle: "Mom",
            selectedText: nil,
            contextSummary: "",
            vocabulary: [],
            corrections: [],
            outputLanguage: "",
            customInstructions: ""
        ))
        expect(whatsappPrompt.contains("never markdown syntax"), "WhatsApp cleanup prompt should forbid markdown")
        expect(!whatsappPrompt.contains("Markdown renders here"), "WhatsApp must not advertise markdown")
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
        expect(
            AppWritingContext.classify(appName: "Safari", bundleIdentifier: "com.apple.Safari", windowTitle: "Megaphone | Slack") == .workChat,
            "Slack in a browser should use work-chat writing context"
        )
        expect(
            AppWritingContext.classify(appName: "Safari", bundleIdentifier: "com.apple.Safari", windowTitle: "Discord | #general") == .casualChat,
            "Discord in a browser should use casual-chat writing context"
        )
        expect(
            AppWritingContext.classify(appName: "WhatsApp", bundleIdentifier: "net.whatsapp.WhatsApp", windowTitle: nil) == .casualChat,
            "WhatsApp should use casual-chat writing context"
        )
        expect(
            AppWritingContext.classify(appName: "Telegram", bundleIdentifier: "ru.keepcoder.Telegram", windowTitle: nil) == .casualChat,
            "Telegram should use casual-chat writing context"
        )
        expect(
            AppWritingContext.classify(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", windowTitle: "Inbox (42) - kuber@gmail.com - Gmail") == .email,
            "Gmail in a browser should use email writing context"
        )
        expect(
            AppWritingContext.classify(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", windowTitle: "kuber@gmail.com - Google Account") == .neutral,
            "A Gmail address alone should not read as email writing context"
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

    private static func testCleanupPromptIncludesTextBeforeCaret() {
        func request(textBeforeCaret: String?) -> SmartCleanupRequest {
            SmartCleanupRequest(
                transcript: "definitely ship it tomorrow",
                appName: "Notes",
                bundleIdentifier: "com.apple.Notes",
                windowTitle: "Ideas",
                selectedText: nil,
                textBeforeCaret: textBeforeCaret,
                contextSummary: "",
                vocabulary: [],
                corrections: [],
                outputLanguage: "",
                customInstructions: ""
            )
        }
        let hintMarker = "Text immediately before the cursor"

        let withCaretContext = AppleFoundationModelsPostProcessor.cleanupPrompt(
            for: request(textBeforeCaret: "I think we should")
        )
        expect(withCaretContext.contains(hintMarker), "Caret context hint missing")
        expect(withCaretContext.contains("\"I think we should\""), "Caret context text missing from hint")
        expect(withCaretContext.contains("start lowercase"), "Mid-sentence caret context must direct a lowercase continuation")

        let afterSentence = AppleFoundationModelsPostProcessor.cleanupPrompt(
            for: request(textBeforeCaret: "Let me check the logs.")
        )
        expect(afterSentence.contains("capitalize its first word"), "Sentence-ending caret context must direct a fresh sentence")

        let multiline = AppleFoundationModelsPostProcessor.cleanupPrompt(
            for: request(textBeforeCaret: "Meeting notes:\nI think we should")
        )
        expect(multiline.contains("\"Meeting notes: I think we should\""), "Caret context must be flattened to one line")

        expect(
            AppleFoundationModelsPostProcessor.caretContinuesSentence("I think we should"),
            "Mid-sentence text must continue the sentence"
        )
        expect(
            AppleFoundationModelsPostProcessor.caretContinuesSentence("We talked it over and,"),
            "A trailing comma must continue the sentence"
        )
        expect(
            !AppleFoundationModelsPostProcessor.caretContinuesSentence("Let me check the logs."),
            "A trailing period must start a fresh sentence"
        )
        expect(
            !AppleFoundationModelsPostProcessor.caretContinuesSentence("Really?!"),
            "Trailing sentence punctuation must start a fresh sentence"
        )
        expect(
            !AppleFoundationModelsPostProcessor.caretContinuesSentence("He said \u{201C}done.\u{201D}"),
            "A period inside closing quotes must start a fresh sentence"
        )
        expect(
            !AppleFoundationModelsPostProcessor.caretContinuesSentence("Shopping list\n"),
            "A trailing newline must start a fresh sentence"
        )

        let withoutCaretContext = AppleFoundationModelsPostProcessor.cleanupPrompt(
            for: request(textBeforeCaret: nil)
        )
        expect(!withoutCaretContext.contains(hintMarker), "Caret context hint must be omitted when nil")

        let withBlankCaretContext = AppleFoundationModelsPostProcessor.cleanupPrompt(
            for: request(textBeforeCaret: "  \n ")
        )
        expect(!withBlankCaretContext.contains(hintMarker), "Caret context hint must be omitted when blank")

        // Existing call sites that never pass textBeforeCaret keep compiling
        // and produce no caret hint.
        let defaulted = AppleFoundationModelsPostProcessor.cleanupPrompt(for: SmartCleanupRequest(
            transcript: "definitely ship it tomorrow",
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "Ideas",
            selectedText: nil,
            contextSummary: "",
            vocabulary: [],
            corrections: [],
            outputLanguage: "",
            customInstructions: ""
        ))
        expect(!defaulted.contains(hintMarker), "Defaulted textBeforeCaret must omit the caret hint")
    }

    private static func testCaretContextCaseHarmonization() {
        func harmonized(_ text: String, transcript: String, before: String?) -> String {
            AppleFoundationModelsPostProcessor.harmonizeCaseWithCaretContext(text, request: SmartCleanupRequest(
                transcript: transcript,
                appName: nil,
                bundleIdentifier: nil,
                windowTitle: nil,
                selectedText: nil,
                textBeforeCaret: before,
                contextSummary: "",
                vocabulary: [],
                corrections: [],
                outputLanguage: "",
                customInstructions: ""
            ))
        }

        expectEqual(
            harmonized("Definitely ship it", transcript: "um definitely ship it", before: "I think we should"),
            "definitely ship it"
        )
        expectEqual(
            harmonized("Ian should go", transcript: "Ian should go", before: "I think"),
            "Ian should go"
        )
        expectEqual(
            harmonized("I should go", transcript: "I should go", before: "maybe"),
            "I should go"
        )
        expectEqual(
            harmonized("we might need to roll back", transcript: "we might need to roll back", before: "Let me check the logs."),
            "We might need to roll back"
        )
        expectEqual(
            harmonized("iPhone sales dropped", transcript: "iPhone sales dropped", before: "Let me check the logs."),
            "iPhone sales dropped"
        )
        expectEqual(
            harmonized("Definitely ship it", transcript: "definitely ship it", before: nil),
            "Definitely ship it"
        )
    }

    private static func testCaretContextRepetitionStripping() {
        expectEqual(
            AppleFoundationModelsPostProcessor.stripRepeatedCaretPrefix(
                "I guess the team could probably try the beta first thing.",
                before: "I guess the team could"
            ),
            "probably try the beta first thing."
        )
        expectEqual(
            AppleFoundationModelsPostProcessor.stripRepeatedCaretPrefix(
                "I think we should ship",
                before: "Yesterday we agreed that I think we should"
            ),
            "ship"
        )
        expectEqual(
            AppleFoundationModelsPostProcessor.stripRepeatedCaretPrefix(
                "I guess the team could, probably try the beta",
                before: "I guess the team could"
            ),
            "probably try the beta"
        )
        expectEqual(
            AppleFoundationModelsPostProcessor.stripRepeatedCaretPrefix(
                "should we reconsider",
                before: "I think we should"
            ),
            "should we reconsider"
        )
        expectEqual(
            AppleFoundationModelsPostProcessor.stripRepeatedCaretPrefix(
                "hi everyone",
                before: "Hi"
            ),
            "hi everyone"
        )
        expectEqual(
            AppleFoundationModelsPostProcessor.stripRepeatedCaretPrefix(
                "I guess the team could",
                before: "I guess the team could"
            ),
            "I guess the team could"
        )
    }

    private static func testSelectionPromptUsesDestinationContext() {
        let prompt = AppleFoundationModelsPostProcessor.selectionPrompt(
            selectedText: "can we ship this tomorrow",
            command: "make this clearer",
            appName: "Mail",
            bundleIdentifier: "com.apple.mail",
            windowTitle: "Draft — Launch",
            vocabulary: ["Megaphone"]
        )

        expect(!prompt.contains("com.apple.mail"), "Raw bundle identifier should not enter the edit prompt")
        expect(prompt.contains("Window: Draft — Launch"), "Edit prompt lost window context")
        expect(prompt.contains("Writing context: email"), "Edit prompt lost email style")
        expect(prompt.contains("Do not invent a greeting, sign-off, subject, or details."), "Edit prompt lost email safety")
    }

    private static let casualSentence = "The speaker prefers a relaxed register: contractions are welcome and punctuation stays light."
    private static let formalSentence = "The speaker prefers a polished register: full sentences, professional punctuation, and spoken shorthand written out — “gonna” becomes “going to”, “wanna” becomes “want to”."

    private static func testWritingFormalityGuidance() {
        let dialContexts: [AppWritingContext] = [.email, .workChat, .casualChat, .document, .neutral]
        for context in dialContexts {
            expectEqual(
                context.cleanupGuidance(markdown: false, formality: .balanced),
                context.cleanupGuidance(markdown: false)
            )
            expect(
                !context.cleanupGuidance(markdown: false).contains("register"),
                "Balanced must add nothing for \(context)"
            )
            expect(
                context.cleanupGuidance(markdown: false, formality: .casual).hasSuffix(casualSentence),
                "Casual preference missing for \(context)"
            )
            expect(
                context.cleanupGuidance(markdown: false, formality: .formal).hasSuffix(formalSentence),
                "Formal preference missing for \(context)"
            )
            expect(
                context.commandGuidance(markdown: false, formality: .formal).contains(formalSentence),
                "Command guidance lost formal preference for \(context)"
            )
        }

        // Markdown guidance and the formality preference must coexist.
        let markdownFormal = AppWritingContext.document.cleanupGuidance(markdown: true, formality: .formal)
        expect(markdownFormal.contains("Markdown renders here"), "Markdown guidance lost with formality set")
        expect(markdownFormal.hasSuffix(formalSentence), "Formal preference lost on markdown surface")

        // Code and terminal are always technical, whatever the dial says.
        for formality in WritingFormality.allCases {
            expectEqual(
                AppWritingContext.codeOrTerminal.cleanupGuidance(markdown: false, formality: formality),
                AppWritingContext.codeOrTerminal.cleanupGuidance(markdown: false)
            )
        }
    }

    private static func testWritingFormalityPromptPlumbing() {
        func request(_ formality: WritingFormality) -> SmartCleanupRequest {
            SmartCleanupRequest(
                transcript: "hey uh can you send me the report by friday thanks",
                appName: "Mail",
                bundleIdentifier: "com.apple.mail",
                windowTitle: "Draft",
                selectedText: nil,
                contextSummary: "",
                vocabulary: [],
                corrections: [],
                outputLanguage: "",
                customInstructions: "",
                formality: formality
            )
        }
        expect(
            AppleFoundationModelsPostProcessor.cleanupPrompt(for: request(.formal)).contains(formalSentence),
            "Cleanup prompt lost the formal dial"
        )
        expect(
            AppleFoundationModelsPostProcessor.cleanupPrompt(for: request(.casual)).contains(casualSentence),
            "Cleanup prompt lost the casual dial"
        )
        let balancedPrompt = AppleFoundationModelsPostProcessor.cleanupPrompt(for: request(.balanced))
        expect(
            !balancedPrompt.contains(formalSentence) && !balancedPrompt.contains(casualSentence),
            "Balanced cleanup prompt must match current behavior"
        )

        let commandPrompt = AppleFoundationModelsPostProcessor.commandPrompt(
            command: "reply saying thanks",
            appName: "Slack",
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            windowTitle: "Megaphone | project",
            contextSummary: "",
            selectedText: nil,
            previousText: nil,
            vocabulary: [],
            formality: .formal
        )
        expect(commandPrompt.contains(formalSentence), "Command prompt lost the formal dial")

        let selectionPrompt = AppleFoundationModelsPostProcessor.selectionPrompt(
            selectedText: "can we ship this tomorrow",
            command: "fix the punctuation",
            appName: "Discord",
            bundleIdentifier: "com.hnc.Discord",
            windowTitle: nil,
            vocabulary: [],
            formality: .casual
        )
        expect(selectionPrompt.contains(casualSentence), "Selection prompt lost the casual dial")
    }

    private static func testWritingFormalityStorageRoundTrip() {
        for formality in WritingFormality.allCases {
            expect(
                WritingFormality(rawValue: formality.rawValue) == formality,
                "Raw-value round trip failed for \(formality)"
            )
        }
        // Unknown or missing stored values fall back to balanced, the way
        // AppState resolves the per-context dictionary.
        expect(
            WritingFormality(rawValue: "loud") == nil,
            "Unknown stored value must be rejected so the caller defaults to balanced"
        )
        let stored = ["email": "formal", "casualChat": "casual"]
        let decoded = AppWritingContext.email.rawValue
        expect(
            WritingFormality(rawValue: stored[decoded] ?? "") == .formal,
            "Stored dictionary lookup by context raw value failed"
        )
        expect(
            WritingFormality(rawValue: stored[AppWritingContext.neutral.rawValue] ?? "") == nil,
            "Missing context entry must resolve to no explicit formality"
        )
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

    private static func testWakeCommandRoutingIsParsed() {
        let replacement = AppleFoundationModelsPostProcessor.parseWakeCommandOutput(
            "REPLACE_PREVIOUS\nHello,\n\nCould you send this by Friday?"
        )
        expect(replacement.replacesPreviousText, "Previous-text edit route was not preserved")
        expectEqual(replacement.text, "Hello,\n\nCould you send this by Friday?")

        let insertion = AppleFoundationModelsPostProcessor.parseWakeCommandOutput("INSERT\n8")
        expect(!insertion.replacesPreviousText, "Standalone answer was treated as an edit")
        expectEqual(insertion.text, "8")

        let legacy = AppleFoundationModelsPostProcessor.parseWakeCommandOutput("ordinary output")
        expect(!legacy.replacesPreviousText, "Unrouted output must fail safe as an insertion")
        expectEqual(legacy.text, "ordinary output")
    }

    private static func testTransformInstructionsAndPrompt() {
        let instructions = AppleFoundationModelsPostProcessor.transformInstructions(
            directive: TransformStore.polishInstruction
        )
        expect(instructions.contains("Rewrite the user's text according to the directive."), "Transform frame missing")
        expect(instructions.contains("Return only the rewritten text"), "Output-only constraint missing")
        expect(instructions.contains("Directive: Tighten the grammar"), "Directive was not embedded in the instructions")

        let prompt = AppleFoundationModelsPostProcessor.transformPrompt(
            text: "so basically we should ship on friday",
            vocabulary: ["Megaphone"]
        )
        expect(prompt.contains("<source_text>"), "Tagged source block missing")
        expect(prompt.contains("so basically we should ship on friday"), "Source text missing from prompt")
        expect(prompt.contains("Preferred spellings: Megaphone"), "Vocabulary hint missing")

        let bare = AppleFoundationModelsPostProcessor.transformPrompt(text: "hello", vocabulary: [])
        expect(!bare.contains("Preferred spellings"), "Empty vocabulary must not add a hint")
    }

    private static func testTransformSourceTextEchoIsRemoved() {
        let echoed = """
        <source_text>
        so basically we should ship on friday
        </source_text>
        We should ship on Friday.
        """
        expectEqual(
            AppleFoundationModelsPostProcessor.normalizeCommandOutput(echoed),
            "We should ship on Friday."
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
