import Foundation

/// Rules and labels for binding a mouse button as a hold-to-talk dictation
/// trigger. Button numbers use NSEvent/CGEvent numbering: 0 = left,
/// 1 = right, 2 = middle, 3+ = extra buttons (side/thumb buttons on
/// MMO mice and trackballs).
enum MouseDictationButton {
    /// NSEvent button number for the middle button — the lowest bindable one.
    static let middleButtonNumber = 2

    /// Default binding: the 4th button (first thumb/side button on most mice).
    static let defaultButtonNumber = 3

    /// Left (0) and right (1) clicks must never trigger dictation; the
    /// middle button (2) and anything above it is fair game.
    static func isBindable(_ buttonNumber: Int) -> Bool {
        buttonNumber >= middleButtonNumber
    }

    /// Human-readable label using 1-based mouse-button naming
    /// (NSEvent button 3 is "Button 4").
    static func displayName(for buttonNumber: Int) -> String {
        guard isBindable(buttonNumber) else { return "Unsupported button" }
        if buttonNumber == middleButtonNumber { return "Middle Button" }
        return "Button \(buttonNumber + 1)"
    }

    /// Clamps stored/legacy values to a bindable button so a corrupted or
    /// hand-edited preference can never bind the left or right button.
    static func normalized(_ buttonNumber: Int) -> Int {
        isBindable(buttonNumber) ? buttonNumber : defaultButtonNumber
    }
}
