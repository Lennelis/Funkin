package funkin.ui.debug;

import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.addons.transition.FlxTransitionableState;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.audio.FunkinSound;
import funkin.ui.FullScreenScaleMode;
import funkin.ui.MusicBeatState;
import funkin.ui.TextMenuList;

/**
 * The first screen of the game when it is built as an editor app.
 *
 * `DebugMenuSubState` already lists the editors, but it is a substate reached
 * from the main menu of a game — it assumes there is something to go back to.
 * When the editors are the app, they need a screen of their own that is the
 * root rather than a detour, which is what this is.
 *
 * The game is still in here; it is reachable from the last item, so a chart
 * can be played rather than only looked at.
 */
class EditorHubState extends MusicBeatState
{
  var items:TextMenuList;

  /**
   * What the camera follows, so the list can scroll past the bottom of the
   * screen the way the debug menu's does.
   */
  var camFocusPoint:FlxObject;

  /**
   * Says which editor is opening.
   *
   * On a phone there is no console to watch, so when an editor does not come
   * up there is no way to tell whether the menu never fired or the editor
   * failed on its way in. This distinguishes the two: if this appears and
   * nothing follows, the editor is what went wrong.
   */
  var status:FlxText;

  /**
   * What to open once the status text has had a frame to draw.
   */
  var pending:Null<Void->Void> = null;

  var pendingFrames:Int = 0;

  override function create():Void
  {
    FlxTransitionableState.skipNextTransIn = true;
    super.create();

    camFocusPoint = new FlxObject(0, 0);
    add(camFocusPoint);

    FlxG.camera.follow(camFocusPoint, null, 0.06);

    var menuBG = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
    menuBG.color = 0xFF4CAF50;
    menuBG.setGraphicSize(Std.int(menuBG.width * 1.1 * FullScreenScaleMode.wideScale.x));
    menuBG.updateHitbox();
    menuBG.screenCenter();
    menuBG.scrollFactor.set(0, 0);
    add(menuBG);

    items = new TextMenuList();
    items.onChange.add(onMenuChange);
    add(items);

    #if FEATURE_CHART_EDITOR
    createItem("CHART EDITOR", openChartEditor);
    #end
    #if FEATURE_STAGE_EDITOR
    createItem("STAGE EDITOR", openStageEditor);
    #end
    #if FEATURE_ANIMATION_EDITOR
    createItem("ANIMATION EDITOR", openAnimationEditor);
    #end
    createItem("PLAY A SONG", openFreeplay);

    #if mobile
    // Not decoration. MenuList tests a tap against the second camera, and
    // that camera only exists once one of the mobile controls has been added,
    // so without this nothing on this screen answers a touch at all.
    //
    // Back leaves the editors for the game, which is still in this build.
    addBackButton(FlxG.width - 230, FlxG.height - 200, FlxColor.WHITE, goBack, 1.0);
    #end

    // Every editor is behind a feature flag, so a build with all of them off
    // would leave nothing to focus the camera on.
    if (items.members.length > 0)
    {
      onMenuChange(items.members[0]);
      FlxG.camera.focusOn(new FlxPoint(camFocusPoint.x, camFocusPoint.y + 500));
    }

    status = new FlxText(0, FlxG.height - 90, FlxG.width, "");
    status.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
    status.scrollFactor.set(0, 0);
    status.visible = false;
    add(status);

    #if FEATURE_HAXEUI
    // The same reason the debug menu does this: a stylesheet left over from
    // elsewhere makes the editors' own components come up wrong.
    haxe.ui.Toolkit.styleSheet.clear("user");
    #end
  }

  /**
   * Show what is happening, then do it a frame later so the text is on screen
   * before the editor takes over.
   */
  function open(what:String, action:Void->Void):Void
  {
    status.text = 'Opening $what...';
    status.visible = true;

    pending = action;
    pendingFrames = 2;
  }

  override function update(elapsed:Float):Void
  {
    super.update(elapsed);

    if (pending != null)
    {
      pendingFrames--;

      if (pendingFrames <= 0)
      {
        var action = pending;
        pending = null;
        action();
      }
    }
  }

  function onMenuChange(selected:TextMenuItem):Void
  {
    camFocusPoint.setPosition(selected.x + selected.width / 2, selected.y + selected.height / 2);
  }

  function createItem(name:String, callback:Void->Void, fireInstantly = false):TextMenuItem
  {
    var item = items.createItem(0, 100 + items.length * 100, name, BOLD, callback);
    item.fireInstantly = fireInstantly;
    item.screenCenter(X);
    return item;
  }

  #if FEATURE_CHART_EDITOR
  function openChartEditor():Void
  {
    open('the chart editor', () -> {
      FlxTransitionableState.skipNextTransIn = true;
      switchToChartEditor();
    });
  }

  function switchToChartEditor():Void
  {
    FlxG.switchState(() -> new funkin.ui.debug.charting.ChartEditorState());
  }
  #end

  #if FEATURE_STAGE_EDITOR
  function openStageEditor():Void
  {
    open('the stage editor', () -> {
      FlxTransitionableState.skipNextTransIn = true;
      switchToStageEditor();
    });
  }

  function switchToStageEditor():Void
  {
    FlxG.switchState(() -> new funkin.ui.debug.stageeditor.StageEditorState());
  }
  #end

  #if FEATURE_ANIMATION_EDITOR
  function openAnimationEditor():Void
  {
    open('the animation editor', () -> {
      FlxTransitionableState.skipNextTransIn = true;
      switchToAnimationEditor();
    });
  }

  function switchToAnimationEditor():Void
  {
    FlxG.switchState(() -> new funkin.ui.debug.anim.DebugBoundingState());
  }
  #end

  #if mobile
  function goBack():Void
  {
    FlxG.switchState(() -> new funkin.ui.title.TitleState());
  }
  #end

  function openFreeplay():Void
  {
    FunkinSound.playOnce(Paths.sound('confirmMenu'));
    open('freeplay', () -> FlxG.switchState(() -> new funkin.ui.freeplay.FreeplayState()));
  }
}
