# Character Editor

A character editor that runs entirely from mod scripts. Opens from **Options → CHARACTER
EDITOR**, works on touch, and edits every field in the character JSON.

| Script | What it does |
| --- | --- |
| `scripts/CharacterEditorState.hxc` | The editor itself, a scripted `MusicBeatState`. |
| `scripts/CharacterEditorOptions.hxc` | Adds the Options menu entry that opens it. |
| `scripts/CharacterOverridesModule.hxc` | Applies saved edits at startup, so they show up in gameplay. |

## Using it

Options → **CHARACTER EDITOR**.

- **< CHARACTER / CHARACTER >** — walk through every character the game knows about,
  including modded ones.
- **< ANIM / ANIM > / REPLAY** — pick and replay an animation.
- **The d-pad** — move the selected animation's offsets. **STEP** toggles 1px and 10px.
  The preview updates immediately.
- **The property list on the right** — every field in the character JSON, one per row.
  `<` and `>` change the value. Dimmed rows are text fields, which are read-only here
  (see below).
- **LIST UP / LIST DOWN** — page through the properties.
- **ZOOM +/-/1** — camera zoom on the preview.
- **SAVE** — writes the character's whole JSON into the save file. Applies from the next
  launch onward, to gameplay and to Freeplay.
- **EXPORT** — additionally tries to write a real `.json` into
  `mods/characterEditorOutput/data/characters/`.
- **REVERT** — back to the data as it was when you opened the character. SAVE afterwards
  to keep the revert.
- **EXIT** — back to the main menu.

## What it edits

Everything in the character schema: `renderType`, `scale`, `isPixel`, `flipX`,
`danceEvery`, `singTime`, `offsets`, `cameraOffsets`, the whole `healthIcon` block
(creating it if the character has none), and per animation: `frameRate`, `looped`,
`flipX` and `offsets`.

**Text fields are read-only** — `name`, `assetPath`, `startingAnimation` and animation
`prefix`. There's no text input in the engine's UI toolkit that works with a phone's
soft keyboard, so rather than ship a half-working keyboard these are displayed but not
editable. Use EXPORT and edit those few fields in a text editor. A future version could
let you pick animation prefixes from the loaded atlas rather than typing them.

## How it works

`CharacterDataParser.fetchCharacterData(id)` hands back the *cached* data object that
every character is built from. The editor mutates that object directly, then rebuilds the
preview with `fetchCharacter(id)` — so what you see is exactly what the game will do.

Saving stores the whole data object as JSON in `Save.instance.modOptions`, rather than
writing a file. The character cache is loaded at `InitState:304` and modules are created
at `:310`, so `CharacterOverridesModule.onCreate` is early enough to copy saved values
back onto the cached data before anything builds a character. That's why edits work on
mobile, where the mods folder isn't writable from inside the app.

Rebuilds are batched behind a 0.35s timer, so holding down `>` on `scale` doesn't rebuild
the sprite on every tap.

## Notes

- Edits are global: they apply to that character everywhere, in every song.
- To undo everything for a character, open it, press REVERT then SAVE. To wipe all edits,
  clear the `CharEdit:` entries from your save.
- EXPORT depends on `FileUtil.gameDirectory`, which resolves from the executable's
  location. On Android that isn't where mods live, so export may fail there — the status
  line will say so, and SAVE still works.
- The editor loads the *saved* version of a character when you open it, so your edits are
  where you left them.
