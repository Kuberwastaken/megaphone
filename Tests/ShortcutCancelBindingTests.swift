import Foundation

struct ShortcutCancelBindingTests {
    static func run() {
        testDefaultCancelIsBareEscapeKey()
        testDefaultCancelEncodeDecodeRoundTrip()
        testCustomCancelEncodeDecodeRoundTrip()
        testCorruptStoredDataFailsDecodingGracefully()
        testSanitizedCancelBindingFallsBackToDefault()
        testSanitizedCancelBindingKeepsValidKeyBindings()
        testCancelKeyDownMatching()
        testConfigurationDefaultsCancelToEscape()
    }

    private static let customCancel = ShortcutBinding(
        keyCode: 47,
        keyDisplay: ".",
        modifiers: [.command],
        kind: .key,
        preset: nil
    )

    private static func testDefaultCancelIsBareEscapeKey() {
        let binding = ShortcutBinding.defaultCancel
        expect(binding.keyCode == 53, "Default cancel key must be Escape (keyCode 53)")
        expect(binding.modifiers == [], "Default cancel key must have no modifiers")
        expect(binding.kind == .key, "Default cancel key must be a regular key binding")
        expect(!binding.isDisabled, "Default cancel key must not be disabled")
    }

    private static func testDefaultCancelEncodeDecodeRoundTrip() {
        expectRoundTrips(.defaultCancel)
    }

    private static func testCustomCancelEncodeDecodeRoundTrip() {
        expectRoundTrips(customCancel)

        let withExactModifiers = ShortcutBinding(
            keyCode: 96,
            keyDisplay: "F5",
            modifiers: [.control, .shift],
            kind: .key,
            preset: nil,
            exactModifierKeyCodes: [59, 56]
        )
        expectRoundTrips(withExactModifiers)
    }

    private static func testCorruptStoredDataFailsDecodingGracefully() {
        let corrupt = Data("not a shortcut binding".utf8)
        let decoded = try? JSONDecoder().decode(ShortcutBinding.self, from: corrupt)
        expect(decoded == nil, "Corrupt stored data must decode to nil, not crash")
        expect(
            ShortcutBinding.sanitizedCancelBinding(decoded) == .defaultCancel,
            "Corrupt stored data must fall back to the default cancel binding"
        )
    }

    private static func testSanitizedCancelBindingFallsBackToDefault() {
        expect(
            ShortcutBinding.sanitizedCancelBinding(nil) == .defaultCancel,
            "Missing binding must fall back to default"
        )
        expect(
            ShortcutBinding.sanitizedCancelBinding(.disabled) == .defaultCancel,
            "Disabled binding must fall back to default"
        )

        let modifierOnly = ShortcutBinding(
            keyCode: 63,
            keyDisplay: "Fn",
            modifiers: [],
            kind: .modifierKey,
            preset: .fnKey
        )
        expect(
            ShortcutBinding.sanitizedCancelBinding(modifierOnly) == .defaultCancel,
            "Modifier-only binding must fall back to default"
        )
    }

    private static func testSanitizedCancelBindingKeepsValidKeyBindings() {
        expect(
            ShortcutBinding.sanitizedCancelBinding(customCancel) == customCancel,
            "Valid key binding must be kept as-is"
        )
        expect(
            ShortcutBinding.sanitizedCancelBinding(.defaultCancel) == .defaultCancel,
            "Default binding must be kept as-is"
        )
    }

    private static func testCancelKeyDownMatching() {
        let defaultCancel = ShortcutBinding.defaultCancel
        expect(
            defaultCancel.matchesCancelKeyDown(keyCode: 53, activeModifiers: []),
            "Default cancel must match a bare Escape key-down"
        )
        // Historical behavior: the hardcoded check consumed Escape regardless
        // of held modifiers, so a no-modifier binding matches supersets.
        expect(
            defaultCancel.matchesCancelKeyDown(keyCode: 53, activeModifiers: [.command, .shift]),
            "Default cancel must still match Escape with extra modifiers held"
        )
        expect(
            !defaultCancel.matchesCancelKeyDown(keyCode: 49, activeModifiers: []),
            "Default cancel must not match other keys"
        )

        expect(
            customCancel.matchesCancelKeyDown(keyCode: 47, activeModifiers: [.command]),
            "Custom cancel must match its key with its modifiers held"
        )
        expect(
            customCancel.matchesCancelKeyDown(keyCode: 47, activeModifiers: [.command, .option]),
            "Custom cancel must match when extra modifiers are held"
        )
        expect(
            !customCancel.matchesCancelKeyDown(keyCode: 47, activeModifiers: []),
            "Custom cancel must not match without its required modifiers"
        )
        expect(
            !customCancel.matchesCancelKeyDown(keyCode: 53, activeModifiers: [.command]),
            "Custom cancel must not match a different keyCode"
        )

        let modifierOnly = ShortcutPreset.fnKey.binding
        expect(
            !modifierOnly.matchesCancelKeyDown(keyCode: 63, activeModifiers: [.function]),
            "Modifier-only bindings must never match as cancel keys"
        )
        expect(
            !ShortcutBinding.disabled.matchesCancelKeyDown(keyCode: 0, activeModifiers: []),
            "Disabled bindings must never match as cancel keys"
        )
    }

    private static func testConfigurationDefaultsCancelToEscape() {
        let configuration = ShortcutConfiguration(hold: .defaultHold, toggle: .defaultToggle)
        expect(
            configuration.cancel == .defaultCancel,
            "Configurations without an explicit cancel binding must default to Escape"
        )
    }

    private static func expectRoundTrips(_ binding: ShortcutBinding, file: StaticString = #file, line: UInt = #line) {
        guard let data = try? JSONEncoder().encode(binding) else {
            fatalError("\(file):\(line): Failed to encode \(binding.displayName)")
        }
        guard let decoded = try? JSONDecoder().decode(ShortcutBinding.self, from: data) else {
            fatalError("\(file):\(line): Failed to decode \(binding.displayName)")
        }
        expect(decoded == binding, "Round trip changed binding: \(binding.displayName) -> \(decoded.displayName)", file: file, line: line)
    }

    private static func expect(_ condition: Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
        if !condition {
            fatalError("\(file):\(line): \(message)")
        }
    }
}
