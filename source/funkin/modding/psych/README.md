# Psych Engine mods in V-Slice

Psych Engine mods are Lua. V-Slice's modding system is Polymod and HScript. This package
is what lets the first run inside the second.

## The shape of it

V-Slice already dispatches every event a script could want - create, update, beat, step,
note hit, note miss, countdown, pause, song end - from one place, `PlayState.dispatchEvent`,
to every registered module. So the bridge is a module:

```
PlayState.dispatchEvent(event)
  -> ModuleHandler.callEvent(event)
       -> PsychScriptHandler           (this package)
            -> PsychScript.call('onBeatHit', [])
                 -> the mod's Lua
```

Nothing in the game has to learn that Lua exists. `PsychScriptHandler` sits in the same
queue as any other module, at a lower priority number so a Psych script gets to cancel
something before a built-in module acts on it.

| File | What it does |
| --- | --- |
| `PsychScript` | One Lua file and the interpreter running it. Loading, globals, calling a function, reporting an error. |
| `PsychScriptHandler` | The `Module`. Finds the scripts, owns their lifetime, turns V-Slice's events into Psych's callback names. |
| `PsychScriptFinder` | Which files to run, by Psych's folder convention. |
| `PsychGlobals` | The variables a script reads without calling anything - `curBeat`, `score`, `songPos`. |
| `PsychBridge` | `getProperty`/`setProperty` name resolution, and the handful of names V-Slice keeps somewhere else. |
| `PsychApi` | The functions a script can call. |

## Where scripts come from

Psych has no manifest. A file runs because of where it sits, and that convention is the
whole contract:

```
mods/<mod>/scripts/*.lua          every song
mods/<mod>/data/<songId>/*.lua    that song
```

A debug build is the exception, and it catches people out: `-debug` turns on
`REDIRECT_ASSETS_FOLDER`, which moves the mod root to `example_mods/` in the project
folder. This follows `PolymodHandler.MOD_FOLDER` rather than hardcoding `mods`, so it
lands in the same place the rest of the modding system does - but it does mean a mod you
dropped in `mods/` will not be found by a debug build.

Read straight off disk rather than through Polymod. Polymod exists to let one mod's file
replace another's, which is right for images and charts and wrong here - two mods that
both ship `scripts/init.lua` both want theirs to run, and going through the asset layer
would silently drop one.

## What translates, and what doesn't

Most of it needs no translation: both engines are FlxSprites underneath, so a sprite's
`x` is a sprite's `x`, and `setProperty('boyfriend.x', 100)` means the same thing on both
sides once `boyfriend` resolves.

The differences worth knowing:

- **Characters live on the stage here**, not on PlayState. `boyfriend`, `dad` and `gf`
  are mapped to `currentStage.getBoyfriend()` and friends.
- **The Conductor is an object**, not a class of statics. `getPropertyFromClass('backend.Conductor', 'songPosition')`
  is pointed at `Conductor.instance` so the same call works unchanged.
- **`camOther` is the cutscene camera.** Psych's third camera is for things drawn over
  everything, which is the job V-Slice gives `camCutscene`.
- **Sections are counted, not stored.** Psych sections are four beats; V-Slice has
  measures. `curSection` and `onSectionHit` are derived from the beat, which is the same
  thing for any chart in four-four - which every chart converted from Psych is.
- **A note's side comes from the chart, not the sprite.** Note data 0-3 is the player in
  Psych and strumline index 0 in V-Slice, and the same arithmetic gets you there from
  either, so `goodNoteHit` and `opponentNoteHit` are decided by `getMustHitNote()`.
- **Note ids are strum times.** Psych passes the note's index in `PlayState.notes`, which
  has no counterpart here. Mods use it as a handle to pass back, so the strum time stands
  in: unique per note and, unlike an index, stable.

## What is not here yet

This is a first slice, not the whole API. Ported so far: properties (including class and
group properties), the script variable bag, sprite creation and animation, adding and
removing sprites, object cameras, camera flash/fade/shake, and timers.

Not yet ported, in rough order of how much mods want them: tweens (`startTween`,
`doTweenX` and the rest), sound (`playSound`, `playMusic`, `precacheSound`), text
objects, shaders, `triggerEvent`, dialogue, save data, and the HScript half of Psych's
scripting. A script calling one of these gets a Lua error naming the function, which is
at least obvious rather than mysterious.

`FEATURE_PSYCH_LUA` is off on HTML5: LuaJIT is a C library and there is nothing to link
against there. A browser build still loads a Psych mod's images and charts - it just
cannot run the scripts.
