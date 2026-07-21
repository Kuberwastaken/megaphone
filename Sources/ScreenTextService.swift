import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

/// Extracts the text currently visible in the frontmost window so wake
/// commands can act on it ("reply to this email", "answer his question").
/// Everything stays on-device: the accessibility tree is read first, and
/// Vision OCR of the focused window is used only when the tree is too
/// sparse AND Screen Recording was already granted — collection never
/// triggers a permission prompt mid-dictation.
final class ScreenTextService {
    static let shared = ScreenTextService()

    static let maxLength = 2_400
    private static let minUsefulAXLength = 120
    private static let maxElementVisits = 900
    private static let maxDepth = 24
    private static let collectionBudget = maxLength * 3

    func visibleText() async -> String? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontmost.processIdentifier
        let axText = accessibilityText(processIdentifier: pid)
        if let axText, axText.count >= Self.minUsefulAXLength {
            return axText
        }
        if CGPreflightScreenCaptureAccess(),
           let ocrText = await recognizedText(processIdentifier: pid),
           ocrText.count > (axText?.count ?? 0) {
            return ocrText
        }
        return axText
    }

    // MARK: Accessibility tree

    private func accessibilityText(processIdentifier: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        // Chromium and Electron apps only build the accessibility tree for
        // web content once a client asks for it.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let window = element(of: appElement, attribute: kAXFocusedWindowAttribute as CFString) else {
            return nil
        }

        var pieces: [String] = []
        var seen = Set<String>()
        var visits = 0
        var budget = Self.collectionBudget
        collectText(from: window, depth: 0, visits: &visits, budget: &budget, pieces: &pieces, seen: &seen)

        let joined = pieces
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !joined.isEmpty else { return nil }
        return Self.truncatedMiddle(joined, to: Self.maxLength)
    }

    private func collectText(
        from element: AXUIElement,
        depth: Int,
        visits: inout Int,
        budget: inout Int,
        pieces: inout [String],
        seen: inout Set<String>
    ) {
        guard depth <= Self.maxDepth, visits <= Self.maxElementVisits, budget > 0 else { return }
        visits += 1

        let role = string(of: element, attribute: kAXRoleAttribute as CFString) ?? ""
        if ["AXStaticText", "AXTextArea", "AXTextField", "AXHeading"].contains(role) {
            let value = string(of: element, attribute: kAXValueAttribute as CFString)
                ?? string(of: element, attribute: kAXTitleAttribute as CFString)
                ?? string(of: element, attribute: kAXDescriptionAttribute as CFString)
            if let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
               value.count >= 2,
               seen.insert(value).inserted {
                pieces.append(value)
                budget -= value.count
            }
        }

        guard let children = elementArray(of: element, attribute: kAXChildrenAttribute as CFString) else {
            return
        }
        for child in children {
            guard visits <= Self.maxElementVisits, budget > 0 else { return }
            collectText(from: child, depth: depth + 1, visits: &visits, budget: &budget, pieces: &pieces, seen: &seen)
        }
    }

    private func element(of element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let rawValue = value,
              CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(rawValue, to: AXUIElement.self)
    }

    private func elementArray(of element: AXUIElement, attribute: CFString) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let array = value as? [AnyObject] else {
            return nil
        }
        return array.compactMap {
            guard CFGetTypeID($0) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast($0, to: AXUIElement.self)
        }
    }

    private func string(of element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let stringValue = value as? String,
              !stringValue.isEmpty else {
            return nil
        }
        return stringValue
    }

    // MARK: OCR fallback

    private func recognizedText(processIdentifier: pid_t) async -> String? {
        guard let image = await focusedWindowImage(processIdentifier: processIdentifier) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { return nil }
        return Self.truncatedMiddle(lines.joined(separator: "\n"), to: Self.maxLength)
    }

    private func focusedWindowImage(processIdentifier: pid_t) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            let candidates = content.windows.filter {
                $0.owningApplication?.processID == processIdentifier && $0.isOnScreen
            }
            guard let window = candidates.max(by: {
                $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
            }) else {
                return nil
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = max(Int(window.frame.width * scale), 1)
            configuration.height = max(Int(window.frame.height * scale), 1)
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            return nil
        }
    }

    /// Keeps the start and, mostly, the end of overlong captures: in mail
    /// threads and chats the newest content sits at the bottom.
    static func truncatedMiddle(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let headCount = limit * 2 / 5
        let tailCount = limit - headCount - 4
        return "\(text.prefix(headCount))\n[…]\n\(text.suffix(tailCount))"
    }
}
