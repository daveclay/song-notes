import AVFoundation
import Observation
import os
import Speech
import SwiftUI

/// Turns speech from the microphone into text. Plays a short two-tone cue when the
/// microphone is live, and stops by itself after a pause in speech.
@MainActor
@Observable
final class Dictation {
    private(set) var transcript = ""
    /// True once the microphone is delivering audio and the "speak now" cue has played.
    private(set) var isReady = false
    private(set) var finished = false
    private(set) var errorMessage: String?

    /// How long to wait for the first word, and how long a pause ends the note.
    private static let initialTimeout: TimeInterval = 6
    private static let pauseTimeout: TimeInterval = 2

    /// Called once when listening ends by itself (after a pause in speech or a timeout).
    @ObservationIgnored var onFinished: (() -> Void)?

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private let cuePlayer = AVAudioPlayerNode()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTimer: Timer?
    @ObservationIgnored private var stopped = false
    /// Closed until the cue has played, so the cue itself isn't transcribed.
    @ObservationIgnored private let gate = OSAllocatedUnfairLock(initialState: false)

    /// - Parameter usePhoneMicrophone: listen with the iPhone's own microphone and leave
    ///   the Bluetooth connection alone, instead of switching to the car or headphone mic.
    func start(usePhoneMicrophone: Bool = false) async {
        guard await Self.requestPermissions() else {
            errorMessage = "Allow Microphone and Speech Recognition for Song Notes in Settings to speak notes."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        do {
            // Connecting a car or headphone microphone can take a few seconds.
            try await Self.activateSession(usePhoneMicrophone: usePhoneMicrophone)
            guard !stopped else { return }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Keeps audio on the phone and works without signal.
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            let cueFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
            audioEngine.attach(cuePlayer)
            audioEngine.connect(cuePlayer, to: audioEngine.mainMixerNode, format: cueFormat)

            let installed = Self.installTap(
                on: audioEngine.inputNode, feeding: request, gate: gate
            ) { [weak self] in
                Task { @MainActor in self?.microphoneIsLive() }
            }
            guard installed else {
                errorMessage = "No microphone is available."
                stop()
                return
            }
            audioEngine.prepare()
            try audioEngine.start()

            task = Self.startTask(recognizer: recognizer, request: request) { [weak self] text, done in
                Task { @MainActor in self?.handle(text: text, done: done) }
            }
        } catch {
            errorMessage = "Couldn't start listening: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        stopped = true
        silenceTimer?.invalidate()
        silenceTimer = nil
        gate.withLock { $0 = false }
        if audioEngine.isRunning {
            cuePlayer.stop()
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        isReady = false
    }

    // MARK: - Private

    /// The first audio has arrived from the microphone: play the cue, then start listening.
    private func microphoneIsLive() {
        guard !stopped, audioEngine.isRunning else { return }
        let cueLength = playCue()
        Task {
            try? await Task.sleep(for: .seconds(cueLength + 0.1))
            guard !stopped else { return }
            gate.withLock { $0 = true }
            isReady = true
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            scheduleTimeout(Self.initialTimeout)
        }
    }

    /// Plays a rising two-tone beep through the same audio route as the microphone,
    /// so hearing it means the connection is up. Returns its length in seconds.
    private func playCue() -> TimeInterval {
        let length = 0.24
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate * length)
              ),
              let samples = buffer.floatChannelData?[0]
        else { return 0 }

        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) {
            let time = Double(index) / format.sampleRate
            let frequency = time < length / 2 ? 880.0 : 1320.0
            let fade = min(1, min(time, length - time) / 0.01)
            samples[index] = Float(sin(2 * .pi * frequency * time) * 0.4 * fade)
        }
        cuePlayer.scheduleBuffer(buffer)
        cuePlayer.play()
        return length
    }

    private func handle(text: String?, done: Bool) {
        if let text, !text.isEmpty {
            transcript = text
            if isReady { scheduleTimeout(Self.pauseTimeout) }
        }
        if done { finish() }
    }

    func finish() {
        guard !finished else { return }
        stop()
        finished = true
        onFinished?()
    }

    private func scheduleTimeout(_ interval: TimeInterval) {
        silenceTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
        RunLoop.main.add(timer, forMode: .common)
        silenceTimer = timer
    }

    // These run off the main thread, so they are set up outside the main actor.

    nonisolated static func requestPermissions() async -> Bool {
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAllowed else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private nonisolated static func activateSession(usePhoneMicrophone: Bool) async throws {
        let session = AVAudioSession.sharedInstance()
        if usePhoneMicrophone {
            try AudioSessionSetup.usePhoneMicrophone()
        } else {
            try session.setCategory(
                .playAndRecord, mode: .measurement,
                options: [.allowBluetoothHFP, .defaultToSpeaker]
            )
        }
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true)
    }

    private nonisolated static func installTap(
        on input: AVAudioInputNode,
        feeding request: SFSpeechAudioBufferRecognitionRequest,
        gate: OSAllocatedUnfairLock<Bool>,
        onFirstBuffer: @escaping @Sendable () -> Void
    ) -> Bool {
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        let announced = OSAllocatedUnfairLock(initialState: false)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let isFirst = announced.withLock { seen in
                defer { seen = true }
                return !seen
            }
            if isFirst { onFirstBuffer() }
            if gate.withLock({ $0 }) {
                request.append(buffer)
            }
        }
        return true
    }

    private nonisolated static func startTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onUpdate: @escaping @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onUpdate(result?.bestTranscription.formattedString, result?.isFinal == true || error != nil)
        }
    }
}

/// Listens, shows the words as they arrive, and writes them into the note when done.
struct DictationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var note: Note
    let onFinish: () -> Void

    @State private var dictation = Dictation()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: dictation.isReady ? "mic.fill" : "mic.slash.fill")
                .font(.system(size: 44))
                .foregroundStyle(dictation.isReady ? Color.red : Color.secondary)
                .symbolEffect(.pulse, isActive: dictation.isReady)

            Text("Note at \(timestamp(note.time))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            if let error = dictation.errorMessage {
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else if !dictation.isReady && dictation.transcript.isEmpty {
                ProgressView("Connecting microphone… wait for the beep")
            } else {
                Text(dictation.transcript.isEmpty ? "Listening — speak now" : dictation.transcript)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(dictation.transcript.isEmpty ? .secondary : .primary)
            }

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .padding(.top, 12)
        .presentationDetents([.medium])
        .task { await dictation.start() }
        .onChange(of: dictation.finished) { _, finished in
            if finished { dismiss() }
        }
        .onDisappear {
            dictation.stop()
            if !dictation.transcript.isEmpty {
                note.text = dictation.transcript
            }
            onFinish()
        }
    }
}
