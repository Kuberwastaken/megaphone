import Foundation

enum MouseDictationButtonTests {
    static func run() {
        testPrimaryButtonsAreNeverBindable()
        testMiddleAndSideButtonsAreBindable()
        testDisplayNamesUseOneBasedNumbering()
        testNormalizationRepairsInvalidStoredValues()
        testDefaultIsTheFourthButton()
    }

    private static func testPrimaryButtonsAreNeverBindable() {
        expect(!MouseDictationButton.isBindable(0), "Left click must never be bindable")
        expect(!MouseDictationButton.isBindable(1), "Right click must never be bindable")
        expect(!MouseDictationButton.isBindable(-1), "Negative button numbers must be rejected")
    }

    private static func testMiddleAndSideButtonsAreBindable() {
        for buttonNumber in [2, 3, 4, 5, 15] {
            expect(
                MouseDictationButton.isBindable(buttonNumber),
                "Button number \(buttonNumber) should be bindable"
            )
        }
    }

    private static func testDisplayNamesUseOneBasedNumbering() {
        expectEqual(MouseDictationButton.displayName(for: 2), "Middle Button")
        expectEqual(MouseDictationButton.displayName(for: 3), "Button 4")
        expectEqual(MouseDictationButton.displayName(for: 4), "Button 5")
        expectEqual(MouseDictationButton.displayName(for: 9), "Button 10")
        expectEqual(MouseDictationButton.displayName(for: 0), "Unsupported button")
        expectEqual(MouseDictationButton.displayName(for: 1), "Unsupported button")
    }

    private static func testNormalizationRepairsInvalidStoredValues() {
        expectEqual(MouseDictationButton.normalized(0), MouseDictationButton.defaultButtonNumber)
        expectEqual(MouseDictationButton.normalized(1), MouseDictationButton.defaultButtonNumber)
        expectEqual(MouseDictationButton.normalized(-7), MouseDictationButton.defaultButtonNumber)
        expectEqual(MouseDictationButton.normalized(2), 2)
        expectEqual(MouseDictationButton.normalized(6), 6)
    }

    private static func testDefaultIsTheFourthButton() {
        expectEqual(MouseDictationButton.defaultButtonNumber, 3)
        expect(
            MouseDictationButton.isBindable(MouseDictationButton.defaultButtonNumber),
            "The default button must itself be bindable"
        )
    }

    private static func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        expect(actual == expected, "Expected \(expected), got \(actual)", file: file, line: line)
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
