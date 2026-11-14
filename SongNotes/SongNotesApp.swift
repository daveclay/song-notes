import SwiftData
import SwiftUI

@main
struct SongNotesApp: App {
    @State private var engine = PlayerEngine()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(engine)
        }
        .modelContainer(for: [Song.self, Mix.self, Note.self])
    }
}
