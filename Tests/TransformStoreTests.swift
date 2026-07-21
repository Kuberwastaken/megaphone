import Foundation

enum TransformStoreTests {
    static func run() {
        testBuiltInsAreAvailableByDefault()
        testInvocationMatchingPositives()
        testInvocationMatchingNegatives()
        testMultiWordUserTransformMatching()
        testStoreRoundTripMergesBuiltIns()
        testDecodedTransformsNeverClaimBuiltInStatus()
        testUserTransformShadowsBuiltInName()
    }

    private static func testBuiltInsAreAvailableByDefault() {
        let resolved = TransformStore.resolved(userTransforms: [])
        expect(resolved.count == 2, "Expected exactly the two built-ins, got \(resolved.count)")
        expect(resolved.contains { $0.name == "Polish" && $0.isBuiltIn }, "Polish built-in missing")
        expect(resolved.contains { $0.name == "Prompt" && $0.isBuiltIn }, "Prompt built-in missing")
        expect(
            resolved.allSatisfy { !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            "Built-in transforms must carry a visible instruction"
        )
    }

    private static func testInvocationMatchingPositives() {
        let transforms = TransformStore.resolved(userTransforms: [])
        let polishInvocations = [
            "polish",
            "Polish",
            "POLISH THAT",
            "polish this",
            "polish that.",
            "Polish that!",
            "apply polish",
            "Apply Polish."
        ]
        for command in polishInvocations {
            expect(
                TransformStore.match(command: command, in: transforms)?.name == "Polish",
                "Expected \(command.debugDescription) to invoke Polish"
            )
        }
        expect(
            TransformStore.match(command: "prompt that.", in: transforms)?.name == "Prompt",
            "Expected \"prompt that.\" to invoke Prompt"
        )
        expect(
            TransformStore.match(command: "apply prompt", in: transforms)?.name == "Prompt",
            "Expected \"apply prompt\" to invoke Prompt"
        )
    }

    private static func testInvocationMatchingNegatives() {
        let transforms = TransformStore.resolved(userTransforms: [])
        let rejected = [
            "",
            "   ",
            "polish that thing up",
            "please polish that",
            "can you polish that",
            "polish that now",
            "polish it",
            "apply",
            "that",
            "this",
            "apply that",
            "shine that",
            "prompt engineering that",
            "make that a bulleted list"
        ]
        for command in rejected {
            expect(
                TransformStore.match(command: command, in: transforms) == nil,
                "\(command.debugDescription) must not invoke a transform"
            )
        }
    }

    private static func testMultiWordUserTransformMatching() {
        let meetingNotes = Transform(name: "Meeting Notes", instruction: "Turn the text into meeting notes.")
        let transforms = TransformStore.resolved(userTransforms: [meetingNotes])
        for command in ["meeting notes", "Meeting Notes that.", "apply meeting notes", "meeting-notes this"] {
            expect(
                TransformStore.match(command: command, in: transforms)?.id == meetingNotes.id,
                "Expected \(command.debugDescription) to invoke Meeting Notes"
            )
        }
        expect(
            TransformStore.match(command: "meeting", in: transforms) == nil,
            "A name prefix must not invoke a multi-word transform"
        )
        expect(
            TransformStore.match(command: "meeting notes for today that", in: transforms) == nil,
            "Extra words inside the invocation must fall through"
        )
    }

    private static func testStoreRoundTripMergesBuiltIns() {
        let custom = Transform(name: "Formalize", instruction: "Make the text formal.")
        let data = try! JSONEncoder().encode([custom])
        let decoded = try! JSONDecoder().decode([Transform].self, from: data)
        expect(decoded == [custom], "User transform did not survive an encode/decode round trip")

        let resolved = TransformStore.resolved(userTransforms: decoded)
        expect(resolved.count == 3, "Expected built-ins plus the decoded transform, got \(resolved.count)")
        expect(resolved.prefix(2).allSatisfy(\.isBuiltIn), "Built-ins should stay listed first")
        expect(resolved.last == custom, "Decoded user transform missing from the resolved list")
    }

    private static func testDecodedTransformsNeverClaimBuiltInStatus() {
        let data = try! JSONEncoder().encode(TransformStore.builtIns)
        let decoded = try! JSONDecoder().decode([Transform].self, from: data)
        expect(
            decoded.allSatisfy { !$0.isBuiltIn },
            "isBuiltIn must not be persisted; storage only ever holds user transforms"
        )
    }

    private static func testUserTransformShadowsBuiltInName() {
        let customPolish = Transform(name: "polish", instruction: "Polish, but in pirate speak.")
        let resolved = TransformStore.resolved(userTransforms: [customPolish])

        expect(resolved.count == 2, "Shadowed built-in must not be listed twice")
        expect(
            resolved.filter { TransformStore.normalize($0.name) == "polish" } == [customPolish],
            "User transform must replace the built-in with the same name"
        )
        let matched = TransformStore.match(command: "polish that", in: resolved)
        expect(matched?.id == customPolish.id, "Invocation must resolve to the user's shadowing transform")
        expect(
            matched?.instruction == "Polish, but in pirate speak.",
            "Shadowing transform must carry the user's instruction"
        )
        expect(
            TransformStore.match(command: "prompt that", in: resolved)?.isBuiltIn == true,
            "Unshadowed built-in must keep working"
        )
    }

    private static func expect(
        _ condition: Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
