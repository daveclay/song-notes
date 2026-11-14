import MediaPlayer
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SongView: View {
    @Environment(\.modelContext) private var context
    @Environment(PlayerEngine.self) private var engine
    @Bindable var song: Song

    @State private var mix: Mix?
    @State private var editingNote: Note?
    @State private var dictatingNote: Note?
    @State private var resumeAfterDictation = false
    @State private var importing = false
    @State private var pickingFromMusic = false
    @State private var copying = false
    @State private var renaming = false
    @State private var errorMessage: String?

    private var isLoaded: Bool {
        guard let mix else { return false }
        return engine.loadedMixID == mix.uuid
    }

    private var notes: [Note] { mix?.sortedNotes ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            playerPanel
            Divider()
            notesList
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    addNote()
                } label: {
                    Label("Add Note", systemImage: "plus.bubble.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                Button {
                    speakNote()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.title3.weight(.semibold))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                }
                .accessibilityLabel("Speak Note")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isLoaded)
            .padding()
            .background(.bar)
        }
        .sheet(item: $dictatingNote) { note in
            DictationSheet(note: note) {
                if resumeAfterDictation {
                    resumeAfterDictation = false
                    engine.play()
                }
            }
        }
        .navigationTitle(song.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: exportText) {
                    Label("Export Notes", systemImage: "square.and.arrow.up")
                }
                .disabled(notes.isEmpty)
                versionMenu
            }
        }
        .sheet(item: $editingNote) { note in
            NoteEditor(note: note) {
                context.delete(note)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url): addVersion(from: url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $pickingFromMusic) {
            MusicLibraryPicker { item in
                pickingFromMusic = false
                if let item { addVersion(from: item) }
            }
            .ignoresSafeArea()
        }
        .overlay {
            if copying { CopyingOverlay() }
        }
        .alert("Rename Song", isPresented: $renaming) {
            TextField("Title", text: $song.title)
            Button("Done") {}
        }
        .alert("Something went wrong", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if mix == nil, let latest = song.sortedMixes.last {
                activate(latest)
            }
        }
    }

    // MARK: - Sections

    private var playerPanel: some View {
        VStack(spacing: 12) {
            if let mix {
                Text("\(mix.label) · \(mix.sourceName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Scrubber(
                duration: mix?.duration ?? 0,
                currentTime: isLoaded ? engine.currentTime : 0,
                markers: notes.map(\.time),
                onSeek: { engine.seek(to: $0) }
            )
            .disabled(!isLoaded)

            HStack(spacing: 44) {
                Button {
                    engine.skip(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title)
                }
                Button {
                    engine.toggle()
                } label: {
                    Image(systemName: isLoaded && engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                }
                Button {
                    engine.skip(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title)
                }
            }
            .disabled(!isLoaded)
        }
        .padding()
    }

    @ViewBuilder
    private var notesList: some View {
        if notes.isEmpty {
            ContentUnavailableView {
                Label("No notes yet", systemImage: "text.bubble")
            } description: {
                Text("Tap Add Note while listening. In the car or on headphones, press Next Track to drop a marker and fill it in later.")
            }
        } else {
            List {
                ForEach(notes) { note in
                    Button {
                        engine.seek(to: note.time)
                    } label: {
                        NoteRow(note: note)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            context.delete(note)
                        }
                        Button("Edit", systemImage: "pencil") {
                            editingNote = note
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading) {
                        Button(note.resolved ? "Reopen" : "Resolve", systemImage: "checkmark") {
                            note.resolved.toggle()
                        }
                        .tint(.green)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var versionMenu: some View {
        Menu {
            Picker("Version", selection: Binding(
                get: { mix?.uuid },
                set: { id in
                    if let picked = song.mixes.first(where: { $0.uuid == id }) {
                        activate(picked)
                    }
                }
            )) {
                ForEach(song.sortedMixes) { item in
                    Text("\(item.label) · \(item.sourceName)").tag(Optional(item.uuid))
                }
            }
            Divider()
            Button("Add Version from Music Library…", systemImage: "music.note") { pickingFromMusic = true }
            Button("Add Version from Files…", systemImage: "folder") { importing = true }
            Button("Rename Song…", systemImage: "pencil") { renaming = true }
        } label: {
            Label("Versions", systemImage: "square.stack")
        }
    }

    // MARK: - Actions

    private func activate(_ newMix: Mix) {
        mix = newMix
        if engine.loadedMixID != newMix.uuid {
            do {
                try engine.load(
                    mixID: newMix.uuid,
                    url: AudioLibrary.url(for: newMix.fileName),
                    title: song.title,
                    subtitle: newMix.label
                )
            } catch {
                errorMessage = "Couldn't open the audio file: \(error.localizedDescription)"
                return
            }
        }
        let context = context
        engine.onRemoteMarker = { time in
            let note = Note(time: time)
            note.mix = newMix
            context.insert(note)
        }
    }

    private func addNote() {
        guard let mix else { return }
        // Capture the time now; typing happens while the song keeps playing.
        let note = Note(time: engine.markerTime)
        note.mix = mix
        context.insert(note)
        editingNote = note
    }

    private func speakNote() {
        guard let mix else { return }
        let note = Note(time: engine.markerTime)
        note.mix = mix
        context.insert(note)
        // The song pauses while you talk so the microphone hears you, not the mix.
        resumeAfterDictation = engine.isPlaying
        engine.pause()
        dictatingNote = note
    }

    private func addVersion(from url: URL) {
        do {
            addVersion(try AudioLibrary.importAudio(from: url))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addVersion(from item: MPMediaItem) {
        copying = true
        Task {
            defer { copying = false }
            do {
                addVersion(try await AudioLibrary.importLibraryItem(item))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addVersion(_ imported: AudioLibrary.Imported) {
        let newMix = Mix(
            label: "v\(song.mixes.count + 1)",
            fileName: imported.fileName,
            sourceName: imported.sourceName,
            duration: imported.duration
        )
        newMix.song = song
        context.insert(newMix)
        activate(newMix)
    }

    private var exportText: String {
        var lines = ["\(song.title) — \(mix?.label ?? "")", ""]
        for note in notes {
            let text = note.text.isEmpty ? "(marker)" : note.text
            lines.append("\(note.resolved ? "[x]" : "[ ]") \(timestamp(note.time))  \(text)")
        }
        return lines.joined(separator: "\n")
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(timestamp(note.time))
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.tint)
            Text(note.text.isEmpty ? "Marker — swipe to add a note" : note.text)
                .foregroundStyle(note.text.isEmpty || note.resolved ? .secondary : .primary)
                .strikethrough(note.resolved)
            Spacer(minLength: 0)
            if note.resolved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct Scrubber: View {
    let duration: Double
    let currentTime: Double
    let markers: [Double]
    let onSeek: (Double) -> Void

    @State private var dragValue: Double?

    /// Approximate inset of the slider thumb's travel from the slider's edges.
    private let thumbInset: CGFloat = 14

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let travel = max(0, geo.size.width - thumbInset * 2)
                ForEach(Array(markers.enumerated()), id: \.offset) { _, time in
                    Capsule()
                        .fill(.orange)
                        .frame(width: 3, height: 10)
                        .position(
                            x: thumbInset + travel * (duration > 0 ? time / duration : 0),
                            y: geo.size.height / 2
                        )
                }
            }
            .frame(height: 10)

            Slider(
                value: Binding(
                    get: { dragValue ?? currentTime },
                    set: { dragValue = $0 }
                ),
                in: 0...max(duration, 0.1)
            ) { editing in
                if !editing, let value = dragValue {
                    onSeek(value)
                    dragValue = nil
                }
            }

            HStack {
                Text(timestamp(dragValue ?? currentTime))
                Spacer()
                Text(timestamp(duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}
