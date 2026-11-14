import AVFoundation
import Observation
import Speech
import SwiftUI

/// Turns speech from the microphone into text. Stops by itself after a pause in speech.
@MainActor
@Observable
final class Dictation {
    private(set) var transcript = ""
    private(set) var isListening = false
    private(set) var finished = false
    private(set) var errorMessage: String?

    /// How long to wait for the first word, and how long a pause ends the note.
    private static let initialTimeout: TimeInterval = 6
    private static let pauseTimeout: TimeInterval = 2

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTimer: Timer?

    func start() async {
        guard await Self.requestPermissions() else {
            errorMessage = "Allow Microphone and Speech Recognition for Song Notes in Settings to speak notes."
            return
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord, mode: .measurement,
                options: [.allowBluetoothHFP, .defaultToSpeaker]
            )
            try session.setActive(true)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            // Keeps audio on the phone and works without signal.
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.request = request

            guard Self.installTap(on: audioEngine.inputNode, feeding: request) else {
                errorMessage = "No microphone is available."
                stop()
                return
            }
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true

            task = Self.startTask(recognizer: recognizer, request: request) { [weak self] text, done in
                Task { @MainActor in self?.handle(text: text, done: done) }
            }
            scheduleTimeout(Self.initialTimeout)
        } catch {
            errorMessage = "Couldn't start listening: \(error.localizedDescription)"
            stop()
        }
    }

    func stop() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        isListening = false
    }

    // MARK: - Private

    private func handle(text: String?, done: Bool) {
        if let text, !text.isEmpty {
            transcript = text
            if isListening { scheduleTimeout(Self.pauseTimeout) }
        }
        if done { finish() }
    }

    private func finish() {
        stop()
        finished = true
    }

    private func scheduleTimeout(_ interval: TimeInterval) {
        silenceTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.finish() }
        }
        RunLoop.main.add(timer, forMode: .common)
        silenceTimer = timer
    }

    // These callbacks run off the main thread, so they are set up outside the main actor.

    private nonisolated static func requestPermissions() async -> Bool {
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAllowed else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private nonisolated static func installTap(
        on input: AVAudioInputNode, feeding request: SFSpeechAudioBufferRecognitionRequest
    ) -> Bool {
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
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
            Image(systemName: "mic.fill")
                .font(.system(size: 44))
                .foregroundStyle(dictation.isListening ? Color.red : Color.secondary)
                .symbolEffect(.pulse, isActive: dictation.isListening)

            Text("Note at \(timestamp(note.time))")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            if let error = dictation.errorMessage {
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text(dictation.transcript.isEmpty ? "Listening…" : dictation.transcript)
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
