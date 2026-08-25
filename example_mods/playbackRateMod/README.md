# Playback Rate Mod

Adds a playback rate selector to Freeplay, under the difficulty. Whatever you pick
applies to every song until you change it.

| Script | What it does |
| --- | --- |
| `scripts/FreeplayRateSelector.hxc` | The Freeplay control. Writes the rate to the save file. |
| `scripts/PlaybackRateModule.hxc` | Reads it when a song starts and applies it. |

## Using it

In Freeplay, under the difficulty, you'll see `<  RATE 1.00x  >`.

- **Tap the left half** to slow down, **the right half** to speed up.
- On a keyboard, **Q** and **E**.
- Steps of 0.05, clamped between 0.5x and 2.0x.

The value is saved immediately, so it survives closing the game.

## Tuning

In `FreeplayRateSelector.hxc`:

- `STEP` — how much one tap changes the rate. Default `0.05`.
- `MIN_RATE` / `MAX_RATE` — the clamp. Also set in the module.
- `X_OFFSET` / `Y_OFFSET` — where it sits relative to the difficulty. Default is 115px below.
- `TAP_PADDING` — how much extra room around the text counts as a tap. Default 24px.
- `FONT_SIZE` — text size.

In `PlaybackRateModule.hxc`:

- `SCALE_ANIMATIONS` — also speed up animations, tweens and timers to match. On by default.
- `INVALIDATE_SCORE` — keep modified runs out of your high scores. On by default.
- `FALLBACK_RATE` — used before anything has been chosen in Freeplay.

Both scripts share `SAVE_KEY`; change it in both or neither.

## How it works

The rate is applied as **pitch** on the instrumental and the vocals, exactly like the
chart editor's playback speed control. `Conductor.update()` reads its position from
`FlxG.sound.music.time`, so a track playing at 1.5x advances the song position 1.5x as
fast, and notes, song events and beat hits all follow without any extra work.

The Freeplay control is an `FlxText` (plus a second one behind it as a drop shadow) added
to the Freeplay substate on its `funnyCam`. It repositions every frame from
`grpDifficulties`, so it slides in with the difficulty during the intro animation instead
of popping into place.

## Notes

- **Pitch, not time-stretch.** Faster means higher pitched, like a tape sped up. There's
  no pitch-preserving resampling in the engine, so chipmunk voices at 1.5x are expected.
- **Hit windows are unchanged in song time**, so they're narrower in real time. 1.5x is a
  much bigger jump than it sounds.
- **Scores are invalidated** while the rate isn't 1.0, using the same `validScore` flag the
  chart editor uses for test runs.
- `FlxG.timeScale` is global, so the module resets it on song end, game over, leaving the
  song and script reload. If the menus ever run fast, that reset is what to look at.
- The tap area sits above Freeplay's DJ hitbox, so it shouldn't steal taps from anything
  else. If it ever does, shrink `TAP_PADDING`.
