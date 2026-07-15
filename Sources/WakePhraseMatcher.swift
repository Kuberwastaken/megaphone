import Foundation

enum WakePhrase: String, Equatable {
    case heyMegaphone
    case megaphone
}

struct WakePhraseMatch: Equatable {
    let phrase: WakePhrase
    let trailingText: String
}

/// Recognizes a wake phrase at the beginning of a live speech transcript.
///
/// Speech recognizers repeatedly publish increasingly complete versions of the
/// same utterance. `observe` therefore emits at most once until a non-matching
/// transcript is observed after the cooldown, or the caller explicitly rearms
/// the matcher for a new recognition session.
struct WakePhraseMatcher {
    var plainMegaphoneEnabled: Bool
    var cooldown: TimeInterval

    private var isArmed = true
    private var lastMatchDate: Date?

    init(plainMegaphoneEnabled: Bool = false, cooldown: TimeInterval = 1.0) {
        self.plainMegaphoneEnabled = plainMegaphoneEnabled
        self.cooldown = max(0, cooldown)
    }

    mutating func observe(_ transcript: String, at date: Date = Date()) -> WakePhraseMatch? {
        let detected = Self.detect(in: transcript, plainMegaphoneEnabled: plainMegaphoneEnabled)

        guard isArmed else {
            if detected == nil, cooldownHasElapsed(at: date) {
                isArmed = true
            }
            return nil
        }

        guard let detected else { return nil }
        isArmed = false
        lastMatchDate = date
        return detected
    }

    mutating func rearm() {
        isArmed = true
        lastMatchDate = nil
    }

    static func detect(
        in transcript: String,
        plainMegaphoneEnabled: Bool = false
    ) -> WakePhraseMatch? {
        if let match = match(pattern: heyPattern, phrase: .heyMegaphone, in: transcript) {
            return match
        }
        guard plainMegaphoneEnabled else { return nil }
        return match(pattern: plainPattern, phrase: .megaphone, in: transcript)
    }

    private func cooldownHasElapsed(at date: Date) -> Bool {
        guard let lastMatchDate else { return true }
        return date.timeIntervalSince(lastMatchDate) >= cooldown
    }

    private static func match(
        pattern: NSRegularExpression,
        phrase: WakePhrase,
        in transcript: String
    ) -> WakePhraseMatch? {
        let range = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        guard let result = pattern.firstMatch(in: transcript, range: range),
              let matchedRange = Range(result.range, in: transcript) else {
            return nil
        }

        let trailing = transcript[matchedRange.upperBound...]
            .drop(while: { character in
                character.unicodeScalars.allSatisfy { trailingSeparators.contains($0) }
            })
        return WakePhraseMatch(phrase: phrase, trailingText: String(trailing))
    }

    private static let leadingSeparators = #"^[\s\p{P}\p{S}]*"#
    private static let phraseSeparator = #"[\s\p{P}\p{S}]+"#
    private static let phraseBoundary = #"(?=$|[\s\p{P}\p{S}])"#

    private static let heyPattern = try! NSRegularExpression(
        pattern: leadingSeparators + "hey" + phraseSeparator + "megaphone" + phraseBoundary,
        options: [.caseInsensitive]
    )
    private static let plainPattern = try! NSRegularExpression(
        pattern: leadingSeparators + "megaphone" + phraseBoundary,
        options: [.caseInsensitive]
    )
    private static let trailingSeparators = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)
}
