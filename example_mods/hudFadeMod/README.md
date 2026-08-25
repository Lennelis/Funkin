# HUD Fade Mod

Adds a **Fade HUD** chart event which fades the HUD in and out.

| Script | What it does |
| --- | --- |
| `scripts/HudFadeModule.hxc` | Owns the fades: runs the tweens, freezes them on pause, restores everything afterwards. |
| `scripts/FadeHudSongEvent.hxc` | The `FadeHUD` chart event. |

## Charting

Place a **Fade HUD** event where the fade should start:

- **Opacity** — what to fade to. `0` is invisible, `1` is normal.
- **Duration** — how long the fade takes, in steps. `0` snaps instantly.
- **Easing Type / Direction** — any function from `FlxEase`.
- **Target** — what to fade:
  - **Whole HUD** — notes, bar, icons and score together, by fading the HUD camera.
  - **Strumlines Only** — the notes and strums, leaving the bar and score up.
  - **Bar & Score Only** — the health bar, icons and score, leaving the notes readable.

Place a second event with Opacity `1` where it should come back.

## From a script

```haxe
var hudFade = ModuleHandler.getModule('HudFadeModule');

hudFade.fadeHud('hud', 0.0, 8, 'quartOut');
hudFade.fadeHud('hud', 1.0, 8, 'quartOut');
```

## Notes

- **Whole HUD** fades `camHUD.alpha`, which is one tween for the entire HUD no matter how
  much is on it. The other two targets tween each object, so mixing targets at the same
  time can double up on the bar and score — pick one at a time.
- On mobile, the touch controls live on their own camera (`camControls`), so they stay
  usable while the HUD is faded out. Fading the HUD does not fade your controls.
- Everything is restored to full opacity on song start, end, retry, game over and script
  reload, so a fade can't leak into the next song or the results screen.
- Tweens are frozen while the game is paused, since nothing pauses them for you.
