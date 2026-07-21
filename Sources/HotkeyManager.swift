import Cocoa

final class HotkeyManager {
    private let backend = GlobalShortcutBackend()
    private var configuration = ShortcutConfiguration(
        hold: .defaultHold,
        toggle: .defaultToggle
    )
    private var inputState = ShortcutInputState()

    var onShortcutEvent: ((ShortcutEvent) -> Void)?
    var onEscapeKeyPressed: (() -> Bool)?
    /// Down/up of the configured mouse dictation button. Return true to
    /// consume the click. Only fired when start(...) received a button.
    var onMouseButtonEvent: ((_ isDown: Bool) -> Bool)?

    var currentPressedModifiers: ShortcutModifiers {
        inputState.currentModifiers
    }

    var hasPressedShortcutInputs: Bool {
        inputState.hasPressedShortcutInputs(configuration: configuration)
    }

    func start(configuration: ShortcutConfiguration, mouseButtonNumber: Int? = nil) throws {
        stop()
        self.configuration = configuration
        backend.onInputEvent = { [weak self] event in
            self?.handleInputEvent(event) ?? .passthrough
        }
        backend.onEscapeKeyPressed = { [weak self] in
            self?.onEscapeKeyPressed?() ?? false
        }
        backend.onMouseButtonEvent = { [weak self] isDown in
            self?.onMouseButtonEvent?(isDown) ?? false
        }
        do {
            try backend.start(mouseButtonNumber: mouseButtonNumber)
        } catch {
            backend.onInputEvent = nil
            backend.onEscapeKeyPressed = nil
            backend.onMouseButtonEvent = nil
            inputState = ShortcutInputState()
            throw error
        }
    }

    func stop() {
        backend.stop()
        backend.onInputEvent = nil
        backend.onEscapeKeyPressed = nil
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
        for event in result.emittedEvents {
            onShortcutEvent?(event)
        }
        return result.consumeDecision
    }
}
