# Pico Singer Mod

Adds Pico to the stage as a second singer. Notes you mark with the `pico` note kind
in the chart editor are sung by him instead of by Boyfriend or Dad.

| Script | What it does |
| --- | --- |
| `scripts/PicoSingerModule.hxc` | Adds Pico to the stage, positions him, and holds his sing animation through sustains. |
| `scripts/PicoSingerNoteKind.hxc` | The `pico` note kind. Suppresses the usual singer's animation and hands the note to the module. |

Both are needed — the note kind talks to the module through `ModuleHandler`.

## Charting

Open a chart, select a note, and set its **kind** to `pico` ("Pico Sings" in the list).
That's it: the note scores and plays exactly as before, but the side's usual character
stays idle while Pico sings it. It works on player notes and opponent notes alike.

Pico only appears in songs whose chart contains at least one `pico` note, so the mod
does nothing to every other song.

## Tuning

At the top of `PicoSingerModule.hxc`:

- `CHARACTER_IDS` — character IDs to try, in order, first match wins. Defaults to
  `pico-player` (the playable Pico). If none of them exist you'll get a
  `[PicoSinger] No Pico character found` line in the log with the IDs it tried —
  check the folder names in `data/characters/` and add yours to the front of the list.
- `X_OFFSET` / `Y_OFFSET` — where he stands, relative to Boyfriend.
- `SCALE` — multiplier on his own base scale.
- `NOTE_KIND` — must match the ID in `PicoSingerNoteKind.hxc`.

## How it works

The engine decides who sings in `BaseCharacter.onNoteHit`: a character sings only if
its `characterType` is `BF` and the note is a player note, or `DAD` and it isn't. That
hardcoding is why a side normally has exactly one singer.

Two things get around it:

- `NoteKind.noanim` makes the usual singer skip a note. That frees the note up.
- `Stage.addCharacter` has a fallback branch that stores any character under its own
  ID, and `dispatchToCharacters` already loops "the rest of the characters, if any".
  Pico goes in as `CharacterType.OTHER`, which idles and dances but never sings by
  itself — so the script has full control over when he does.

## Notes

- Sustains: non-BF characters drop back to idle after about a beat of singing, so the
  module pins `holdTimer` to zero for the length of a sustain to hold the animation.
- Vocals are mixed per *side*, not per character (`playerVolume` / `opponentVolume`
  cover every voice on that side), so Pico won't mute independently on a miss. If you
  want a separate stem for him, add his ID to `playerVocals` / `opponentVocals` in the
  song metadata and ship a matching `Voices-<id>.ogg`.
- The health icon still belongs to the side's main character. Swapping it when Pico
  sings is a couple of lines on `iconP1` / `iconP2` if you want it.
- If the song's player character is already Pico (a Pico mix), you'll get two of him.
  Point `CHARACTER_IDS` at a different character for those charts.
