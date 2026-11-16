import MediaPlayer
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlayerEngine.self) private var engine
    @Query(sort: \Song.createdAt, order: .reverse) private var songs: [Song]

    @State private var path: [Song] = []
    @State private var importing = false
    @State private var pickingFromMusic = false
    @State private var copying = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if songs.isEmpty {
                    ContentUnavailableView {
                        Label("No songs yet", systemImage: "waveform")
                    } description: {
                        Text("Pick a song from your Music library, import a bounce from Files, or share an audio file to Song Notes from another app.")
                    } actions: {
                        Button("From Music Library") { pickingFromMusic = true }
                            .buttonStyle(.borderedProminent)
                        Button("From Files") { importing = true }
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
                    Menu("Add Song", systemImage: "plus") {
                        Button("From Music Library", systemImage: "music.note") { pickingFromMusic = true }
                        Button("From Files", systemImage: "folder") { importing = true }
                    }
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
        .sheet(isPresented: $pickingFromMusic) {
            MusicLibraryPicker { item in
                pickingFromMusic = false
                if let item { addSong(from: item) }
            }
            .ignoresSafeArea()
        }
        .overlay {
            if copying { CopyingOverlay() }
        }
        .alert("Couldn't import audio", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func addSong(from url: URL) {
        do {
            addSong(try AudioLibrary.importAudio(from: url))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addSong(from item: MPMediaItem) {
        copying = true
        Task {
            defer { copying = false }
            do {
                addSong(try await AudioLibrary.importLibraryItem(item))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addSong(_ imported: AudioLibrary.Imported) {
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
        // Save first so the song's identity is final before navigating to it.
        try? context.save()
        path = [song]
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

/// Shown while a song is being copied out of the Music library.
struct CopyingOverlay: View {
    var body: some View {
        ProgressView("Copying song…")
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
