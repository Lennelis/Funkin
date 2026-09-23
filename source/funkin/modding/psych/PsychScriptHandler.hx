package funkin.modding.psych;

#if FEATURE_PSYCH_LUA
import funkin.modding.events.ScriptEvent;
import funkin.modding.module.Module;
import funkin.play.PlayState;

/**
 * Runs Psych Engine's Lua scripts inside V-Slice.
 *
 * This is a `Module`, which is the whole trick. V-Slice already dispatches every event a
 * script could want - create, update, beat, step, note hit, note miss, countdown, pause,
 * song end - to every registered module, from one place in `PlayState.dispatchEvent`. So
 * nothing in the game has to learn about Lua; this sits in the same queue as any other
 * module and translates what arrives into the names Psych mods are written against.
 *
 * Psych's callback names and their arguments are the contract here, not V-Slice's. A mod
 * written years ago against `goodNoteHit(id, noteData, noteType, isSustainNote)` has to
 * keep working, so that signature is what gets called, whatever the event is called on
 * this side.
 */
class PsychScriptHandler extends Module
{
  /**
   * The id this registers under. `ModuleHandler` keys its cache by this.
   */
  public static inline var MODULE_ID:String = 'funkin.psych.lua';

  /**
   * Psych scripts run before V-Slice's own modules so a mod can cancel something that a
   * built-in module would otherwise have acted on first.
   */
  static inline var PRIORITY:Int = 100;

  static var scripts:Array<PsychScript> = [];

  /**
   * The PlayState the loaded scripts belong to.
   *
   * Scripts are per-song, and a retry builds a fresh `PlayState`. Comparing the instance
   * is how this notices, rather than comparing song ids - restarting the same song is
   * exactly the case a song id would miss.
   */
  static var loadedFor:Null<PlayState> = null;

  static var errors:Array<String> = [];

  public function new()
  {
    super(MODULE_ID, PRIORITY);
  }

  /**
   * Whether any Psych script is currently loaded.
   */
  public static function isActive():Bool
  {
    return scripts.length > 0;
  }

  /**
   * Called by `PsychScript` when a script misbehaves.
   */
  public static function reportError(message:String):Void
  {
    errors.push(message);
  }

  /**
   * Errors raised since the last time they were taken, emptying the list.
   * Whatever is drawing them on screen is the one thing that should call this.
   */
  public static function takeErrors():Array<String>
  {
    var taken:Array<String> = errors;
    errors = [];
    return taken;
  }

  //
  // SCRIPT LIFECYCLE
  //

  static function load():Void
  {
    unload();

    var game:Null<PlayState> = PlayState.instance;
    if (game == null) return;

    loadedFor = game;

    for (path in PsychScriptFinder.findForSong(songId()))
    {
      var script:PsychScript = new PsychScript(path, PsychScriptFinder.modOf(path));
      if (script.load()) scripts.push(script);
    }

    if (scripts.length == 0) return;

    trace('[PSYCHLUA] Loaded ${scripts.length} script(s) for ${songId()}');

    // Psych fires both of these during its own create, one after the stage and characters
    // exist. By the time a module hears about the song the state is already built, so
    // they land together - a script that split work across the two still sees them in
    // the right order.
    callOnScripts('onCreate', []);
    callOnScripts('onCreatePost', []);
  }

  static function unload():Void
  {
    for (script in scripts)
      script.stop();

    scripts = [];
    loadedFor = null;

    // The objects and variables belonged to those scripts; nothing else can reach them
    // now, and leaving them would let the next song see the last one's sprites.
    PsychBridge.reset();
  }

  static function songId():String
  {
    var game:Null<PlayState> = PlayState.instance;
    if (game == null || game.currentChart == null) return '';

    return game.currentChart.song.id;
  }

  /**
   * Calls a Psych callback on every loaded script.
   * @return Whether a script asked for the thing that triggered this not to happen.
   */
  public static function callOnScripts(name:String, args:Array<Dynamic>):Bool
  {
    var stopped:Bool = false;

    for (script in scripts)
    {
      if (script.closed) continue;

      var result:Dynamic = script.call(name, args);

      if (result == PsychScript.STOP || result == PsychScript.STOP_ALL || result == PsychScript.STOP_LUA) stopped = true;
    }

    return stopped;
  }

  //
  // EVENT TRANSLATION
  //

  override public function onScriptEvent(event:ScriptEvent):Void
  {
    // The globals a Psych script reads without asking - curStep, score, and so on - are
    // just Lua globals, so they have to be pushed rather than fetched. Refreshing them
    // before every callback is what makes them true whenever a script looks.
    if (scripts.length > 0) PsychGlobals.refresh(scripts);
  }

  override public function onSongLoaded(event:SongLoadScriptEvent):Void
  {
    // The first point at which the chart, the stage and the characters all exist.
    if (PlayState.instance != loadedFor) load();
  }

  override public function onDestroy(event:ScriptEvent):Void
  {
    if (scripts.length == 0) return;

    callOnScripts('onDestroy', []);
    unload();
  }

  override public function onUpdate(event:UpdateScriptEvent):Void
  {
    if (scripts.length == 0) return;

    // A state that has gone away without a DESTROY reaching us would otherwise leave the
    // scripts running against nothing.
    if (PlayState.instance != loadedFor)
    {
      unload();
      return;
    }

    callOnScripts('onUpdate', [event.elapsed]);
    callOnScripts('onUpdatePost', [event.elapsed]);
  }

  override public function onStepHit(event:SongTimeScriptEvent):Void
  {
    if (scripts.length == 0) return;

    callOnScripts('onStepHit', []);
  }

  override public function onBeatHit(event:SongTimeScriptEvent):Void
  {
    if (scripts.length == 0) return;

    callOnScripts('onBeatHit', []);

    // Psych's sections are four beats. V-Slice has measures, but a chart converted from
    // Psych keeps four-four throughout, so counting beats is both simpler and truer to
    // what the script expects.
    if (event.beat % 4 == 0) callOnScripts('onSectionHit', []);
  }

  override public function onSongStart(event:ScriptEvent):Void
  {
    if (scripts.length == 0) return;

    callOnScripts('onSongStart', []);
  }

  override public function onSongEnd(event:ScriptEvent):Void
  {
    if (scripts.length == 0) return;

    callOnScripts('onEndSong', []);
  }

  override public function onNoteHit(event:HitNoteScriptEvent):Void
  {
    if (scripts.length == 0 || event.note == null) return;

    var data:Null<funkin.data.song.SongData.SongNoteData> = event.note.noteData;
    if (data == null) return;

    // Psych hands the script the note's index in PlayState.notes, which nothing here
    // keeps. Its actual use in mods is as a handle to pass back to note functions, so
    // the strum time stands in - unique per note and, unlike an index, stable.
    var id:Float = data.time;
    var direction:Int = event.note.direction;
    var kind:String = data.kind == null ? '' : data.kind;

    // Which side the note is on is the difference between the two callbacks. Asked of the
    // chart data rather than of the sprite, because that is where both engines agree:
    // note data 0-3 is the player in Psych and strumline index 0 in V-Slice, and the
    // same arithmetic gets you there from either.
    if (data.getMustHitNote()) callOnScripts('goodNoteHit', [id, direction, kind, false]);
    else
      callOnScripts('opponentNoteHit', [id, direction, kind, false]);
  }

  override public function onNoteMiss(event:NoteScriptEvent):Void
  {
    if (scripts.length == 0 || event.note == null) return;

    var data:Null<funkin.data.song.SongData.SongNoteData> = event.note.noteData;
    if (data == null) return;

    callOnScripts('noteMiss', [data.time, event.note.direction, data.kind == null ? '' : data.kind, false]);
  }

  override public function onNoteGhostMiss(event:GhostMissNoteScriptEvent):Void
  {
    if (scripts.length == 0) return;

    callOnScripts('noteMissPress', [event.dir]);
  }

  override public function onSongEvent(event:SongEventScriptEvent):Void
  {
    if (scripts.length == 0 || event.eventData == null) return;

    var data = event.eventData;

    // Psych events carry two loose values; V-Slice's carry a named object. Mods index
    // value1/value2 positionally, so the object's fields are handed over in the order
    // they were written, which for a converted chart is the order Psych had them in.
    var values:Array<Dynamic> = [];
    if (data.value != null)
    {
      for (field in Reflect.fields(data.value))
        values.push(Reflect.field(data.value, field));
    }

    callOnScripts('onEvent', [data.eventKind, values[0], values[1], data.time]);
  }

  override public function onCountdownStart(event:CountdownScriptEvent):Void
  {
    if (scripts.length == 0) return;

    callOnScripts('onCountdownStarted', []);
  }

  override public function onCountdownStep(event:CountdownScriptEvent):Void
  {
    if (scripts.length == 0) return;

    callOnScripts('onCountdownTick', [countdownIndex(event.step)]);
  }

  override public function onPause(event:PauseScriptEvent):Void
  {
    if (scripts.length == 0) return;

    callOnScripts('onPause', []);
  }

  override public function onResume(event:ScriptEvent):Void
  {
    if (scripts.length == 0) return;

    callOnScripts('onResume', []);
  }

  override public function onGameOver(event:ScriptEvent):Void
  {
    if (scripts.length == 0) return;

    callOnScripts('onGameOver', []);
  }

  override public function onFocusLost(event:FocusScriptEvent):Void
  {
    if (scripts.length == 0) return;

    callOnScripts('onFocusLost', []);
  }

  override public function onFocusGained(event:FocusScriptEvent):Void
  {
    if (scripts.length == 0) return;

    callOnScripts('onFocus', []);
  }

  //
  // HELPERS
  //

  /**
   * Psych counts the countdown down - 3, 2, 1, Go - as 0 through 3.
   */
  static function countdownIndex(step:funkin.play.Countdown.CountdownStep):Int
  {
    return switch (step)
    {
      case THREE: 0;
      case TWO: 1;
      case ONE: 2;
      case GO: 3;
      default: -1;
    }
  }
}
#end
