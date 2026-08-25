# Playback Rate Mod

Plays songs faster or slower — globally, or per song.

`scripts/PlaybackRateModule.hxc` is the whole mod.

## Setting it up

At the top of the script:

- `DEFAULT_RATE` — the rate for every song without an override. `1.0` is normal.
- `SONG_RATES` — per-song overrides:

```haxe
var SONG_RATES:Array<Dynamic> = [
  { song: 'bopeebo', rate: 1.2 },
  { song: 'dadbattle', rate: 1.5 }
];
```

- `MIN_RATE` / `MAX_RATE` — clamp, defaults 0.5 and 2.0.
- `SCALE_ANIMATIONS` — also speed up animations, tweens and timers to match. On by default.
- `INVALIDATE_SCORE` — keep modified runs out of your high scores. On by default.

From another script:

```haxe
ModuleHandler.getModule('PlaybackRateModule').setRate(1.5);
```

## How it works

The rate is applied as **pitch** on the instrumental and the vocals, exactly like the
chart editor's playback speed control does. `Conductor.update()` reads its position from
`FlxG.sound.music.time`, so a track playing at 1.5x advances the song position 1.5x as
fast, and notes, song events and beat hits all follow without any extra work.

`SCALE_ANIMATIONS` sets `FlxG.timeScale`, which scales the `elapsed` value flixel hands
to everything. Without it the audio speeds up but characters keep singing at normal speed,
which looks wrong at anything above about 1.2x.

## Notes

- **Pitch, not time-stretch.** Faster means higher pitched, like a tape sped up. There's no
  pitch-preserving resampling in the engine, so chipmunk voices at 1.5x are expected.
- **Hit windows are unchanged in song time**, which means they're narrower in real time.
  That's the point of a rate mod, but it does get hard fast — 1.5x is a real jump.
- **Scores are invalidated by default** while the rate isn't 1.0, using the same
  `validScore` flag the chart editor uses for test runs.
- `FlxG.timeScale` is global, so the script resets it on song end, game over, leaving the
  song and script reload. If you ever find the menus running fast, that reset is what to
  look at.
- Calling `setRate` mid-song works, but the pitch change is audible as a jump. It also
  won't retime notes already on screen — they keep travelling at whatever speed the
  Conductor is now advancing at, which is usually what you want.
