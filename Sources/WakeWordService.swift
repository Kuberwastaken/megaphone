import AVFoundation
import Combine
import CoreMedia
import Foundation
import Speech
import os.log

private let wakeWordLog = OSLog(
    subsystem: "com.kuberwastaken.megaphone",
    category: "WakeWord"
)

/// Keeps a low-power, on-device SpeechAnalyzer stream open while Megaphone is
/// idle and reports only explicit wake phrases. The service never writes audio
/// to disk and never sends microphone data off the Mac.
final class WakeWordService: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum State: Equatable {
        case disabled
        case listening
        case suspended
        case unavailable
        case error(String)
    }

    @Published private(set) var state: State = .disabled

    private let sessionQueue = DispatchQueue(label: "com.kuberwastaken.megaphone.wake.capture")
    private let sampleQueue = DispatchQueue(label: "com.kuberwastaken.megaphone.wake.samples")
    private let lock = OSAllocatedUnfairLock(initialState: MutableState())

    private var captureSession: AVCaptureSession?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?

    private struct MutableState {
        var generation = UUID()
        var matcher = WakePhraseMatcher()
        var onWake: ((WakePhraseMatch) -> Void)?
        var suspended = false
    }

    override init() {
        super.init()
    }

    deinit {
        startupTask?.cancel()
        resultsTask?.cancel()
        inputContinuation?.finish()
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        captureSession?.stopRunning()
    }

    /// Starts listening with the chosen locale and microphone. Calling start
    /// again atomically replaces the previous recognition session.
    func start(
        locale: Locale,
        selectedMicrophoneID: String,
        allowPlainMegaphone: Bool,
        onWake: @escaping (WakePhraseMatch) -> Void
    ) {
        stop()

        let generation = UUID()
        lock.withLock { state in
            state.generation = generation
            state.matcher = WakePhraseMatcher(plainMegaphoneEnabled: allowPlainMegaphone)
            state.onWake = onWake
            state.suspended = false
        }

        guard SpeechTranscriber.isAvailable else {
            publish(.unavailable, generation: generation)
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            // Permission prompts belong to setup/settings, never to a passive
            // background listener starting unexpectedly.
            publish(.unavailable, generation: generation)
            return
        }

        startupTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Wake recognition needs partial hypotheses; the normal
                // dictation transcriber intentionally reports final text only.
                let transcriber = SpeechTranscriber(
                    locale: locale,
                    transcriptionOptions: [],
                    reportingOptions: [.volatileResults, .fastResults],
                    attributeOptions: []
                )
                try await SpeechAnalyzerService.ensureAssets(for: transcriber, locale: locale)
                guard !Task.isCancelled,
                      let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
                else {
                    if !Task.isCancelled { self.publish(.unavailable, generation: generation) }
                    return
                }

                let analyzer = SpeechAnalyzer(modules: [transcriber])
                let context = AnalysisContext()
                context.contextualStrings[.general] = ["Hey Megaphone", "Megaphone"]
                do {
                    try await analyzer.setContext(context)
                } catch {
                    // Context bias is an optimization; recognition still works
                    // if the current locale does not accept it.
                    os_log(.error, log: wakeWordLog, "wake phrase context failed: %{public}@", error.localizedDescription)
                }
                let (inputs, continuation) = AsyncStream<AnalyzerInput>.makeStream()
                let collector = Task { [weak self] in
                    do {
                        for try await result in transcriber.results {
                            guard !Task.isCancelled else { return }
                            // Volatile results revise earlier hypotheses, so
                            // appending would duplicate words as recognition
                            // converges. Each result is matched independently.
                            self?.observe(String(result.text.characters), generation: generation)
                        }
                    } catch is CancellationError {
                        // Normal shutdown.
                    } catch {
                        self?.fail(error, generation: generation)
                    }
                }
                try await analyzer.start(inputSequence: inputs)
                guard !Task.isCancelled, self.isCurrent(generation) else {
                    continuation.finish()
                    collector.cancel()
                    await analyzer.cancelAndFinishNow()
                    return
                }

                self.sessionQueue.async { [weak self] in
                    guard let self, self.isCurrent(generation) else { return }
                    do {
                        let session = try self.makeCaptureSession(selectedMicrophoneID: selectedMicrophoneID)
                        self.analyzer = analyzer
                        self.sampleQueue.sync {
                            self.analyzerFormat = format
                            self.inputContinuation = continuation
                            self.converter = nil
                            self.sourceFormat = nil
                        }
                        self.resultsTask = collector
                        self.captureSession = session
                        session.startRunning()
                        guard session.isRunning else {
                            throw WakeWordError.captureDidNotStart
                        }
                        self.publish(.listening, generation: generation)
                    } catch {
                        continuation.finish()
                        collector.cancel()
                        Task { await analyzer.cancelAndFinishNow() }
                        self.fail(error, generation: generation)
                    }
                }
            } catch is CancellationError {
                // A newer start or stop superseded setup.
            } catch {
                self.fail(error, generation: generation)
            }
        }
    }

    func stop() {
        let oldAnalyzer = analyzer
        let newGeneration = UUID()
        lock.withLock { state in
            state.generation = newGeneration
            state.onWake = nil
            state.suspended = false
            state.matcher.rearm()
        }
        startupTask?.cancel()
        startupTask = nil
        resultsTask?.cancel()
        resultsTask = nil
        sampleQueue.sync {
            inputContinuation?.finish()
            inputContinuation = nil
            analyzerFormat = nil
            converter = nil
            sourceFormat = nil
        }
        analyzer = nil
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.captureSession = nil
        }
        if let oldAnalyzer {
            Task { await oldAnalyzer.cancelAndFinishNow() }
        }
        publish(.disabled, generation: newGeneration)
    }

    /// Pauses microphone capture while Megaphone is dictating, preventing its
    /// own output or the dictation command from retriggering the wake listener.
    func suspend() {
        let generation = lock.withLock { state -> UUID in
            state.suspended = true
            state.matcher.rearm()
            return state.generation
        }
        sessionQueue.async { [weak self] in self?.captureSession?.stopRunning() }
        publish(.suspended, generation: generation)
    }

    func resume() {
        let generation = lock.withLock { state -> UUID in
            state.suspended = false
            state.matcher.rearm()
            return state.generation
        }
        sessionQueue.async { [weak self] in
            guard let self, self.analyzer != nil else { return }
            self.captureSession?.startRunning()
            if self.captureSession?.isRunning == true {
                self.publish(.listening, generation: generation)
            } else {
                self.fail(WakeWordError.captureDidNotStart, generation: generation)
            }
        }
    }

    func setAllowPlainMegaphone(_ enabled: Bool) {
        lock.withLock { state in
            state.matcher.plainMegaphoneEnabled = enabled
            state.matcher.rearm()
        }
    }

    // MARK: Capture

    private func makeCaptureSession(selectedMicrophoneID: String) throws -> AVCaptureSession {
        let device: AVCaptureDevice?
        if selectedMicrophoneID.isEmpty || selectedMicrophoneID == "default" {
            device = AVCaptureDevice.default(for: .audio)
        } else {
            let types: [AVCaptureDevice.DeviceType] = [.microphone, .external]
            device = AVCaptureDevice.DiscoverySession(
                deviceTypes: types,
                mediaType: .audio,
                position: .unspecified
            ).devices.first { $0.uniqueID == selectedMicrophoneID }
                ?? AVCaptureDevice.default(for: .audio)
        }
        guard let device else { throw WakeWordError.noMicrophone }

        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw WakeWordError.captureConfigurationFailed
        }
        session.addInput(input)
        session.addOutput(output)
        return session
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !lock.withLock({ $0.suspended }),
              let targetFormat = analyzerFormat,
              let continuation = inputContinuation,
              let description = CMSampleBufferGetFormatDescription(sampleBuffer)
        else { return }

        let incomingFormat = AVAudioFormat(cmAudioFormatDescription: description)
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frameCount > 0,
              let input = AVAudioPCMBuffer(pcmFormat: incomingFormat, frameCapacity: frameCount)
        else { return }
        input.frameLength = frameCount
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: input.mutableAudioBufferList
        ) == noErr else { return }

        if converter == nil || sourceFormat != incomingFormat {
            converter = AVAudioConverter(from: incomingFormat, to: targetFormat)
            converter?.primeMethod = .none
            sourceFormat = incomingFormat
        }
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / incomingFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(frameCount) * ratio)) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            guard !supplied else {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        if status != .error, converted.frameLength > 0 {
            continuation.yield(AnalyzerInput(buffer: converted))
        } else if let conversionError {
            os_log(.error, log: wakeWordLog, "audio conversion failed: %{public}@", conversionError.localizedDescription)
        }
    }

    // MARK: Results and state

    private func observe(_ transcript: String, generation: UUID) {
        let callbackAndMatch = lock.withLock { state -> (((WakePhraseMatch) -> Void), WakePhraseMatch)? in
            guard state.generation == generation, !state.suspended,
                  let callback = state.onWake,
                  let match = state.matcher.observe(transcript)
            else { return nil }
            return (callback, match)
        }
        guard let (callback, match) = callbackAndMatch else { return }
        os_log(.info, log: wakeWordLog, "detected wake phrase %{public}@", match.phrase.rawValue)
        DispatchQueue.main.async { callback(match) }
    }

    private func isCurrent(_ generation: UUID) -> Bool {
        lock.withLock { $0.generation == generation }
    }

    private func fail(_ error: Error, generation: UUID) {
        guard isCurrent(generation) else { return }
        os_log(.error, log: wakeWordLog, "wake listener failed: %{public}@", error.localizedDescription)
        resultsTask?.cancel()
        resultsTask = nil
        sampleQueue.async { [weak self] in
            self?.inputContinuation?.finish()
            self?.inputContinuation = nil
            self?.analyzerFormat = nil
            self?.converter = nil
            self?.sourceFormat = nil
        }
        if let analyzer {
            self.analyzer = nil
            Task { await analyzer.cancelAndFinishNow() }
        }
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.captureSession = nil
        }
        publish(.error(error.localizedDescription), generation: generation)
    }

    private func publish(_ newState: State, generation: UUID) {
        guard isCurrent(generation) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(generation) else { return }
            self.state = newState
        }
    }
}

private enum WakeWordError: LocalizedError {
    case noMicrophone
    case captureConfigurationFailed
    case captureDidNotStart

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "No microphone is available for wake-word listening."
        case .captureConfigurationFailed: "The wake-word microphone session could not be configured."
        case .captureDidNotStart: "The wake-word microphone session could not start."
        }
    }
}
