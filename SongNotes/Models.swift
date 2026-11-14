import Foundation
import SwiftData

@Model
final class Song {
    var title: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Mix.song) var mixes: [Mix] = []

    init(title: String) {
        self.title = title
        self.createdAt = .now
    }

    var sortedMixes: [Mix] { mixes.sorted { $0.addedAt < $1.addedAt } }
}

/// One bounce of a song. Notes belong to the bounce they were heard on.
@Model
final class Mix {
    var uuid: UUID
    var label: String
    /// File name inside Documents/Audio. Relative, because the container path changes between installs.
    var fileName: String
    var sourceName: String
    var duration: Double
    var addedAt: Date
    var song: Song?
    @Relationship(deleteRule: .cascade, inverse: \Note.mix) var notes: [Note] = []

    init(label: String, fileName: String, sourceName: String, duration: Double) {
        self.uuid = UUID()
        self.label = label
        self.fileName = fileName
        self.sourceName = sourceName
        self.duration = duration
        self.addedAt = .now
    }

    var sortedNotes: [Note] { notes.sorted { $0.time < $1.time } }
}

/// A timestamped note. Empty text means a bare marker waiting to be filled in.
@Model
final class Note {
    var time: Double
    var text: String
    var resolved: Bool
    var createdAt: Date
    var mix: Mix?

    init(time: Double, text: String = "") {
        self.time = time
        self.text = text
        self.resolved = false
        self.createdAt = .now
    }
}

func timestamp(_ seconds: Double) -> String {
    let total = Int(max(0, seconds))
    return String(format: "%d:%02d", total / 60, total % 60)
}
