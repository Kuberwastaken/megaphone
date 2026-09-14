import Cocoa

final class HotkeyManager {
    private let backend = GlobalShortcutBackend()
    private var configuration = ShortcutConfiguration(
        hold: .defaultHold,
        toggle: .defaultToggle
    )
    private var inputState = ShortcutInputState()

    var onShortcutEvent: ((ShortcutEvent) -> Void)?
    var onCancelKeyPressed: (() -> Bool)?
    /// Down/up of the configured mouse dictation button. Return true to
    /// consume the click. Only fired when start(...) received a button.
    var onMouseButtonEvent: ((_ isDown: Bool) -> Bool)?
    /// Whether the app in front right now is one the user excluded. Asked
    /// live on each input event rather than cached from workspace
    /// notifications: reading the frontmost app costs ~0.1µs, and the answer
    /// can never lag behind an app switch the way a cached copy can.
    var shouldIgnoreShortcuts: (() -> Bool)?

    var currentPressedModifiers: ShortcutModifiers {
        inputState.currentModifiers
    }

    var hasPressedShortcutInputs: Bool {
        inputState.hasPressedShortcutInputs(configuration: configuration)
    }

    private var isFrontmostAppExcluded: Bool {
        shouldIgnoreShortcuts?() ?? false
    }

    func start(configuration: ShortcutConfiguration, mouseButtonNumber: Int? = nil) throws {
        stop()
        self.configuration = configuration
        backend.onInputEvent = { [weak self] event in
            self?.handleInputEvent(event) ?? .passthrough
        }
        backend.onCancelKeyPressed = { [weak self] in
            guard let self, !self.isFrontmostAppExcluded else { return false }
            return self.onCancelKeyPressed?() ?? false
        }
        backend.onMouseButtonEvent = { [weak self] isDown in
            guard let self else { return false }
            // A press in an excluded app must not start dictation or be
            // swallowed; a release still runs so a session started elsewhere
            // can end.
            if isDown && self.isFrontmostAppExcluded { return false }
            return self.onMouseButtonEvent?(isDown) ?? false
        }
        backend.cancelBinding = ShortcutBinding.sanitizedCancelBinding(configuration.cancel)
        do {
            try backend.start(mouseButtonNumber: mouseButtonNumber)
        } catch {
            backend.onInputEvent = nil
            backend.onCancelKeyPressed = nil
            backend.onMouseButtonEvent = nil
            inputState = ShortcutInputState()
            throw error
        }
    }

    func stop() {
        backend.stop()
        backend.onInputEvent = nil
        backend.onCancelKeyPressed = nil
        backend.onMouseButtonEvent = nil
        inputState = ShortcutInputState()
    }

    deinit {
        stop()
    }

    private func handleInputEvent(_ event: ShortcutInputEvent) -> ShortcutConsumeDecision {
        let result = ShortcutMatcher.reduce(
            state: inputState,
            event: event,
            configuration: configuration
        )
        inputState = result.state

        // In an excluded app the matcher still tracks key state — so pressed
        // keys stay accurate across app switches — but nothing starts and no
        // event is ever swallowed. Deactivations still fire, which is what
        // ends a session that began in a normal app before focus moved here.
        //
        // The frontmost app is only looked up once the result is one that
        // exclusion could change, so the tap's view of every keystroke on the
        // system costs an array check, not a workspace lookup.
        let isSuppressed = ShortcutSuppression.canSuppress(
            emittedEvents: result.emittedEvents,
            wouldConsume: result.consumeDecision == .consume
        ) && isFrontmostAppExcluded

        let events = isSuppressed
            ? ShortcutSuppression.eventsAllowedWhileSuppressed(result.emittedEvents)
            : result.emittedEvents
        for event in events {
            onShortcutEvent?(event)
        }
        return isSuppressed ? .passthrough : result.consumeDecision
    }
}
