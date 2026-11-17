# Song Notes

An iPhone app for listening to songs you're working on and taking timestamped notes — in the car, on headphones, or at your desk.

Everything is stored on the phone. There is no account, backend, or sync.

## Features

- **Add songs** from your Music library, from Files, or by sharing an audio file to Song Notes from another app (AirDrop, share sheet). The app keeps its own copy.
- **Typed notes.** Tap Add Note; the timestamp is captured at the tap (backed off 2 seconds for reaction time) and the song keeps playing while you type.
- **Spoken notes.** Tap the mic; the song pauses, your speech is turned into text on the device, and playback resumes when you stop talking.
- **Hands-free spoken notes.** With the screen locked, press Next Track on the car, headphones, or lock screen: the song pauses, a beep plays, you say the note, and the song resumes. This uses the iPhone's own microphone. It can be switched off in a song's menu, in which case Next Track drops an empty marker to fill in later. Previous Track jumps back 15 seconds.
- **Review.** Notes are listed by time and shown as ticks on the scrubber. Tap a note to jump there; swipe to edit, delete, or mark it resolved.
- **Versions.** Add each new bounce as a version of the same song. Notes belong to the version they were heard on.
- **Export.** Share a version's notes as plain text:

  ```
  My Song — v2

  [ ] 0:42  vocal too loud in the pre-chorus
  [x] 1:15  snare is buried
  ```

## Requirements

- Xcode 26 or later
- An iPhone running iOS 17 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), only if you change the project structure (`brew install xcodegen`)

## Running it on your phone

1. Open `SongNotes.xcodeproj` in Xcode.
2. Select the SongNotes target and choose your team under Signing & Capabilities.
3. Plug in your iPhone, choose it as the run destination, and press Run.

With a free Apple ID the installed app expires after 7 days and has to be re-run from Xcode. A paid Apple Developer account removes that limit.

The app asks for permission the first time you use the microphone, speech recognition, or the Music library.

## Project layout

The Xcode project is generated from `project.yml`. After adding or removing source files, or changing build settings or `Info.plist` keys, edit `project.yml` and run:

```sh
xcodegen generate
```

Changes made to settings inside Xcode are overwritten by the next generate, so put them in `project.yml`.

| File | Purpose |
|---|---|
| `SongNotes/Models.swift` | Data model: `Song` → `Mix` (one bounce) → `Note` |
| `SongNotes/PlayerEngine.swift` | Playback, background audio, lock screen and remote controls |
| `SongNotes/AudioLibrary.swift` | The app's private copies of audio files |
| `SongNotes/MusicLibraryPicker.swift` | Picking and copying songs from the Music library |
| `SongNotes/Dictation.swift` | Speech-to-text for spoken notes |
| `SongNotes/HandsFreeRecorder.swift` | Spoken notes started from the Next Track button |
| `SongNotes/LibraryView.swift` | Song list and importing |
| `SongNotes/SongView.swift` | Player, notes list, versions, export |
| `SongNotes/NoteEditor.swift` | Editing a single note |

## Limitations

- **Music library:** only songs that are downloaded to the phone and not copy-protected can be added. Apple Music subscription tracks can't be.
- **Copies don't update:** changing a song in Music or Files doesn't change the copy in Song Notes. Add the new bounce as a new version.
- **No waveform:** the scrubber is a plain slider with marker ticks.
- **No backup or sync:** deleting the app deletes its songs and notes. Export notes you want to keep.
