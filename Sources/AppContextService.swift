import Foundation
import ApplicationServices
import AppKit

struct AppSelectionSnapshot {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
}

struct AppContext {
    let appName: String?
    let bundleIdentifier: String?
    let windowTitle: String?
    let selectedText: String?
    let textBeforeCaret: String?
    let currentActivity: String

    var contextSummary: String {
        currentActivity
    }
}

/// Reads lightweight, on-device context about the app the user is dictating
/// into: frontmost app identity, focused window title, and selected text via
/// the accessibility APIs. Megaphone is local-only; nothing here talks to a
/// network.
final class AppContextService {
    /// How much text before the caret is captured as continuation context.
    /// Enough to see the current sentence and the previous one; small enough
    /// to stay cheap in the on-device model's prompt.
    static let textBeforeCaretLimit = 240

    func collectSelectionSnapshot() -> AppSelectionSnapshot {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return AppSelectionSnapshot(
                appName: nil,
                bundleIdentifier: nil,
                windowTitle: nil,
                selectedText: nil
            )
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        return AppSelectionSnapshot(
            appName: frontmostApp.localizedName,
            bundleIdentifier: frontmostApp.bundleIdentifier,
            windowTitle: focusedWindowTitle(from: appElement) ?? frontmostApp.localizedName,
            selectedText: rawSelectedText(from: appElement)
        )
    }

    /// Selects `text` only when it is still immediately before the caret in
    /// the focused editable element. This makes follow-up edits safe: if the
    /// user moved the caret or changed the content, Megaphone leaves it alone.
    func selectTextImmediatelyBeforeCaret(matching text: String) -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        guard let focusedElement = accessibilityElement(
            from: appElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ), let value = accessibilityRawString(
            from: focusedElement,
            attribute: kAXValueAttribute as CFString
        ), var selectedRange = accessibilityRange(
            from: focusedElement,
            attribute: kAXSelectedTextRangeAttribute as CFString
        ), selectedRange.length == 0 else {
            return false
        }

        let target = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return false }
        let valueNSString = value as NSString
        let targetLength = (target as NSString).length
        var caret = selectedRange.location
        guard caret >= 0, caret <= valueNSString.length else { return false }

        // Dictation appends one convenience space after sentence punctuation.
        if caret > 0,
           let trailingScalar = UnicodeScalar(valueNSString.character(at: caret - 1)),
           CharacterSet.whitespacesAndNewlines.contains(trailingScalar) {
            caret -= 1
        }
        guard caret >= targetLength else { return false }
        let candidateRange = NSRange(location: caret - targetLength, length: targetLength)
        guard valueNSString.substring(with: candidateRange) == target else { return false }

        selectedRange = CFRange(
            location: candidateRange.location,
            length: candidateRange.length + (selectedRange.location - caret)
        )
        guard let rangeValue = AXValueCreate(.cfRange, &selectedRange) else { return false }
        return AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        ) == .success
    }

    func collectContext() async -> AppContext {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return AppContext(
                appName: nil,
                bundleIdentifier: nil,
                windowTitle: nil,
                selectedText: nil,
                textBeforeCaret: nil,
                currentActivity: "You are dictating in an unrecognized context."
            )
        }

        let appName = frontmostApp.localizedName
        let bundleIdentifier = frontmostApp.bundleIdentifier
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        let windowTitle = focusedWindowTitle(from: appElement) ?? appName
        let selectedText = selectedText(from: appElement)

        return AppContext(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            selectedText: selectedText,
            textBeforeCaret: textBeforeCaret(from: appElement),
            currentActivity: Self.localActivity(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                selectedText: selectedText,
                windowTitle: windowTitle
            )
        )
    }

    static func localActivity(
        appName: String?,
        bundleIdentifier: String?,
        selectedText: String?,
        windowTitle: String?
    ) -> String {
        let activeApp = appName ?? "the active application"
        let writingContext = AppWritingContext.classify(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle
        )
        let selectionHint = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? " Nearby selected text is available as a tone and spelling hint."
            : ""
        return "The user is writing in \(activeApp), treated as \(writingContext.label).\(selectionHint)"
    }

    /// Captures up to `textBeforeCaretLimit` characters immediately before the
    /// caret in the focused editable element, so smart cleanup can continue
    /// existing text with matching capitalization and punctuation. Returns nil
    /// when there is no focused text element, the element is a secure field
    /// (never read passwords), the value is empty, or the caret sits at the
    /// very start.
    private func textBeforeCaret(from appElement: AXUIElement) -> String? {
        guard let focusedElement = accessibilityElement(
            from: appElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ) else { return nil }
        // Secure fields report "AXSecureTextField" as the subrole (native
        // AppKit) or occasionally as the role itself (some web views).
        let secureMarker = NSAccessibility.Subrole.secureTextField.rawValue
        let role = accessibilityRawString(from: focusedElement, attribute: kAXRoleAttribute as CFString)
        let subrole = accessibilityRawString(from: focusedElement, attribute: kAXSubroleAttribute as CFString)
        if role == secureMarker || subrole == secureMarker {
            return nil
        }
        guard let value = accessibilityRawString(
            from: focusedElement,
            attribute: kAXValueAttribute as CFString
        ), let selectedRange = accessibilityRange(
            from: focusedElement,
            attribute: kAXSelectedTextRangeAttribute as CFString
        ) else { return nil }

        // With an active selection, the text "before the caret" is the text
        // before the selection start: dictation replaces the selection.
        let valueNSString = value as NSString
        var caret = min(max(selectedRange.location, 0), valueNSString.length)
        guard caret > 0 else { return nil }
        // Never split a surrogate pair or composed character sequence.
        if caret < valueNSString.length {
            let composed = valueNSString.rangeOfComposedCharacterSequence(at: caret)
            caret = min(caret, composed.location)
        }
        guard caret > 0 else { return nil }

        let captured = String(valueNSString.substring(to: caret).suffix(Self.textBeforeCaretLimit))
        return captured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : captured
    }

    private func focusedWindowTitle(from appElement: AXUIElement) -> String? {
        guard let focusedWindow = accessibilityElement(from: appElement, attribute: kAXFocusedWindowAttribute as CFString) else {
            return nil
        }

        if let windowTitle = accessibilityString(from: focusedWindow, attribute: kAXTitleAttribute as CFString) {
            return trimmedText(windowTitle)
        }

        return nil
    }

    private func selectedText(from appElement: AXUIElement) -> String? {
        if let focusedElement = accessibilityElement(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString),
           let selectedText = accessibilityString(from: focusedElement, attribute: kAXSelectedTextAttribute as CFString) {
            return trimmedText(selectedText)
        }

        if let selectedText = accessibilityString(from: appElement, attribute: kAXSelectedTextAttribute as CFString) {
            return trimmedText(selectedText)
        }

        return nil
    }

    private func rawSelectedText(from appElement: AXUIElement) -> String? {
        if let focusedElement = accessibilityElement(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString),
           let selectedText = accessibilityRawString(from: focusedElement, attribute: kAXSelectedTextAttribute as CFString) {
            return selectedText
        }

        if let selectedText = accessibilityRawString(from: appElement, attribute: kAXSelectedTextAttribute as CFString) {
            return selectedText
        }

        return nil
    }

    private func accessibilityElement(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(rawValue, to: AXUIElement.self)
    }

    private func accessibilityString(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let stringValue = value as? String else { return nil }
        return trimmedText(stringValue)
    }

    private func accessibilityRawString(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let stringValue = value as? String else { return nil }
        return stringValue.isEmpty ? nil : stringValue
    }

    private func accessibilityRange(from element: AXUIElement, attribute: CFString) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeBitCast(rawValue, to: AXValue.self)
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private func trimmedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return trimmed.isEmpty ? nil : trimmed
    }
}
