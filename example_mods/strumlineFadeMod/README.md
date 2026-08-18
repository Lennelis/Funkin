# Strumline Fade Mod

Fades the opponent's strumline out at a chosen point in a song, holds it there, then
tweens it back to normal opacity.

There are two scripts here, and they work together:

| Script | What it does |
| --- | --- |
| `scripts/StrumlineFadeModule.hxc` | A module that fades strumlines. It fires at hardcoded points in a song (its `fadeCues` list), and exposes functions other scripts can call. |
| `scripts/StrumlineAlphaSongEvent.hxc` | A custom `StrumlineAlpha` chart event, so you can place fades in the chart editor instead of hardcoding them. |

You only need `StrumlineFadeModule.hxc` if you just want a scripted fade. Keep both if
you want to place fades from the chart editor — the event delegates to the module.

## Installing

Copy the `strumlineFadeMod` folder into your game's `mods` folder, then enable it in
the mods menu. If you're running the game from source, it already lives in
`example_mods/`, which the game loads directly in debug builds.

## Setting up a fade

Open `scripts/StrumlineFadeModule.hxc` and edit the `fadeCues` list at the top:

```haxe
var fadeCues:Array<Dynamic> = [
  {
    song: 'bopeebo',      // The song ID, i.e. the folder name under `data/songs/`.
    difficulties: null,   // Only fire on these difficulties, e.g. ['hard'], or null for all.
    strumline: 'opponent',// 'opponent', 'player' or 'both'.
    step: 128,            // The step the fade starts on. 16 steps per measure in 4/4.
    targetAlpha: 0.2,     // How see-through the strumline gets. 0.0 is invisible, 1.0 is normal.
    fadeOutSteps: 4,      // How long the fade out takes, in steps.
    holdSteps: 32,        // How long it stays faded. Use -1 to never fade back in on its own.
    fadeInSteps: 8,       // How long the tween back to normal opacity takes, in steps.
    ease: 'quartOut'      // Any function name from FlxEase, or 'linear'.
  }
];
```

Add as many entries as you like — one per fade, and they can target different songs.
Each cue fires once per attempt and resets when you retry the song.

The example above, on `bopeebo`, fades the opponent's strumline down to 20% opacity
over 4 steps starting at step 128 (measure 9), holds it there for 32 steps (2 measures),
then tweens it back to full opacity over 8 steps.

Durations are in **steps**, not seconds, so a fade stays in time with the music even if
the song changes BPM.

## Setting up a fade from the chart editor

With `StrumlineAlphaSongEvent.hxc` installed, a **Strumline Opacity** event shows up in
the chart editor's event list. Place it where the fade should start and fill in the form:

- **Opacity** — the alpha to tween to (0.0 - 1.0).
- **Duration** — how long the tween takes, in steps.
- **Easing Type / Easing Direction** — which `FlxEase` function to use.
- **Target Strumline** — opponent, player or both.
- **Fade Back In → Hold** — how long to stay faded before tweening back, in steps. Leave
  it at `-1` and the strumline stays faded until another event brings it back.
- **Fade Back In → Fade Back In** — how long the tween back to normal opacity takes.

So there are two ways to chart it:

1. **One event.** Set Hold to something other than `-1`, and the event handles the whole
   fade out → hold → fade back in by itself.
2. **Two events.** Leave Hold at `-1`, place one event with Opacity `0.2` where the fade
   starts, and a second one with Opacity `1.0` where the strumline should come back.

## Driving it from your own script

The module is available to any other script through `ModuleHandler`:

```haxe
var fadeModule = ModuleHandler.getModule('StrumlineFadeModule');

// Fade out, hold, then tween back to normal opacity.
fadeModule.fadeStrumline('opponent', 0.2, 4, 32, 8, 'quartOut');

// Or tween to an opacity and stay there.
fadeModule.tweenStrumlineAlpha('opponent', 0.2, 4, 'quartOut');
fadeModule.tweenStrumlineAlpha('opponent', 1.0, 8, 'quartOut');
```

## Notes

- Setting `alpha` on a `Strumline` fades the whole group: the arrows, the notes on it,
  the hold notes and the strumline background (which is also scaled by the player's
  Strumline Background Opacity preference).
- A couple of spots in the base game assign a note's alpha directly — a hit note that
  stays on screen is set to `0.5`, and a hold note is set to `1.0` when it's rendered.
  Those individual notes ignore the fade until they're recycled. If that's noticeable
  in your chart, fade to a lower opacity or fade during a section with fewer notes.
- The module pauses its tweens when the game is paused and cleans them up when the song
  ends, is retried or when modules are reloaded, so a fade can't leak into the next song.
- Scripts run through Polymod's hscript, so you can edit them and press `F5` in game to
  reload without restarting.
