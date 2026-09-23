package funkin.modding.psych;

#if FEATURE_PSYCH_LUA
import funkin.Conductor;
import funkin.Highscore;
import funkin.play.Countdown;
import funkin.play.Countdown.CountdownStep;
import funkin.play.GameOverSubState;
import funkin.play.PlayState;

/**
 * The variables a Psych script expects to find already sitting there.
 *
 * Psych mods read `curBeat` or `score` as bare globals, without calling anything. Lua has
 * no way to compute a global on read, so they have to be written into the state before a
 * script gets a chance to look - which means before every callback, since any of them
 * might.
 *
 * That sounds expensive and isn't: this is a few dozen assignments against a table, once
 * per event, and the alternative is mods silently reading stale numbers. Psych does the
 * same thing for the same reason.
 */
class PsychGlobals
{
  /**
   * Pushes the current state of the game into every script.
   */
  public static function refresh(scripts:Array<PsychScript>):Void
  {
    if (scripts.length == 0) return;

    var game:Null<PlayState> = PlayState.instance;
    var conductor:Null<Conductor> = Conductor.instance;

    for (script in scripts)
    {
      if (script.closed) continue;

      script.set('screenWidth', FlxG.width);
      script.set('screenHeight', FlxG.height);
      script.set('buildTarget', buildTarget());
      script.set('version', Constants.VERSION);

      if (conductor != null)
      {
        script.set('curBpm', conductor.bpm);
        script.set('bpm', conductor.bpm);
        script.set('crochet', conductor.beatLengthMs);
        script.set('stepCrochet', conductor.stepLengthMs);
        script.set('songPos', conductor.songPosition);
        script.set('curStep', conductor.currentStep);
        script.set('curBeat', conductor.currentBeat);
        script.set('curDecStep', conductor.currentStepTime);
        script.set('curDecBeat', conductor.currentBeatTime);

        // Psych's sections are four beats each, and mods index them. V-Slice counts
        // measures, which is the same thing for any chart in four-four - which every
        // chart converted from Psych is.
        script.set('curSection', Math.floor(conductor.currentBeat / 4));
      }

      if (game == null) continue;

      script.set('inGameOver', GameOverSubState.instance != null);
      script.set('startedCountdown', Countdown.countdownStep != BEFORE);
      script.set('botPlay', game.isBotPlayMode);
      script.set('practice', game.isPracticeMode);

      script.set('health', game.health);
      script.set('score', Highscore.tallies.score);
      script.set('misses', Highscore.tallies.missed);
      script.set('hits', Highscore.tallies.totalNotesHit);
      script.set('combo', Highscore.tallies.combo);

      script.set('cameraZoom', game.camGame == null ? 1 : game.camGame.zoom);
      script.set('hudZoom', game.camHUD == null ? 1 : game.camHUD.zoom);
      script.set('defaultCameraZoom', game.currentCameraZoom);

      var chart = game.currentChart;
      if (chart != null)
      {
        script.set('songName', chart.songName);
        script.set('songPath', chart.song.id);
        script.set('difficultyName', chart.difficulty);
        script.set('scrollSpeed', chart.scrollSpeed);
      }
    }
  }

  /**
   * What Psych calls the platform. Mods branch on this to skip things a phone can't do.
   */
  static function buildTarget():String
  {
    #if windows
    return 'windows';
    #elseif linux
    return 'linux';
    #elseif mac
    return 'mac';
    #elseif android
    return 'android';
    #elseif ios
    return 'ios';
    #elseif html5
    return 'browser';
    #else
    return 'unknown';
    #end
  }
}
#end
