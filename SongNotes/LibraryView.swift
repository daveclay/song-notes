import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlayerEngine.self) private var engine
    @Query(sort: \Song.createdAt, order: .reverse) private var songs: [Song]

    @State private var path: [Song] = []
    @State private var importing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView {
                        Label("No songs yet", systemImage: "waveform")
                    } description: {
                        Text("Import a bounce from Files, or share an audio file to Song Notes from another app.")
                    } actions: {
                        Button("Import Audio") { importing = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(songs) { song in
                            NavigationLink(value: song) {
                                SongRow(song: song)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Song Notes")
            .navigationDestination(for: Song.self) { song in
                SongView(song: song)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import Audio", systemImage: "plus") { importing = true }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): addSong(from: url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .onOpenURL { url in
            addSong(from: url)
        }
        .alert("Couldn't import audio", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func addSong(from url: URL) {
        do {
            let imported = try AudioLibrary.importAudio(from: url)
            let song = Song(title: imported.sourceName)
            context.insert(song)
            let mix = Mix(
                label: "v1",
                fileName: imported.fileName,
                sourceName: imported.sourceName,
                duration: imported.duration
            )
            mix.song = song
            context.insert(mix)
            path = [song]
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let song = songs[index]
            for mix in song.mixes {
                engine.unload(mixID: mix.uuid)
                AudioLibrary.delete(mix.fileName)
            }
            context.delete(song)
        }
    }
}

private struct SongRow: View {
    let song: Song

    var body: some View {
        let open = song.mixes.flatMap(\.notes).filter { !$0.resolved }.count
        VStack(alignment: .leading, spacing: 2) {
            Text(song.title)
                .font(.headline)
            Text("\(song.mixes.count) version\(song.mixes.count == 1 ? "" : "s") · \(open) open note\(open == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
