# Bad Apple Mod

Blacks out the stage and turns every character into a solid colored silhouette,
triggered from the chart.

| Script | What it does |
| --- | --- |
| `scripts/BadAppleModule.hxc` | The effect itself. Shades the characters, tints the stage, and puts everything back. |
| `scripts/BadAppleSongEvent.hxc` | A `BadApple` chart event, so you can turn it on and off at points in a song. |
| `scripts/DadBattleBadAppleTest.hxc` | A test script: fires the effect at the start of Dad Battle with a different color per character. Delete it when you're done. |

## Charting

Place a **Bad Apple** event where the effect should start:

- **Enabled** — on or off. Place a second event with this unchecked to go back to normal.
- **Silhouette Color** — white, black, red, green, blue, yellow, cyan or magenta.
- **Fade Duration** — how long the stage takes to fade to black, in steps. `0` snaps instantly.

## From a script

```haxe
var badApple = ModuleHandler.getModule('BadAppleModule');

badApple.setBadApple(true, 0xFFFFFFFF, 0.5);  // silhouettes
badApple.setBadApple(false, 0xFFFFFFFF, 0.5); // back to normal
```

Colors are `0xAARRGGBB`, so keep the `FF` on the front.

## How it works

- **Characters** get `funkin.graphics.shaders.PureColor`, a shader the base game already
  ships. It replaces every pixel that isn't transparent with a flat color and keeps the
  alpha, so you get the character's exact outline, animating as normal, in one solid color.
  The character's previous shader is stored and restored afterwards.
- **The stage** isn't hidden, it's tinted: every non-character member of the stage has its
  `color` tweened to black, and the game camera's background color goes black underneath.
  Tinting rather than hiding means the effect can fade, and means nothing has to know
  which props were visible in the first place.

## Per-character colors

`setBadApple` gives everyone the same color, but the shader it installs is exposed, so
you can repoint any character at another color afterwards:

```haxe
PlayState.instance.currentStage.getDad().shader.col = 0xFFC3A6FF;
```

`DadBattleBadAppleTest.hxc` does exactly this for all three characters.

## Notes

- Stages are cached and reused between songs, so the module puts every prop back on song
  end, retry, game over and script reload. Without that, a blacked-out prop would follow
  you into the next song.
- The HUD, notes and strumlines are untouched — they're on a different camera. If you want
  those to go dark too, that's a separate change on `camHUD`.
- Girlfriend counts as a character, so she silhouettes along with everyone else.
- Anything a stage script animates by setting `color` directly will fight the tint. None
  of the base game stages do this.
