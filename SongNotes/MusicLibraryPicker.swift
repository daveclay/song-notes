import AVFoundation
import MediaPlayer
import SwiftUI

/// Apple's song picker, limited to songs the app can actually copy:
/// downloaded to the phone and not copy-protected.
struct MusicLibraryPicker: UIViewControllerRepresentable {
    /// Called with the chosen song, or nil if the picker was cancelled.
    let onFinish: (MPMediaItem?) -> Void

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = false
        picker.showsCloudItems = false
        picker.showsItemsWithProtectedAssets = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: MPMediaPickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        let onFinish: (MPMediaItem?) -> Void

        init(onFinish: @escaping (MPMediaItem?) -> Void) {
            self.onFinish = onFinish
        }

        func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems collection: MPMediaItemCollection) {
            onFinish(collection.items.first)
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            onFinish(nil)
        }
    }
}

extension AudioLibrary {
    enum LibraryImportError: LocalizedError {
        case unavailable
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "This song can't be copied. It is either copy-protected or not downloaded to this phone."
            case .exportFailed:
                "The song couldn't be copied out of the Music library."
            }
        }
    }

    /// Copies a song out of the Music library into the app's own storage.
    static func importLibraryItem(_ item: MPMediaItem) async throws -> Imported {
        guard let assetURL = item.assetURL, !item.hasProtectedAsset else {
            throw LibraryImportError.unavailable
        }
        let asset = AVURLAsset(url: assetURL)
        let id = UUID().uuidString

        // Prefer an exact copy of the audio; fall back to re-encoding as AAC if
        // the original format can't be copied as-is.
        let containers: [(type: AVFileType, ext: String)] = [
            (.m4a, "m4a"), (.wav, "wav"), (.aiff, "aif"), (.caf, "caf"), (.mp3, "mp3"),
        ]
        for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetAppleM4A] {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset),
                  let container = containers.first(where: { session.supportedFileTypes.contains($0.type) })
            else { continue }

            let fileName = "\(id).\(container.ext)"
            let destination = url(for: fileName)
            session.outputURL = destination
            session.outputFileType = container.type
            await session.export()

            if session.status == .completed,
               let duration = try? AVAudioPlayer(contentsOf: destination).duration {
                return Imported(
                    fileName: fileName,
                    sourceName: item.title ?? "Untitled",
                    duration: duration
                )
            }
            try? FileManager.default.removeItem(at: destination)
        }
        throw LibraryImportError.exportFailed
    }
}
