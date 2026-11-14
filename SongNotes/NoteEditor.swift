import SwiftUI

struct NoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var note: Note
    let onDelete: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you hear?", text: $note.text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                }
                Section {
                    HStack {
                        Text("Time")
                        Spacer()
                        Button("−1s") { note.time = max(0, note.time - 1) }
                            .buttonStyle(.bordered)
                        Text(timestamp(note.time))
                            .font(.body.monospacedDigit())
                            .frame(minWidth: 52)
                        Button("+1s") { note.time += 1 }
                            .buttonStyle(.bordered)
                    }
                    Toggle("Resolved", isOn: $note.resolved)
                }
                Section {
                    Button("Delete Note", role: .destructive) {
                        dismiss()
                        onDelete()
                    }
                }
            }
            .navigationTitle("Note at \(timestamp(note.time))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}
