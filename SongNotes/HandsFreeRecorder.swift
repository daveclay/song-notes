import AVFoundation
import SwiftData

/// Audio session choices shared by playback and spoken notes.
enum AudioSessionSetup {
    static let handsFreeKey = "handsFreeNotes"

    /// Whether Next Track records a spoken note (on unless switched off in the song menu).
    static var handsFreeEnabled: Bool {
        UserDefaults.standard.object(forKey: handsFreeKey) as? Bool ?? true
    }

    /// Music plays through the car or headphones at full quality while the iPhone's own
    /// microphone stays available. Leaving the Bluetooth connection alone means there is
    /// no switching delay when a spoken note starts.
    static func usePhoneMicrophone() throws {
        try AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, mode: .default,
            options: [.allowBluetoothA2DP, .defaultToSpeaker]
        )
    }

    /// Called before playback starts. Playing with the microphone already available is
    /// what lets a spoken note start later while the app is in the background.
    static func configureForPlayback() {
        if handsFreeEnabled, AVAudioApplication.shared.recordPermission == .granted {
            do {
                try usePhoneMicrophone()
                return
            } catch {}
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }
}

/// Records a spoken note without any UI: pause the song, beep, listen, save, resume.
/// Started by the Next Track button on the car, headphones or lock screen.
@MainActor
final class HandsFreeRecorder {
    static let shared = HandsFreeRecorder()

    private var dictation: Dictation?

    var isRecording: Bool { dictation != nil }

    /// Fills `note` with what is said. If listening can't start, the note is left as an
    /// empty marker and the song carries on.
    func record(into note: Note, context: ModelContext, engine: PlayerEngine) {
        guard dictation == nil else { return }
        let wasPlaying = engine.isPlaying
        engine.pause()

        let dictation = Dictation()
        self.dictation = dictation

        let complete: () -> Void = { [weak self, weak dictation] in
            guard let self, let dictation, self.dictation === dictation else { return }
            dictation.onFinished = nil
            dictation.stop()
            if !dictation.transcript.isEmpty {
                note.text = dictation.transcript
                try? context.save()
            }
            self.dictation = nil
            if wasPlaying { engine.play() }
        }
        dictation.onFinished = complete

        Task {
            await dictation.start(usePhoneMicrophone: true)
            if dictation.errorMessage != nil { complete() }
        }
    }

    /// A second press of Next Track ends the note without waiting for the pause.
    func finishEarly() {
        dictation?.finish()
    }
}
