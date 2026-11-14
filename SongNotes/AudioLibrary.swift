import AVFoundation
import Foundation

/// Owns the app's private copies of imported audio files.
enum AudioLibrary {
    struct Imported {
        let fileName: String
        let sourceName: String
        let duration: Double
    }

    static var directory: URL {
        let dir = URL.documentsDirectory.appending(path: "Audio", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for fileName: String) -> URL {
        directory.appending(path: fileName)
    }

    static func importAudio(from source: URL) throws -> Imported {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = url(for: fileName)
        try FileManager.default.copyItem(at: source, to: destination)

        let duration: Double
        do {
            duration = try AVAudioPlayer(contentsOf: destination).duration
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }

        // Files opened from another app land in Documents/Inbox; we have our own copy now.
        if source.path.contains("/Inbox/") {
            try? FileManager.default.removeItem(at: source)
        }

        return Imported(
            fileName: fileName,
            sourceName: source.deletingPathExtension().lastPathComponent,
            duration: duration
        )
    }

    static func delete(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
