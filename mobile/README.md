# The editors, as an app

A Flutter app for making Friday Night Funkin' mods on a phone. It opens a mod
folder on the device, reads the songs and characters in it, and writes the same
files back — no import step, no export step, no copy of your mod living
somewhere else.

This is a different thing from `tools/`. Those are single HTML files you can
open anywhere, and they trade in downloads: you hand a tool a file and it hands
one back. That works, but on a phone it means every save trips through the
Downloads folder and back again. This app edits the mod where it sits.

## What it does

| | |
|---|---|
| **Chart editor** | The scrolling grid, playing against the song's own audio. Tap to place a note or take it away, long-press and drag to pull a hold out of one, pinch to zoom, drag to scrub. Snap from quarter notes down to 1/48, undo and redo, difficulties and variations, and the song's events on the left. |
| **Metadata editor** | Name, artist, charter, stage, note style, characters, difficulties, offsets, and a proper editor for the tempo map rather than one BPM box. |
| **Character editor** | Plays an animation off the character's own sparrow sheet and lets you drag it until the offsets line up. Animations whose prefix is missing from the sheet are marked, because that is why one plays nothing. |

## Running it

```sh
cd mobile
flutter pub get
flutter run            # a device or emulator
flutter test           # no device needed
flutter analyze
```

Debug builds are fine for using it. `flutter build apk --release` makes
something installable.

**Android only for now.** There is no iOS target in the tree, deliberately:
the folder access below is the Storage Access Framework, which iOS does not
have, so an iOS build would come up and then be unable to open anything. Adding
one means writing the document-picker half of `StorageBackend` first, and then
`flutter create --platforms=ios .` here.

## How files work

Since Android 11 an app cannot read a folder on shared storage by path,
however plainly the path is written on screen. What it can do is ask once and
be handed a grant on that folder, and that is what happens the first time you
open the app: you point it at your mod, and it keeps the grant across reboots
so it never asks again.

Everything under that folder is then addressed by document URI rather than by
path. Those are not paths — you cannot append a name to one and get its child —
so `services/storage/` is the only part of the app that knows the difference:

- `saf_backend.dart` and `android/…/SafBridge.kt` are the two halves of the
  Storage Access Framework bridge, written here rather than pulled in, so that
  the one piece everything else depends on is not a package that stops being
  maintained.
- `io_backend.dart` is ordinary files, for the tests and for a desktop run.

`workspace.dart` is what sits on top: it walks the folder looking for
`data/songs`, `data/characters` and `songs`, which is a mod's layout and also
the game's own — the game keeps its data a level down inside `preload/`, so the
search takes one more look before giving up.

## Saving other people's files

A chart on someone's phone may have been written by a newer game build than
this app knows about. If it parsed only the fields it recognises and wrote back
only those, opening a song and saving it would quietly delete the rest.

So every model keeps the keys it did not claim and folds them back in on write,
and a field the file left out is not invented on the way back — a song that
never set `looped` still does not have it afterwards. The round-trip tests in
`test/chart_io_test.dart` are what hold that up; they encode a real chart and a
real metadata file and check the output matches the input byte for byte.

Numbers go back the way they came, too. Writing `600.0` where the file said
`600` would turn a one-note edit into a diff against every line of the chart.

## Timing

`services/conductor.dart` is the one place that converts song time into musical
time. A song can change tempo partway through, so neither direction is a single
multiplication — both walk to the segment covering the value and measure from
there. Everything the grid draws comes through it, which is why it has the most
tests of anything here.

## Layout

```
lib/
  data/          the file formats: metadata, chart, character
  services/      storage, workspace, audio, conductor
  editors/       chart, metadata, character
  ui/            the hub and the lists
  theme/         colours, carried over from tools/site
```
