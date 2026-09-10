package funkin.ui.debug.charedit;

import flixel.FlxSprite;
import flixel.addons.transition.FlxTransitionableState;
import flixel.math.FlxPoint;
import flixel.util.FlxColor;
import funkin.data.character.CharacterData;
import funkin.data.character.CharacterData.CharacterDataParser;
import funkin.data.stage.StageRegistry;
import funkin.modding.events.ScriptEvent;
import funkin.modding.events.ScriptEventDispatcher;
import funkin.graphics.FunkinCamera;
import funkin.play.character.BaseCharacter;
import funkin.play.character.BaseCharacter.CharacterType;
import funkin.play.stage.Stage;
import funkin.ui.FullScreenScaleMode;
import funkin.ui.MusicBeatState;
import funkin.util.FileUtil;
import funkin.util.SortUtil;
import haxe.ui.RuntimeComponentBuilder;
import haxe.ui.components.Button;
import haxe.ui.components.CheckBox;
import haxe.ui.components.DropDown;
import haxe.ui.components.Label;
import haxe.ui.components.NumberStepper;
import haxe.ui.containers.dialogs.CollapsibleDialog;
import haxe.ui.containers.menus.MenuBar;
import haxe.ui.containers.menus.MenuItem;
import haxe.ui.core.Screen;
import haxe.ui.events.MouseEvent;
import haxe.ui.events.UIEvent;
#if mobile
import funkin.util.TouchUtil;
#end

/**
 * A character editor you can use with your thumbs.
 *
 * The existing one is built for a mouse and a keyboard: offsets are nudged
 * with the arrow keys and saving goes through a desktop file dialog, neither
 * of which exists on a phone, so it opens there and then cannot do either of
 * the two things it is for.
 *
 * This keeps the parts of it that are not about input — the character
 * loading, the animation playback, the offsets living on the sprite — and
 * changes how you reach them. The panel is built the same way the other
 * editors build theirs, from a layout in the assets, so it belongs to the
 * same set; what differs is that the controls are sized for a finger and the
 * character is placed by dragging it rather than by typing numbers.
 */
class CharacterEditorState extends MusicBeatState
{
  /**
   * Where a saved character goes.
   *
   * Writing a mod rather than over the game's own files means an edit is live
   * the next time the game loads, and the original is still there if the edit
   * was a mistake.
   */
  static final MOD_ROOT:String = 'mods';

  static final MOD_ID:String = 'editor';

  /**
   * The stage a character is shown on. The one the game opens on, so what you
   * see here is what most songs will show.
   */
  static final STAGE_ID:String = 'mainStage';

  static final ZOOM_MIN:Float = 0.15;

  static final ZOOM_MAX:Float = 4.0;

  /**
   * The view the character sits in, which moves and zooms under two fingers.
   */
  var camStage:FunkinCamera;

  /**
   * Where the panel lives, so it stays put while the view moves.
   */
  var camUI:FunkinCamera;

  var character:Null<BaseCharacter> = null;

  var data:Null<CharacterData> = null;

  var characterIds:Array<String> = [];

  var characterId:String = '';

  /**
   * The stage the character is stood on.
   *
   * Offsets and scale only mean anything against something, and a character
   * floating on an empty screen gives nothing to judge either by. This is the
   * same stage the game builds, put where the game puts it.
   */
  var stage:Null<Stage> = null;

  /**
   * Which slot on the stage the character is standing in.
   */
  var characterType:CharacterType = BF;

  var animationNames:Array<String> = [];

  var animationName:String = '';

  // -- the panel ----------------------------------------------------------

  var toolbox:Null<CollapsibleDialog> = null;

  var menubar:Null<MenuBar> = null;

  var positionDropdown:Null<DropDown> = null;

  var characterDropdown:Null<DropDown> = null;
  var animationDropdown:Null<DropDown> = null;
  var animationWarning:Null<Label> = null;
  var offsetLabel:Null<Label> = null;
  var statusLabel:Null<Label> = null;
  var scaleStepper:Null<NumberStepper> = null;
  var flipXCheck:Null<CheckBox> = null;
  var singTimeStepper:Null<NumberStepper> = null;
  var danceEveryStepper:Null<NumberStepper> = null;
  var cameraXStepper:Null<NumberStepper> = null;
  var cameraYStepper:Null<NumberStepper> = null;

  /**
   * Set while the panel is being filled in from a character, so that changing
   * a control does not read as the person having changed it.
   */
  var populating:Bool = false;

  // -- gesture state ------------------------------------------------------

  var dragging:Bool = false;

  /**
   * Where the offset would be with the finger at the origin, so a drag turns
   * into an offset without accumulating error.
   */
  var dragAnchor:FlxPoint = new FlxPoint();

  var pinching:Bool = false;

  var lastMid:FlxPoint = new FlxPoint();

  var lastPinchDistance:Float = 0;

  /**
   * Where a press started, so that letting go without having moved can be
   * told apart from a drag. One is asking to see the animation again, the
   * other is placing the character, and they start out identical.
   */
  var pressedAt:FlxPoint = new FlxPoint();

  var pressWasDrag:Bool = false;

  /**
   * How far a finger may wander and still count as a tap.
   */
  static final TAP_SLOP:Float = 14;

  /**
   * How far the panel and the menu bar's contents sit in from the edge.
   *
   * Phone screens are rounded, so the corner pixels are not there to be
   * tapped even though the layout thinks they are. Anything you have to hit
   * starts far enough in to clear the curve. The menu bar carries the same
   * number as padding in its own layout, since it spans the screen.
   */
  static final SCREEN_INSET:Float = 30;

  /**
   * What an open dropdown looks like.
   *
   * On a phone HaxeUI opens a dropdown as a modal in the middle of the
   * screen, which is the right shape for a thumb, but its stylesheet sizes
   * that modal at three quarters of the screen regardless of what is in it.
   * A list of three stage slots then arrives as a panel the width of the
   * phone with three short rows up one side of it. This sizes the modal to
   * the control it belongs to and gives the rows enough height to hit.
   */
  static final POPUP_STYLE:String = '
    .dropdown-popup:mobile { width: 300px; }
    .dropdown-popup .listview .itemrenderer { padding: 12px 10px; }
  ';

  /**
   * The green behind an empty editor.
   *
   * Only up while there is no stage: a character standing on one should look
   * the way it will in the game, and the game has nothing behind its stages.
   */
  var bg:Null<FlxSprite> = null;

  /**
   * How far down the panel has to start to clear the menu bar.
   */
  var menubarHeight:Float = 0;

  override function create():Void
  {
    FlxTransitionableState.skipNextTransIn = true;
    super.create();

    // The same green as the screen this was opened from, so the app reads as
    // one thing rather than as the game with an editor bolted on.
    var backdrop = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
    backdrop.color = 0xFF4CAF50;
    backdrop.setGraphicSize(Std.int(backdrop.width * 1.1 * FullScreenScaleMode.wideScale.x));
    backdrop.updateHitbox();
    backdrop.screenCenter();
    backdrop.scrollFactor.set(0, 0);
    add(backdrop);
    bg = backdrop;

    camStage = new FunkinCamera('camStage');
    camStage.bgColor = 0x0;
    FlxG.cameras.add(camStage, false);

    camUI = new FunkinCamera('camUI');
    camUI.bgColor = 0x0;
    FlxG.cameras.add(camUI, false);

    // Cleared again by the hub on the way back out, the same way the debug
    // menu clears what it adds.
    haxe.ui.Toolkit.styleSheet.parse(POPUP_STYLE, 'user');

    characterIds = CharacterDataParser.listCharacterIds();
    characterIds.sort(SortUtil.alphabetically);

    buildMenubar();
    buildToolbox();
    loadCharacter(characterIds.length > 0 ? characterIds[0] : null);

    #if mobile
    // Also what puts a camera at index 1, which the engine's own touch
    // handling measures taps against.
    addBackButton(FlxG.width - 230, FlxG.height - 200, FlxColor.WHITE, goBack, 1.0);
    #end
  }

  function buildMenubar():Void
  {
    menubar = cast RuntimeComponentBuilder.fromAsset(Paths.xml('ui/character-editor/menu-bar'));

    if (menubar == null) return;

    menubar.cameras = [camUI];
    add(menubar);

    // The bar itself still spans the screen, so it covers the corners rather
    // than stopping short of them; it is the words inside that move in.
    menubar.validateNow();
    menubarHeight = menubar.height > 0 ? menubar.height : 56;

    wireMenuItem('menuSave', save);
    wireMenuItem('menuReload', () -> loadCharacter(characterId));
    wireMenuItem('menuExit', goBack);
    wireMenuItem('menuResetOffset', resetOffset);
    wireMenuItem('menuReplay', replayAnimation);
    wireMenuItem('menuResetCamera', lookAtCharacter);
    wireMenuItem('menuToggleStage', toggleStage);
    wireMenuItem('menuTogglePanel', togglePanel);
  }

  function wireMenuItem(id:String, action:Void->Void):Void
  {
    if (menubar == null) return;

    var item = menubar.findComponent(id, MenuItem);
    if (item != null) item.onClick = _ -> action();
  }

  function toggleStage():Void
  {
    if (stage != null) stage.visible = !stage.visible;
    refreshBackdrop();
  }

  /**
   * Show the green only when there is no stage to stand on.
   *
   * With a stage up the cameras draw onto nothing, which is black, and the
   * character reads the way it will in a song rather than as a cutout on a
   * menu.
   */
  function refreshBackdrop():Void
  {
    if (bg == null) return;

    bg.visible = stage == null || !stage.visible;
  }

  function togglePanel():Void
  {
    if (toolbox != null) toolbox.hidden = !toolbox.hidden;
  }

  function buildToolbox():Void
  {
    toolbox = cast RuntimeComponentBuilder.fromAsset(Paths.xml('ui/character-editor/character-editor-view'));

    if (toolbox == null) return;

    toolbox.cameras = [camUI];
    toolbox.closable = false;
    add(toolbox);
    toolbox.showDialog(false);
    toolbox.x = SCREEN_INSET;
    toolbox.y = menubarHeight + 12;

    characterDropdown = toolbox.findComponent('characterDropdown', DropDown);
    animationDropdown = toolbox.findComponent('animationDropdown', DropDown);
    animationWarning = toolbox.findComponent('animationWarning', Label);
    offsetLabel = toolbox.findComponent('offsetLabel', Label);
    statusLabel = toolbox.findComponent('statusLabel', Label);
    scaleStepper = toolbox.findComponent('scaleStepper', NumberStepper);
    flipXCheck = toolbox.findComponent('flipXCheck', CheckBox);
    singTimeStepper = toolbox.findComponent('singTimeStepper', NumberStepper);
    danceEveryStepper = toolbox.findComponent('danceEveryStepper', NumberStepper);
    cameraXStepper = toolbox.findComponent('cameraXStepper', NumberStepper);
    cameraYStepper = toolbox.findComponent('cameraYStepper', NumberStepper);

    if (characterDropdown != null)
    {
      for (id in characterIds)
        characterDropdown.dataSource.add({text: id});

      characterDropdown.onChange = function(event:UIEvent) {
        if (populating) return;
        loadCharacter(event.data?.text);
      };
    }

    if (animationDropdown != null)
    {
      animationDropdown.onChange = function(event:UIEvent) {
        if (populating) return;
        playAnimation(event.data?.text);
      };
    }

    positionDropdown = toolbox.findComponent('positionDropdown', DropDown);

    if (positionDropdown != null)
    {
      positionDropdown.onChange = function(event:UIEvent) {
        if (populating) return;

        characterType = switch (event.data?.text)
        {
          case 'dad': DAD;
          case 'gf': GF;
          default: BF;
        };

        loadCharacter(characterId);
      };
    }

    // How many rows an open dropdown shows before it starts scrolling. The
    // width it opens at is in POPUP_STYLE; this is the only part of it the
    // component itself decides.
    for (dropdown in [characterDropdown, animationDropdown, positionDropdown])
    {
      if (dropdown == null) continue;

      dropdown.dropdownSize = 6;
    }

    var resetButton = toolbox.findComponent('resetOffsetButton', Button);
    if (resetButton != null) resetButton.onClick = function(event:MouseEvent) resetOffset();

    var saveButton = toolbox.findComponent('saveButton', Button);
    if (saveButton != null) saveButton.onClick = function(event:MouseEvent) save();

    if (scaleStepper != null) scaleStepper.onChange = function(event:UIEvent) applyScale();
    if (flipXCheck != null) flipXCheck.onChange = function(event:UIEvent) applyFlipX();
    if (singTimeStepper != null) singTimeStepper.onChange = function(event:UIEvent) applySingTime();
    if (danceEveryStepper != null) danceEveryStepper.onChange = function(event:UIEvent) applyDanceEvery();
    if (cameraXStepper != null) cameraXStepper.onChange = function(event:UIEvent) applyCameraOffsets();
    if (cameraYStepper != null) cameraYStepper.onChange = function(event:UIEvent) applyCameraOffsets();
  }

  // -- the character ------------------------------------------------------

  function loadCharacter(id:Null<String>):Void
  {
    if (id == null || id == '')
    {
      say('No character to load.');
      return;
    }

    if (character != null)
    {
      remove(character);
      character.destroy();
      character = null;
    }

    characterId = id;
    data = CharacterDataParser.fetchCharacterData(id);
    character = CharacterDataParser.fetchCharacter(id, true);

    if (character == null || data == null)
    {
      say('Could not load $id.');
      return;
    }

    loadStage();

    character.cameras = [camStage];

    if (stage != null)
    {
      stage.addCharacter(character, characterType);
    }
    else
    {
      // No stage to stand on, so at least put it where it can be seen.
      character.screenCenter();
      add(character);
    }

    applyFlipX(true);

    animationNames = [for (animation in data.animations) animation.name];

    lookAtCharacter();
    refreshBackdrop();

    selectInDropdown(characterDropdown, characterIds.indexOf(characterId));

    fillAnimationDropdown();
    populatePanel();

    if (animationNames.length > 0)
    {
      // Named on the control as well as played, or the dropdown sits blank
      // over an animation that is running.
      selectInDropdown(animationDropdown, 0);
      playAnimation(animationNames[0]);
    }

    say('Loaded $id.');
  }

  /**
   * Build the stage fresh.
   *
   * Rebuilding rather than swapping the character out of the old one: a stage
   * places a character when it is added, and taking one back off again is
   * more of its business than an editor should be reaching into.
   */
  function loadStage():Void
  {
    if (stage != null)
    {
      remove(stage);
      stage = null;
    }

    stage = StageRegistry.instance.fetchEntry(STAGE_ID);

    if (stage == null) return;

    stage.revive();
    ScriptEventDispatcher.callEvent(stage, new ScriptEvent(CREATE, false));

    stage.cameras = [camStage];
    add(stage);
  }

  function lookAtCharacter():Void
  {
    camStage.zoom = 0.7;

    if (character == null)
    {
      camStage.scroll.set(0, 0);
      return;
    }

    var middle = character.getMidpoint();
    camStage.focusOn(middle);
    middle.putWeak();
  }

  function replayAnimation():Void
  {
    if (character == null || animationName == '') return;

    character.playAnimation(animationName, true);
  }

  function fillAnimationDropdown():Void
  {
    if (animationDropdown == null) return;

    populating = true;
    animationDropdown.dataSource.clear();

    for (name in animationNames)
      animationDropdown.dataSource.add({text: name});

    populating = false;
  }

  /**
   * Show a row as the chosen one.
   *
   * A dropdown that has had its rows swapped out under it keeps the index it
   * had and so decides nothing has changed, and comes up blank. Standing it
   * down first makes the second assignment land.
   */
  function selectInDropdown(dropdown:Null<DropDown>, index:Int):Void
  {
    if (dropdown == null || index < 0) return;

    populating = true;
    dropdown.selectedIndex = -1;
    dropdown.selectedIndex = index;
    populating = false;
  }

  function playAnimation(name:Null<String>):Void
  {
    if (character == null || name == null || name == '') return;

    animationName = name;
    character.playAnimation(name, true);

    // An animation whose prefix is not in the sprite sheet plays nothing, and
    // that is the most common thing wrong with a character file, so say so
    // rather than leaving it to be discovered.
    if (animationWarning != null)
    {
      var missing = !character.hasAnimation(name);
      animationWarning.text = missing ? 'No frames for this prefix' : '';
    }

    refreshOffsetLabel();
  }

  function resetOffset():Void
  {
    setOffset(0, 0);
    say('Offset cleared for $animationName.');
  }

  function setOffset(x:Float, y:Float):Void
  {
    if (character == null || animationName == '') return;

    // Both: the map is what gets saved, the field is what the sprite draws
    // itself with.
    character.animOffsets = [x, y];
    character.setAnimationOffsets(animationName, x, y);

    refreshOffsetLabel();
  }

  function currentOffset():Array<Float>
  {
    if (character == null) return [0, 0];

    var stored = character.animationOffsets.get(animationName);
    return stored == null ? [0, 0] : stored;
  }

  function refreshOffsetLabel():Void
  {
    if (offsetLabel == null) return;

    var offset = currentOffset();
    offsetLabel.text = '${Std.int(offset[0])}, ${Std.int(offset[1])}';
  }

  // -- the rest of the character file --------------------------------------

  function populatePanel():Void
  {
    if (data == null) return;

    populating = true;

    if (scaleStepper != null) scaleStepper.pos = data.scale ?? 1.0;
    if (flipXCheck != null) flipXCheck.selected = data.flipX ?? false;
    if (singTimeStepper != null) singTimeStepper.pos = data.singTime ?? 8.0;
    if (danceEveryStepper != null) danceEveryStepper.pos = data.danceEvery ?? 1;

    var camera = data.cameraOffsets ?? [0, 0];
    if (cameraXStepper != null) cameraXStepper.pos = camera.length > 0 ? camera[0] : 0;
    if (cameraYStepper != null) cameraYStepper.pos = camera.length > 1 ? camera[1] : 0;

    populating = false;
  }

  function applyScale():Void
  {
    if (data == null || populating || scaleStepper == null) return;

    data.scale = scaleStepper.pos;

    // Reloading is the honest way to show a scale change: the character sets
    // itself up from its data when it is built, and half of that cannot be
    // changed afterwards.
    if (character != null) character.setScale(data.scale);
  }

  /**
   * Point the character the way its file says to.
   *
   * A character standing in the boyfriend slot is drawn mirrored: the sheets
   * all face the way the opponent stands, and `flipX` in the file is written
   * against that. The stage applies the flip when it takes a character, so
   * setting the sprite straight from the file — as this used to — cancelled
   * it out and the checkbox did nothing at all on that side of the stage.
   *
   * @param fromData Take the value from the file rather than the checkbox,
   *   for when a character has just been loaded and the checkbox is stale.
   */
  function applyFlipX(fromData:Bool = false):Void
  {
    if (data == null) return;
    if (!fromData && (populating || flipXCheck == null)) return;

    if (!fromData && flipXCheck != null) data.flipX = flipXCheck.selected;

    var flipped:Bool = data.flipX ?? false;

    // Mirrored for boyfriend, but only once it is actually on a stage; on its
    // own the character wears the file's value as it is.
    if (stage != null && characterType == BF) flipped = !flipped;

    if (character != null) character.flipX = flipped;
  }

  function applySingTime():Void
  {
    if (data == null || populating || singTimeStepper == null) return;
    data.singTime = singTimeStepper.pos;
  }

  function applyDanceEvery():Void
  {
    if (data == null || populating || danceEveryStepper == null) return;
    data.danceEvery = danceEveryStepper.pos;
  }

  function applyCameraOffsets():Void
  {
    if (data == null || populating) return;
    if (cameraXStepper == null || cameraYStepper == null) return;

    data.cameraOffsets = [cameraXStepper.pos, cameraYStepper.pos];
  }

  function say(message:String):Void
  {
    if (statusLabel != null) statusLabel.text = message;
  }

  // -- input --------------------------------------------------------------

  override function update(elapsed:Float):Void
  {
    super.update(elapsed);

    #if mobile
    updateGestures();
    #else
    updateMouse();
    #end
  }

  /**
   * Whether a point is over the panel, so that using it does not also drag
   * the character underneath.
   */
  function overPanel(x:Float, y:Float):Bool
  {
    return Screen.instance.hasSolidComponentUnderPoint(x, y);
  }

  #if mobile
  function updateGestures():Void
  {
    var touches = FlxG.touches.list;

    if (touches.length >= 2)
    {
      // Two fingers move and scale the view. A drag underway is abandoned
      // rather than fighting the pinch.
      dragging = false;

      var a = touches[0].getWorldPosition(camUI);
      var b = touches[1].getWorldPosition(camUI);

      var midX = (a.x + b.x) / 2;
      var midY = (a.y + b.y) / 2;
      var spread = Math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

      if (pinching)
      {
        camStage.scroll.x -= (midX - lastMid.x) / camStage.zoom;
        camStage.scroll.y -= (midY - lastMid.y) / camStage.zoom;

        if (lastPinchDistance > 0 && spread > 0)
        {
          var zoom = camStage.zoom * (spread / lastPinchDistance);
          camStage.zoom = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, zoom));
        }
      }

      pinching = true;
      lastMid.set(midX, midY);
      lastPinchDistance = spread;

      a.putWeak();
      b.putWeak();
      return;
    }

    pinching = false;

    if (character == null) return;

    if (TouchUtil.justPressed)
    {
      var view = TouchUtil.touch.getWorldPosition(camUI);
      var over = overPanel(view.x, view.y);
      pressedAt.set(view.x, view.y);
      view.putWeak();

      pressWasDrag = false;

      if (!over)
      {
        var point = TouchUtil.touch.getWorldPosition(camStage);
        var offset = currentOffset();

        dragging = true;
        dragAnchor.set(point.x + offset[0], point.y + offset[1]);
        point.putWeak();
      }
    }

    if (dragging && TouchUtil.pressed)
    {
      var view = TouchUtil.touch.getWorldPosition(camUI);
      var wandered = view.distanceTo(pressedAt);
      view.putWeak();

      // Until the finger has gone somewhere this might still turn out to be a
      // tap, and moving the character on the way would undo itself anyway.
      if (wandered > TAP_SLOP)
      {
        pressWasDrag = true;

        var point = TouchUtil.touch.getWorldPosition(camStage);
        setOffset(dragAnchor.x - point.x, dragAnchor.y - point.y);
        point.putWeak();
      }
    }

    if (!TouchUtil.pressed)
    {
      // Let go without having moved and you were asking to see the animation
      // again, not to place the character. A pinch cancels the drag before it
      // gets here, so moving the view never replays anything.
      if (dragging && !pressWasDrag) replayAnimation();

      dragging = false;
    }
  }
  #else
  function updateMouse():Void
  {
    if (character == null) return;

    if (FlxG.mouse.justPressed)
    {
      var view = FlxG.mouse.getViewPosition(camUI);
      var over = overPanel(view.x, view.y);
      pressedAt.set(view.x, view.y);
      view.putWeak();

      pressWasDrag = false;

      if (!over)
      {
        var point = FlxG.mouse.getWorldPosition(camStage);
        var offset = currentOffset();

        dragging = true;
        dragAnchor.set(point.x + offset[0], point.y + offset[1]);
        point.putWeak();
      }
    }

    if (dragging && FlxG.mouse.pressed)
    {
      var view = FlxG.mouse.getViewPosition(camUI);
      var wandered = view.distanceTo(pressedAt);
      view.putWeak();

      if (wandered > TAP_SLOP)
      {
        pressWasDrag = true;

        var point = FlxG.mouse.getWorldPosition(camStage);
        setOffset(dragAnchor.x - point.x, dragAnchor.y - point.y);
        point.putWeak();
      }
    }

    if (!FlxG.mouse.pressed)
    {
      if (dragging && !pressWasDrag) replayAnimation();

      dragging = false;
    }

    if (FlxG.mouse.wheel != 0)
    {
      var zoom = camStage.zoom + FlxG.mouse.wheel * 0.1;
      camStage.zoom = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, zoom));
    }
  }
  #end

  function goBack():Void
  {
    FlxG.switchState(() -> new funkin.ui.debug.EditorHubState());
  }

  // -- saving -------------------------------------------------------------

  /**
   * Write the character out as a mod.
   *
   * The old editor saves through a desktop file dialog, which is why it
   * cannot save on a phone at all. This writes the file itself, and says
   * either way — there is no console to check.
   */
  function save():Void
  {
    if (data == null || character == null)
    {
      say('Nothing to save.');
      return;
    }

    // The sprite has been carrying the offsets while they were dragged; put
    // them back into the data before it is written.
    for (animation in data.animations)
    {
      var offsets = character.animationOffsets.get(animation.name);
      if (offsets != null) animation.offsets = [offsets[0], offsets[1]];
    }

    #if sys
    var root = '$MOD_ROOT/$MOD_ID';

    try
    {
      FileUtil.createDirIfNotExists(MOD_ROOT);
      FileUtil.createDirIfNotExists(root);
      FileUtil.createDirIfNotExists('$root/data');
      FileUtil.createDirIfNotExists('$root/data/characters');

      FileUtil.writeStringToPath('$root/_polymod_meta.json', modMeta(), Force);
      FileUtil.writeStringToPath('$root/data/characters/$characterId.json', haxe.Json.stringify(data, null, '  '), Force);

      say('Saved to $root/data/characters/$characterId.json');
    }
    catch (error)
    {
      say('Could not save: $error');
    }
    #else
    say('Saving is not available on this platform.');
    #end
  }

  function modMeta():String
  {
    return haxe.Json.stringify({
      title: "Editor",
      description: "Characters saved from the editor app.",
      contributors: [],
      api_version: "0.1.0",
      mod_version: "1.0.0",
      license: "Unlicense"
    }, null, '  ');
  }
}
