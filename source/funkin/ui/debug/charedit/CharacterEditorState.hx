package funkin.ui.debug.charedit;

import flixel.FlxSprite;
import flixel.addons.transition.FlxTransitionableState;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.data.animation.AnimationData;
import funkin.data.character.CharacterData;
import funkin.data.character.CharacterData.CharacterDataParser;
import funkin.data.character.CharacterData.HealthIconData;
import funkin.data.song.SongRegistry;
import funkin.data.stage.StageRegistry;
import funkin.modding.events.ScriptEvent;
import funkin.modding.events.ScriptEventDispatcher;
import funkin.graphics.FunkinCamera;
import funkin.play.character.BaseCharacter;
import funkin.play.character.BaseCharacter.CharacterType;
import funkin.play.PlayStatePlaylist;
import funkin.play.song.Song;
import funkin.play.song.Song.SongDifficulty;
import funkin.play.stage.Stage;
import funkin.ui.FullScreenScaleMode;
import funkin.ui.MusicBeatState;
import funkin.ui.transition.LoadingState;
import funkin.util.FileUtil;
import funkin.util.FileUtil.SelectedFileData;
import funkin.util.assets.FlxAnimationUtil;
import funkin.util.SortUtil;
import haxe.ui.RuntimeComponentBuilder;
import haxe.ui.components.Button;
import haxe.ui.components.CheckBox;
import haxe.ui.components.DropDown;
import haxe.ui.components.Label;
import haxe.ui.components.NumberStepper;
import haxe.ui.components.TextField;
import haxe.ui.containers.Grid;
import haxe.ui.containers.ScrollView;
import haxe.ui.containers.dialogs.CollapsibleDialog;
import haxe.ui.containers.dialogs.Dialog.DialogEvent;
import haxe.ui.containers.menus.MenuBar;
import haxe.ui.containers.menus.MenuCheckBox;
import haxe.ui.containers.menus.MenuItem;
import haxe.ui.containers.menus.MenuOptionBox;
import haxe.ui.core.Component;
import haxe.ui.core.Screen;
import haxe.ui.events.MouseEvent;
import haxe.ui.events.UIEvent;
import haxe.ui.util.Variant;
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
 * changes how you reach them. The panels are built the same way the other
 * editors build theirs, from layouts in the assets, so they belong to the
 * same set; what differs is that the controls are sized for a finger, the
 * character is placed by dragging it rather than by typing numbers, and the
 * file is split across a window per topic rather than one long column.
 */
class CharacterEditorState extends MusicBeatState
{
  /**
   * Where an imported sprite sheet goes.
   *
   * A character has to be able to find its own sheet through the game's asset
   * system, and the only way in is a mod, so a sheet lands in one whether or
   * not the character built from it is ever written anywhere.
   */
  static final MOD_ROOT:String = 'mods';

  static final MOD_ID:String = 'editor';

  /**
   * Where a sprite sheet has to be for the editor to find it.
   */
  static final SHEET_DIR:String = 'mods/editor/images/characters';

  /**
   * Where the folder someone last read mods out of is written down.
   *
   * A dotted name so that the mod scan does not take it for a mod.
   */
  static final SOURCE_NOTE:String = 'mods/.mod-source';

  /**
   * The two apps, for guessing where the game keeps its own mods.
   *
   * They stand side by side under the same parent, so the editor's own
   * storage folder names the game's. Reading it that way only works where
   * the system still allows it, which is why it is a guess rather than the
   * way in.
   */
  static final EDITOR_PACKAGE:String = 'dev.funkin.editors';

  static final GAME_PACKAGE:String = 'me.funkin.fnf';

  /**
   * The stage a character is shown on. The one the game opens on, so what you
   * see here is what most songs will show.
   */
  static final STAGE_ID:String = 'mainStage';

  static final ZOOM_MIN:Float = 0.15;

  static final ZOOM_MAX:Float = 4.0;

  /**
   * How far the panels and the menu bar's contents sit in from the edge.
   *
   * Phone screens are rounded, so the corner pixels are not there to be
   * tapped even though the layout thinks they are. Anything you have to hit
   * starts far enough in to clear the curve. The menu bar carries the same
   * number as padding in its own layout, since it spans the screen.
   */
  static final SCREEN_INSET:Float = 30;

  /**
   * How far a finger may wander and still count as a tap.
   */
  static final TAP_SLOP:Float = 14;

  /**
   * How big a face is in the character picker.
   *
   * The chart editor uses 70, and this is the same picker with more room to
   * hit, since here it is a thumb rather than a mouse pointer.
   */
  static final TILE:Float = 88;

  /**
   * How many offset changes can be taken back.
   */
  static final UNDO_DEPTH:Int = 60;

  /**
   * Sizes for fingers rather than for a mouse pointer.
   *
   * The toolkit's own numbers assume a pointer that lands where it is aimed:
   * a stepper's arrows get four pixels of padding either side, a checkbox is
   * eighteen pixels square. Those are fine targets for a mouse and much too
   * small for a thumb, and they are set in one stylesheet, so this is one
   * stylesheet too rather than a size written onto every control in every
   * layout — which also reaches the controls that are built in code and have
   * no layout to write it on.
   *
   * The menu bar's height is measured at runtime, so the windows follow it
   * down on their own when its rows get taller.
   */
  static final TOUCH_STYLE:String = '
    .button { padding: 14px 20px; }

    .number-stepper .stepper-inc,
    .number-stepper .stepper-deinc { padding: 6px 18px; }

    .checkbox-value { width: 32px; height: 32px; }

    .dropdown { padding: 12px 12px; }
    .textfield { padding: 12px 10px; }

    .menu { initial-width: 320px; }
    .menuitem { padding: 14px; padding-left: 18px; }

    .dialog-title { padding: 12px; }
    .dialog-close-button,
    .dialog-minimize-button { padding: 12px; }

    /*
      On a phone HaxeUI opens a dropdown as a modal in the middle of the
      screen, which is the right shape for a thumb, but its stylesheet sizes
      that modal at three quarters of the screen whatever is in it.
    */
    .dropdown-popup:mobile { width: 360px; }
    .dropdown-popup .listview .itemrenderer { padding: 16px 12px; }
  ';

  /**
   * Whether this run has already gone looking for the game's mods.
   *
   * Once per run rather than once per visit: reading them means reloading
   * every asset, and doing that each time somebody comes back to this
   * screen would be a pause for nothing.
   */
  static var scannedMods:Bool = false;

  /**
   * Which character to come up on after the editor has been rebuilt.
   *
   * Picking up a sheet that was not there when the game started means
   * reloading the assets, and that takes the editor with it, so the things
   * worth keeping are carried across by hand.
   */
  static var pendingCharacterId:Null<String> = null;

  /**
   * A character built from a sheet but not written anywhere.
   *
   * Importing loads a character in to be worked on; it is File > Export that
   * decides where it ends up, and until then it lives here and in the
   * registry's cache, which the reload also empties.
   */
  static var pendingCharacterJson:Null<String> = null;

  /**
   * The view the character sits in, which moves and zooms under two fingers.
   */
  var camStage:FunkinCamera;

  /**
   * Where the panels live, so they stay put while the view moves.
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

  /**
   * The green behind an empty editor.
   *
   * Only up while there is no stage: a character standing on one should look
   * the way it will in the game, and the game has nothing behind its stages.
   */
  var bg:Null<FlxSprite> = null;

  var menubar:Null<MenuBar> = null;

  /**
   * How far down a window has to start to clear the menu bar.
   */
  var menubarHeight:Float = 0;

  // -- the windows --------------------------------------------------------

  var windows:Map<String, EditorWindow> = new Map<String, EditorWindow>();

  /**
   * The rows under Window, by the window each one stands for, so that a
   * window closed by its own button can put its own tick down.
   */
  var windowToggles:Map<String, MenuCheckBox> = new Map<String, MenuCheckBox>();

  /**
   * The View rows naming the stage slots, so the one in use stays marked.
   */
  var positionRows:Map<CharacterType, MenuOptionBox> = new Map<CharacterType, MenuOptionBox>();

  /**
   * Everything that puts a value from the character file onto a control.
   *
   * One per control, added as the control is bound, so that loading a
   * character is a matter of running the lot rather than of remembering to
   * add a line here for every field added over there.
   */
  var refreshers:Array<Void->Void> = [];

  // -- the controls a window does not own -------------------------------

  var characterGridScroll:Null<ScrollView> = null;
  var characterNameLabel:Null<Label> = null;
  var characterSlotLabel:Null<Label> = null;
  var animationDropdown:Null<DropDown> = null;
  var animationWarning:Null<Label> = null;
  var offsetLabel:Null<Label> = null;
  var animationNameField:Null<TextField> = null;
  var animOffsetX:Null<NumberStepper> = null;
  var animOffsetY:Null<NumberStepper> = null;
  var copyOffsetDropdown:Null<DropDown> = null;
  var playtestSongDropdown:Null<DropDown> = null;
  var playtestDifficultyDropdown:Null<DropDown> = null;

  /**
   * The song a playtest would play, and on which difficulty.
   */
  var playtestSongId:Null<String> = null;

  var playtestDifficulty:Null<String> = null;

  /**
   * Whether the game plays the song itself during a playtest.
   *
   * On by default: a playtest is for watching the character, and watching it
   * is hard to do while hitting notes.
   */
  var playtestBotPlay:Bool = true;

  /**
   * What the song said before a playtest put this character into it.
   *
   * The registry hands out one song and hands out the same one every time,
   * so the override has to be taken back off again afterwards or it is still
   * there the next time anything asks for that song.
   */
  var playtestOverride:Null<PlaytestOverride> = null;

  /**
   * Which animation was up when the playtest started.
   */
  var playtestAnimation:String = '';

  /**
   * Which windows were up when the playtest started.
   */
  var playtestWindows:Array<String> = [];

  /**
   * The editor's own cameras, held aside while a playtest is up.
   *
   * A song resets the camera list on its way in, which destroys every camera
   * that was already there, so these are taken out of the list first and put
   * back afterwards.
   *
   * The editor's own, and no others: the touch pointer keeps a camera in
   * that list which it manages itself, replacing it when it is destroyed, so
   * holding onto that one means putting back a camera that has been thrown
   * away and replaced.
   */
  var playtestCameras:Array<flixel.FlxCamera> = [];

  /**
   * Which animation the copy dropdown is pointing at.
   *
   * Kept here rather than read back off the control, which is the shape the
   * animation dropdown already uses.
   */
  var copyOffsetChoice:Null<String> = null;

  /**
   * Where each offset stood before it was last moved, newest last.
   *
   * Placing a character is guesswork done by eye, and the drag that went too
   * far is only recognised as such after it has happened, so every way of
   * moving an offset writes down what it is about to paint over.
   */
  var offsetHistory:Array<OffsetEdit> = [];

  /**
   * A see-through copy of the character, left where it was.
   *
   * Setting an offset is judging a distance, and a distance needs two things
   * to be between. This is the other one: it stays put while the character
   * moves, so what you are dragging is the gap.
   */
  var ghost:Null<BaseCharacter> = null;
  var statusLabel:Null<Label> = null;

  /**
   * What the editor last had to say, on the screen rather than in a window.
   *
   * The editor now opens with every window closed, and a message that only
   * exists inside one of them is a message nobody reads — which matters most
   * for the ones explaining why something did not work.
   */
  var statusText:Null<FlxText> = null;

  // -- making a character out of a sprite sheet ---------------------------

  var newCharacterDialog:Null<CollapsibleDialog> = null;
  var sheetDropdown:Null<DropDown> = null;
  var sheetPathLabel:Null<Label> = null;
  var sheetSummaryLabel:Null<Label> = null;
  var newCharacterStatus:Null<Label> = null;

  /**
   * The sheets sitting in `SHEET_DIR`, in the order the dropdown lists them.
   */
  var sheetNames:Array<String> = [];

  /**
   * Set while the panels are being filled in from a character, so that
   * changing a control does not read as the person having changed it.
   */
  var populating:Bool = false;

  /**
   * Something to do once the toolkit has finished with the click that asked
   * for it.
   *
   * Leaving the editor and reloading the assets both tear down every
   * component HaxeUI is holding, and a menu item asking for either of them
   * is asking from inside a pass that is still walking those components.
   */
  var afterThisFrame:Null<Void->Void> = null;

  // -- gesture state ------------------------------------------------------

  var dragging:Bool = false;

  /**
   * Where the offset would be with the finger at the origin, so a drag turns
   * into an offset without accumulating error.
   */
  var dragAnchor:FlxPoint = new FlxPoint();

  /**
   * Whether a finger that went down somewhere other than on the character is
   * pulling the view along behind it.
   */
  var panning:Bool = false;

  var pinching:Bool = false;

  /**
   * Where the panning finger was last seen, so a pan is a series of small
   * moves rather than a jump to wherever it started.
   */
  var lastPan:FlxPoint = new FlxPoint();

  var lastMid:FlxPoint = new FlxPoint();

  var lastPinchDistance:Float = 0;

  /**
   * Where a press started, so that letting go without having moved can be
   * told apart from a drag. One is asking to see the animation again, the
   * other is placing the character, and they start out identical.
   */
  var pressedAt:FlxPoint = new FlxPoint();

  var pressWasDrag:Bool = false;

  function later(action:Void->Void):Void
  {
    afterThisFrame = action;
  }

  override function create():Void
  {
    FlxTransitionableState.skipNextTransIn = true;
    super.create();

    // The same green as the screen this was opened from, so the app reads as
    // one thing rather than as the game with an editor bolted on.
    bg = new FlxSprite();
    styleBackdrop(bg);
    add(bg);

    camStage = new FunkinCamera('camStage');
    camStage.bgColor = 0x0;
    FlxG.cameras.add(camStage, false);

    camUI = new FunkinCamera('camUI');
    camUI.bgColor = 0x0;
    FlxG.cameras.add(camUI, false);

    statusText = new FlxText(SCREEN_INSET, FlxG.height - 46, FlxG.width - SCREEN_INSET * 2, '');
    statusText.setFormat(Paths.font('vcr.ttf'), 22, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
    statusText.scrollFactor.set(0, 0);
    statusText.cameras = [camUI];
    add(statusText);

    // Cleared again by the hub on the way back out, the same way the debug
    // menu clears what it adds.
    haxe.ui.Toolkit.styleSheet.parse(TOUCH_STYLE, 'user');

    // Made now rather than when it is first needed, so that the folder is
    // there to be found by someone plugging the phone into a computer.
    makeModDirs();

    // Whatever was read last time, read again, in case it has changed.
    if (!scannedMods)
    {
      scannedMods = true;
      readRememberedMods();
    }

    // A character imported just before the reload that brought us back here
    // has no file anywhere; putting it in the cache is what makes it real
    // enough to be built, played and eventually exported.
    adoptPendingCharacter();

    characterIds = CharacterDataParser.listCharacterIds();
    characterIds.sort(SortUtil.alphabetically);

    buildMenubar();
    buildWindows();

    var opening:Null<String> = pendingCharacterId;
    pendingCharacterId = null;

    if (opening == null || characterIds.indexOf(opening) == -1)
    {
      opening = characterIds.length > 0 ? characterIds[0] : null;
    }

    loadCharacter(opening);

    #if mobile
    // Also what puts a camera at index 1, which the engine's own touch
    // handling measures taps against.
    addBackButton(FlxG.width - 230, FlxG.height - 200, FlxColor.WHITE, goBack, 1.0);
    #end
  }

  /**
   * Take on a character that was built from a sheet and never written down.
   */
  function adoptPendingCharacter():Void
  {
    if (pendingCharacterJson == null || pendingCharacterId == null) return;

    var adopted:Null<CharacterData> = CharacterDataParser.parseCharacterDataString(pendingCharacterId, pendingCharacterJson);

    if (adopted != null) CharacterDataParser.registerCharacterData(pendingCharacterId, adopted);

    pendingCharacterJson = null;
  }

  function buildMenubar():Void
  {
    menubar = cast RuntimeComponentBuilder.fromAsset(Paths.xml('ui/character-editor/menu-bar'));

    if (menubar == null) return;

    // Through the toolkit rather than added to the state directly: HaxeUI
    // adds a component to the state itself when it takes one, so doing both
    // leaves it in the state's list twice.
    Screen.instance.addComponent(menubar);
    menubar.cameras = [camUI];

    // The bar itself still spans the screen, so it covers the corners rather
    // than stopping short of them; it is the words inside that move in.
    menubar.validateNow();
    menubarHeight = menubar.height > 0 ? menubar.height : 56;

    wireMenuItem('menuNew', () -> showWindow('windowNewCharacter', true));
    wireMenuItem('menuImport', () -> {
      showWindow('windowNewCharacter', true);
      later(importSheet);
    });
    wireMenuItem('menuExport', exportCharacter);
    wireMenuItem('menuReload', () -> loadCharacter(characterId, true));
    wireMenuItem('menuPlaytest', () -> showWindow('windowPlaytest', true));
    wireMenuItem('menuLoadMods', () -> later(loadMods));
    wireMenuItem('menuExit', () -> later(goBack));
    wireMenuItem('menuUndoOffset', undoOffset);
    wireMenuItem('menuResetOffset', resetOffset);
    wireMenuItem('menuReplay', replayAnimation);
    wireMenuItem('menuResetCamera', lookAtCharacter);
    wirePosition('menuPositionBf', BF);
    wirePosition('menuPositionDad', DAD);
    wirePosition('menuPositionGf', GF);
  }

  /**
   * Tie one of the View rows to the slot it names.
   */
  function wirePosition(id:String, slot:CharacterType):Void
  {
    if (menubar == null) return;

    var row = menubar.findComponent(id, MenuOptionBox);
    if (row == null) return;

    positionRows.set(slot, row);
    row.registerEvent(UIEvent.CHANGE, function(_) {
      if (row.selected) standAt(slot);
    });
  }

  /**
   * Move the character to another slot on the stage.
   */
  function standAt(slot:CharacterType):Void
  {
    if (slot == characterType) return;

    characterType = slot;

    var row = positionRows.get(slot);
    if (row != null && !row.selected) row.selected = true;

    // The same character, but standing somewhere else, so this one is worth
    // doing again.
    loadCharacter(characterId, true);
  }

  function slotName():String
  {
    return switch (characterType)
    {
      case DAD: 'Standing as the opponent';
      case GF: 'Standing as girlfriend';
      default: 'Standing as boyfriend';
    };
  }

  function wireMenuItem(id:String, action:Void->Void):Void
  {
    if (menubar == null) return;

    var item = menubar.findComponent(id, MenuItem);
    if (item != null) item.onClick = _ -> action();
  }

  // -- windows ------------------------------------------------------------

  /**
   * Build every window and give each one a row under Window.
   *
   * Laid out left to right in the order they are made. When the row runs out
   * of screen the next one starts again from the left, but stepped down and
   * across, the way a desk full of windows ends up: there is not room for
   * five of these side by side on a phone, and windows exactly on top of one
   * another look like windows that have gone missing.
   */
  function buildWindows():Void
  {
    var left:Float = SCREEN_INSET;
    var wraps:Int = 0;

    function place(dialog:Null<CollapsibleDialog>):Void
    {
      if (dialog == null) return;

      if (left + dialog.width > FlxG.width - SCREEN_INSET && left > SCREEN_INSET)
      {
        wraps++;
        left = SCREEN_INSET + wraps * 36;
      }

      dialog.left = left;
      dialog.top = menubarHeight + 12 + wraps * 36;

      left += dialog.width + 12;
    }

    var select = openWindow('windowCharacter', 'ui/character-editor/character-select-view', place);
    var animation = openWindow('windowAnimation', 'ui/character-editor/animation-view', place);
    var characterData = openWindow('windowCharacterData', 'ui/character-editor/character-data-view', place);
    var healthIcon = openWindow('windowHealthIcon', 'ui/character-editor/health-icon-view', place);
    var newCharacter = openWindow('windowNewCharacter', 'ui/character-editor/new-character-view', place);
    var playtest = openWindow('windowPlaytest', 'ui/character-editor/playtest-view', place);

    buildCharacterSelect(select);
    buildAnimationWindow(animation);
    buildCharacterDataWindow(characterData);
    buildHealthIconWindow(healthIcon);
    buildNewCharacterWindow(newCharacter);
    buildPlaytestWindow(playtest);

    newCharacterDialog = newCharacter;

    // Whichever ones the menu says start open. Everything is wired by now, so
    // a window coming up does not find half of itself missing.
    for (id in windows.keys())
      showWindow(id, tickedAtBuild(id));
  }

  /**
   * Whether a window's row was ticked in the layout, which is how the menu
   * bar says which windows the editor opens on.
   */
  function tickedAtBuild(id:String):Bool
  {
    var toggle = windowToggles.get(id);
    return toggle != null && toggle.selected;
  }

  /**
   * Load a window's layout, remember it, and tie it to its row.
   */
  function openWindow(id:String, layout:String, place:Null<CollapsibleDialog>->Void):Null<CollapsibleDialog>
  {
    var dialog:Null<CollapsibleDialog> = cast RuntimeComponentBuilder.fromAsset(Paths.xml(layout));

    if (dialog == null) return null;

    // Closing a dialog destroys it unless it is told not to, and these have
    // to survive being put away and brought back.
    dialog.destroyOnClose = false;

    // Laid out but not shown. Showing a dialog queues a recentre and a
    // visibility flip a frame or two out, so a window that was shown here
    // just to be measured would put itself back up after being hidden.
    dialog.validateNow();
    place(dialog);

    windows.set(id, {dialog: dialog, shown: false, left: dialog.left, top: dialog.top});

    // A dialog closed by its own X goes straight to hide() without passing
    // through the menu, so the row it belongs to would stay ticked over a
    // window that is not there.
    dialog.onDialogClosed = function(_) {
      var window = windows.get(id);
      if (window != null) window.shown = false;

      var toggle = windowToggles.get(id);
      if (toggle != null && toggle.selected) toggle.selected = false;
    };

    wireWindowToggle(id);

    return dialog;
  }

  /**
   * Tie a row under Window to the window it names.
   */
  function wireWindowToggle(id:String):Void
  {
    if (menubar == null) return;

    var item = menubar.findComponent(id, MenuCheckBox);
    if (item == null) return;

    windowToggles.set(id, item);
    item.registerEvent(UIEvent.CHANGE, function(_) showWindow(id, item.selected));
  }

  /**
   * Put a window up or away.
   *
   * Takes the state it wants rather than flipping what is there, because
   * setting a row's tick reports a change of its own and a window that
   * toggled on being told what it already is would never settle.
   */
  function showWindow(id:String, on:Bool):Void
  {
    var window = windows.get(id);
    if (window == null || window.shown == on) return;

    window.shown = on;

    if (on)
    {
      window.dialog.showDialog(false);
      window.dialog.cameras = [camUI];
      window.dialog.left = window.left;
      window.dialog.top = window.top;
    }
    else
    {
      window.dialog.hide();
    }

    var toggle = windowToggles.get(id);
    if (toggle != null && toggle.selected != on) toggle.selected = on;
  }

  // -- tying a control to a field in the file -----------------------------

  /**
   * Bind a stepper to a number in the character file.
   *
   * The read half is kept so that loading a character can push every value
   * back onto its control at once; the write half ignores the change it
   * causes doing that.
   */
  function bindStepper(owner:Null<Component>, id:String, read:Void->Float, write:Float->Void):Void
  {
    if (owner == null) return;

    var stepper = owner.findComponent(id, NumberStepper);
    if (stepper == null) return;

    // Pressing either arrow focuses the whole stepper, and a stepper taking
    // focus hands it straight to the number in the middle -- which on a
    // phone is a soft keyboard over the screen, once, before the arrow can
    // be pressed again. Nothing here is worth typing that isn't easier to
    // drag or step.
    stepper.allowFocus = false;

    refreshers.push(function() stepper.pos = read());

    stepper.onChange = function(_) {
      if (populating || data == null) return;
      write(stepper.pos);
    };
  }

  function bindCheck(owner:Null<Component>, id:String, read:Void->Bool, write:Bool->Void):Void
  {
    if (owner == null) return;

    var check = owner.findComponent(id, CheckBox);
    if (check == null) return;

    refreshers.push(function() check.selected = read());

    check.onChange = function(_) {
      if (populating || data == null) return;
      write(check.selected);
    };
  }

  function bindField(owner:Null<Component>, id:String, read:Void->String, write:String->Void):Void
  {
    if (owner == null) return;

    var field = owner.findComponent(id, TextField);
    if (field == null) return;

    refreshers.push(function() field.text = read());

    field.onChange = function(_) {
      if (populating || data == null) return;

      // The toolkit does not always deliver a change while the value is
      // being put back, so a write that matches what is already there is
      // taken as the refresh it is. Rebuilding an animation because it was
      // merely redisplayed costs the one that is playing.
      var value:String = field.text ?? '';
      if (value == read()) return;

      write(value);
    };
  }

  function bindLabel(owner:Null<Component>, id:String, read:Void->String):Void
  {
    if (owner == null) return;

    var label = owner.findComponent(id, Label);
    if (label == null) return;

    refreshers.push(function() label.text = read());
  }

  function bindButton(owner:Null<Component>, id:String, action:Void->Void):Void
  {
    if (owner == null) return;

    var button = owner.findComponent(id, Button);
    if (button != null) button.onClick = function(_) action();
  }

  /**
   * Put every value in the file back onto the control that shows it.
   */
  function refreshWindows():Void
  {
    if (data == null) return;

    populating = true;
    for (refresh in refreshers)
      refresh();
    populating = false;

    refreshOffsetLabel();
  }

  /**
   * The health icon block, made if the file does not have one.
   */
  function healthIcon():HealthIconData
  {
    if (data == null) return blankHealthIcon();

    if (data.healthIcon == null) data.healthIcon = blankHealthIcon();

    return data.healthIcon;
  }

  static function blankHealthIcon():HealthIconData
  {
    return {id: null, shouldBop: true, scale: 1.0, flipX: false, isPixel: false, offsets: [0.0, 25.0]};
  }

  /**
   * The entry in the file for the animation being looked at.
   */
  function currentAnimation():Null<AnimationData>
  {
    if (data == null || animationName == '') return null;

    for (animation in data.animations)
      if (animation.name == animationName) return animation;

    return null;
  }

  /**
   * A pair of numbers from the file, either of which may be missing.
   */
  static function pairValue(pair:Null<Array<Float>>, index:Int):Float
  {
    if (pair == null || index >= pair.length) return 0;
    return pair[index];
  }

  // -- the windows themselves ---------------------------------------------

  function buildCharacterSelect(dialog:Null<CollapsibleDialog>):Void
  {
    if (dialog == null) return;

    characterGridScroll = dialog.findComponent('characterGridScroll', ScrollView);
    characterNameLabel = dialog.findComponent('characterNameLabel', Label);
    characterSlotLabel = dialog.findComponent('characterSlotLabel', Label);

    buildCharacterGrid();
  }

  /**
   * A face per character in the registry.
   *
   * Built here rather than in the layout because how many there are depends
   * on what mods are installed, and rebuilt when that changes.
   */
  function buildCharacterGrid():Void
  {
    if (characterGridScroll == null) return;

    characterGridScroll.removeAllComponents();

    var grid = new Grid();
    grid.columns = 4;
    grid.percentWidth = 100;

    for (id in characterIds)
    {
      var entry:Null<CharacterData> = CharacterDataParser.fetchCharacterData(id);

      var tile = new Button();
      tile.width = TILE;
      tile.height = TILE;
      tile.padding = 8;
      tile.iconPosition = 'top';

      var icon = CharacterDataParser.getCharPixelIconAsset(id);
      if (icon != null) tile.icon = Variant.fromImageData(icon);

      tile.text = shortName(entry?.name ?? id);
      tile.onClick = function(_) loadCharacter(id);

      grid.addComponent(tile);
    }

    characterGridScroll.addComponent(grid);
  }

  /**
   * A name that fits on a tile.
   */
  static function shortName(name:String):String
  {
    var LIMIT:Int = 8;
    return name.length > LIMIT ? '${name.substr(0, LIMIT)}.' : name;
  }

  function buildCharacterDataWindow(dialog:Null<CollapsibleDialog>):Void
  {
    if (dialog == null) return;

    bindField(dialog, 'nameField', () -> data?.name ?? '', function(value) data.name = value);

    bindLabel(dialog, 'renderTypeLabel', () -> data == null ? '' : 'Drawn as: ${Std.string(data.renderType)}');
    bindLabel(dialog, 'assetPathLabel', () -> data == null ? '' : 'Sheet: ${data.assetPath}');

    bindStepper(dialog, 'scaleStepper', () -> data?.scale ?? 1.0, function(value) {
      data.scale = value;
      if (character != null) character.setScale(value);
    });

    bindCheck(dialog, 'flipXCheck', () -> data?.flipX ?? false, function(value) {
      data.flipX = value;
      applyFlipX();
    });

    bindCheck(dialog, 'isPixelCheck', () -> data?.isPixel ?? false, function(value) {
      data.isPixel = value;
      say('Pixel art takes effect on reload.');
    });

    bindStepper(dialog, 'singTimeStepper', () -> data?.singTime ?? 8.0, function(value) data.singTime = value);
    bindStepper(dialog, 'danceEveryStepper', () -> data?.danceEvery ?? 1.0, function(value) data.danceEvery = value);

    bindStepper(dialog, 'offsetXStepper', () -> pairValue(data?.offsets, 0), function(value) {
      data.offsets = [value, pairValue(data.offsets, 1)];
      if (character != null) character.globalOffsets = data.offsets;
    });
    bindStepper(dialog, 'offsetYStepper', () -> pairValue(data?.offsets, 1), function(value) {
      data.offsets = [pairValue(data.offsets, 0), value];
      if (character != null) character.globalOffsets = data.offsets;
    });

    bindStepper(dialog, 'cameraXStepper', () -> pairValue(data?.cameraOffsets, 0),
      function(value) data.cameraOffsets = [value, pairValue(data.cameraOffsets, 1)]);
    bindStepper(dialog, 'cameraYStepper', () -> pairValue(data?.cameraOffsets, 1),
      function(value) data.cameraOffsets = [pairValue(data.cameraOffsets, 0), value]);

    bindField(dialog, 'startingAnimationField', () -> data?.startingAnimation ?? 'idle',
      function(value) data.startingAnimation = value);
  }

  function buildHealthIconWindow(dialog:Null<CollapsibleDialog>):Void
  {
    if (dialog == null) return;

    bindField(dialog, 'iconIdField', () -> healthIcon().id ?? '', function(value) healthIcon().id = value == '' ? null : value);

    bindStepper(dialog, 'iconScaleStepper', () -> healthIcon().scale ?? 1.0, function(value) healthIcon().scale = value);
    bindCheck(dialog, 'iconBopCheck', () -> healthIcon().shouldBop ?? true, function(value) healthIcon().shouldBop = value);
    bindCheck(dialog, 'iconFlipXCheck', () -> healthIcon().flipX ?? false, function(value) healthIcon().flipX = value);
    bindCheck(dialog, 'iconPixelCheck', () -> healthIcon().isPixel ?? false, function(value) healthIcon().isPixel = value);

    bindStepper(dialog, 'iconOffsetXStepper', () -> iconOffset(0), function(value) healthIcon().offsets = [value, iconOffset(1)]);
    bindStepper(dialog, 'iconOffsetYStepper', () -> iconOffset(1), function(value) healthIcon().offsets = [iconOffset(0), value]);
  }

  function iconOffset(index:Int):Float
  {
    return pairValue(healthIcon().offsets, index);
  }

  function buildAnimationWindow(dialog:Null<CollapsibleDialog>):Void
  {
    if (dialog == null) return;

    animOffsetX = dialog.findComponent('animOffsetXStepper', NumberStepper);
    animOffsetY = dialog.findComponent('animOffsetYStepper', NumberStepper);

    animationDropdown = dialog.findComponent('animationDropdown', DropDown);
    animationWarning = dialog.findComponent('animationWarning', Label);
    offsetLabel = dialog.findComponent('offsetLabel', Label);
    statusLabel = dialog.findComponent('statusLabel', Label);

    if (animationDropdown != null)
    {
      animationDropdown.dropdownSize = 6;
      animationDropdown.onChange = function(event:UIEvent) {
        var picked:Null<String> = event.data?.text;
        if (populating || picked == null || picked == animationName) return;

        playAnimation(picked);
      };
    }

    bindStepper(dialog, 'animOffsetXStepper', () -> currentOffset()[0], function(value) {
      recordOffset();
      setOffset(value, currentOffset()[1]);
    });
    bindStepper(dialog, 'animOffsetYStepper', () -> currentOffset()[1], function(value) {
      recordOffset();
      setOffset(currentOffset()[0], value);
    });

    animationNameField = dialog.findComponent('nameField', TextField);
    if (animationNameField != null)
    {
      var field = animationNameField;
      refreshers.push(function() field.text = animationName);
    }

    bindField(dialog, 'prefixField', () -> currentAnimation()?.prefix ?? '', function(value) {
      var animation = currentAnimation();
      if (animation == null) return;

      animation.prefix = value;
      rebuildAnimation(animation);
    });

    bindField(dialog, 'frameIndicesField', () -> describeIndices(currentAnimation()?.frameIndices), function(value) {
      var animation = currentAnimation();
      if (animation == null) return;

      animation.frameIndices = readIndices(value);
      rebuildAnimation(animation);
    });

    bindButton(dialog, 'addAnimationButton', addAnimation);
    bindButton(dialog, 'deleteAnimationButton', deleteAnimation);
    bindButton(dialog, 'renameButton', function() {
      if (animationNameField != null) renameAnimation(animationNameField.text ?? '');
    });

    bindStepper(dialog, 'frameRateStepper', () -> currentAnimation()?.frameRate ?? 24, function(value) {
      var animation = currentAnimation();
      if (animation != null) animation.frameRate = Std.int(value);
      applyAnimationSettings();
    });

    bindCheck(dialog, 'loopedCheck', () -> currentAnimation()?.looped ?? false, function(value) {
      var animation = currentAnimation();
      if (animation != null) animation.looped = value;
      applyAnimationSettings();
    });

    bindCheck(dialog, 'animFlipXCheck', () -> currentAnimation()?.flipX ?? false, function(value) {
      var animation = currentAnimation();
      if (animation != null) animation.flipX = value;
      applyAnimationSettings();
    });

    bindCheck(dialog, 'animFlipYCheck', () -> currentAnimation()?.flipY ?? false, function(value) {
      var animation = currentAnimation();
      if (animation != null) animation.flipY = value;
      applyAnimationSettings();
    });

    bindButton(dialog, 'resetOffsetButton', resetOffset);
    bindButton(dialog, 'undoOffsetButton', undoOffset);
    bindButton(dialog, 'replayButton', replayAnimation);

    copyOffsetDropdown = dialog.findComponent('copyOffsetDropdown', DropDown);
    if (copyOffsetDropdown != null)
    {
      copyOffsetDropdown.dropdownSize = 6;
      copyOffsetDropdown.onChange = function(event:UIEvent) {
        if (!populating) copyOffsetChoice = event.data?.text;
      };
    }

    bindButton(dialog, 'copyOffsetButton', () -> copyOffsetFrom(copyOffsetChoice));

    refreshers.push(fillCopyDropdown);

    var ghostCheck = dialog.findComponent('ghostCheck', CheckBox);
    if (ghostCheck != null)
    {
      ghostCheck.onChange = function(_) {
        if (populating) return;
        showGhost(ghostCheck.selected);
      };
    }
  }

  function buildPlaytestWindow(dialog:Null<CollapsibleDialog>):Void
  {
    if (dialog == null) return;

    playtestSongDropdown = dialog.findComponent('playtestSongDropdown', DropDown);
    if (playtestSongDropdown != null)
    {
      playtestSongDropdown.dropdownSize = 8;
      playtestSongDropdown.onChange = function(event:UIEvent) {
        if (populating) return;

        var picked:Null<String> = event.data?.id;
        if (picked == null || picked == playtestSongId) return;

        playtestSongId = picked;
        fillPlaytestDifficulties();
      };
    }

    playtestDifficultyDropdown = dialog.findComponent('playtestDifficultyDropdown', DropDown);
    if (playtestDifficultyDropdown != null)
    {
      playtestDifficultyDropdown.dropdownSize = 6;
      playtestDifficultyDropdown.onChange = function(event:UIEvent) {
        if (!populating) playtestDifficulty = event.data?.text;
      };
    }

    var botCheck = dialog.findComponent('playtestBotCheck', CheckBox);
    if (botCheck != null)
    {
      botCheck.selected = playtestBotPlay;
      botCheck.onChange = function(_) {
        if (!populating) playtestBotPlay = botCheck.selected;
      };
    }

    bindButton(dialog, 'playtestButton', playtest);

    fillPlaytestSongs();
  }

  function buildNewCharacterWindow(dialog:Null<CollapsibleDialog>):Void
  {
    if (dialog == null) return;

    sheetDropdown = dialog.findComponent('sheetDropdown', DropDown);
    sheetPathLabel = dialog.findComponent('sheetPathLabel', Label);
    sheetSummaryLabel = dialog.findComponent('sheetSummaryLabel', Label);
    newCharacterStatus = dialog.findComponent('newCharacterStatus', Label);

    if (sheetDropdown != null)
    {
      sheetDropdown.dropdownSize = 6;
      sheetDropdown.onChange = function(event:UIEvent) {
        if (populating) return;
        describeSheet();
      };
    }

    bindButton(dialog, 'rescanButton', rescanSheets);

    // Asking the system for a file puts the app in the background and brings
    // it back, which is not a thing to start in the middle of handling the
    // press that asked for it.
    bindButton(dialog, 'importButton', () -> later(importSheet));
    bindButton(dialog, 'createButton', createFromSheet);
    bindButton(dialog, 'closeButton', () -> showWindow('windowNewCharacter', false));

    if (sheetPathLabel != null) sheetPathLabel.text = sheetFolder();
  }

  // -- the character ------------------------------------------------------

  // -- reading someone else's mods ----------------------------------------

  /**
   * Bring in the characters from mods kept somewhere else on the device.
   *
   * The game's own mods folder is the point of this: on a recent Android an
   * app cannot read another's storage by path, but the game publishes that
   * folder through a document provider, so the system folder picker can
   * reach it and the copy goes through the provider as well.
   */
  function loadMods():Void
  {
    say('Choose the folder your mods are in...');

    // Asked for once and kept, so that the next run can read the same folder
    // without asking again. Without this the system hands over access for as
    // long as the app is up and takes it back afterwards.
    #if android
    lime.system.System.setHint('SDL_ANDROID_ALLOW_PERSISTENT_FOLDER_ACCESS', '1');
    #end

    FileUtil.browseForDirectory('Choose a mods folder', function(folder:String) {
      later(() -> readMods(folder));
    }, function() {
      say('Nothing loaded.');
    });
  }

  /**
   * Read the mods again from wherever they were last read from.
   *
   * Runs on the way in rather than waiting to be asked: someone who has
   * already said where their mods are should not have to say it again, and a
   * mod edited since is one whose characters have changed.
   */
  function readRememberedMods():Void
  {
    #if sys
    var source:Null<String> = rememberedSource();

    if (source == null) return;

    var brought = ModImport.importFrom(source, MOD_ROOT);

    if (brought.mods.length == 0) return;

    // Everything downstream reads what Polymod found at startup, which was
    // before any of this arrived. Reloading rather than resetting the state,
    // since there is not yet a state worth keeping.
    funkin.modding.PolymodHandler.forceReloadAssets();
    #end
  }

  /**
   * The folder to read mods out of without being told.
   */
  function rememberedSource():Null<String>
  {
    #if sys
    // Wherever it was last time, which the system still lets this app reach
    // because the picker was asked for lasting access.
    if (FileUtil.fileExists(SOURCE_NOTE))
    {
      var saved:Null<String> = FileUtil.readStringFromPath(SOURCE_NOTE);

      if (saved != null && StringTools.trim(saved) != '') return StringTools.trim(saved);
    }

    // Failing that, the game's own folder, on the chance that this device
    // still allows one app to read another's. Newer ones do not, and then
    // there is nothing to do but ask.
    var beside:String = StringTools.replace(Sys.getCwd(), EDITOR_PACKAGE, GAME_PACKAGE);

    if (beside != Sys.getCwd())
    {
      var mods:String = haxe.io.Path.join([beside, 'mods']);

      try
      {
        if (sys.FileSystem.exists(mods) && sys.FileSystem.isDirectory(mods)) return mods;
      }
      catch (error)
      {
        // Not readable, which is the usual answer and not worth saying.
      }
    }
    #end

    return null;
  }

  function readMods(folder:String):Void
  {
    #if sys
    say('Reading that folder...');

    var brought = ModImport.importFrom(folder, MOD_ROOT);

    if (brought.mods.length == 0)
    {
      // What was actually in there, since a folder picker on a phone says
      // very little about where it landed and there is no other way to tell
      // a folder that held nothing from one that was never read at all.
      var sawWhat:String = brought.saw.length == 0 ? 'Saw nothing in there at all.' : 'Saw: ${brought.saw.slice(0, 6).join(', ')}';

      say('${brought.trouble.length > 0 ? brought.trouble[0] : 'Nothing to bring in.'} $sawWhat');
      return;
    }

    var trouble:String = brought.trouble.length > 0 ? ' (${brought.trouble.length} could not be read)' : '';

    say('Loading ${brought.characters} characters from ${brought.mods.join(', ')}$trouble...');

    // Worth coming back to, now that something came of it.
    FileUtil.writeStringToPath(SOURCE_NOTE, folder, Force);

    // Already done, and doing it again on the way back in would only undo
    // the reload that is about to happen.
    scannedMods = true;

    // Come back to the character that is up now, since reloading the assets
    // rebuilds this state from nothing.
    pendingCharacterId = characterId;

    later(reloadAssets);
    #else
    say('Reading mods needs a filesystem.');
    #end
  }

  // -- playtesting --------------------------------------------------------

  /**
   * Fill in the songs there are to play.
   */
  function fillPlaytestSongs():Void
  {
    if (playtestSongDropdown == null) return;

    var was = populating;
    populating = true;

    playtestSongDropdown.dataSource.clear();

    var ids:Array<String> = SongRegistry.instance.listEntryIds();
    ids.sort(SortUtil.alphabetically);

    for (id in ids)
    {
      var song:Null<Song> = SongRegistry.instance.fetchEntry(id);
      if (song == null) continue;

      // Named by the title rather than by the id, which is what anyone
      // choosing a song to watch a character in is looking for.
      playtestSongDropdown.dataSource.add({text: song.songName, id: id});
    }

    populating = was;
  }

  /**
   * Fill in the difficulties the chosen song has.
   */
  function fillPlaytestDifficulties():Void
  {
    if (playtestDifficultyDropdown == null) return;

    var was = populating;
    populating = true;

    playtestDifficultyDropdown.dataSource.clear();
    playtestDifficulty = null;

    var song:Null<Song> = playtestSongId == null ? null : SongRegistry.instance.fetchEntry(playtestSongId);
    var difficulties:Array<String> = song == null ? [] : song.listDifficulties(Constants.DEFAULT_VARIATION);

    for (difficulty in difficulties)
      playtestDifficultyDropdown.dataSource.add({text: difficulty});

    populating = was;

    // The first one, so that choosing a song and pressing play works without
    // a second choice nobody asked for.
    if (difficulties.length > 0)
    {
      playtestDifficulty = difficulties[0];
      selectInDropdown(playtestDifficultyDropdown, 0);
    }
  }

  /**
   * Drop the character into a song and watch it work.
   *
   * The song plays as a substate over the editor, so that closing it comes
   * straight back here with everything as it was left -- which matters,
   * since the offsets being checked have not been written down anywhere yet.
   */
  function playtest():Void
  {
    if (data == null || character == null)
    {
      say('Nothing to play.');
      return;
    }

    if (playtestSongId == null)
    {
      say('Pick a song first.');
      return;
    }

    var song:Null<Song> = SongRegistry.instance.fetchEntry(playtestSongId);

    if (song == null)
    {
      say('Could not load $playtestSongId.');
      return;
    }

    var difficultyId:Null<String> = playtestDifficulty ?? song.listDifficulties(Constants.DEFAULT_VARIATION)[0];
    var difficulty:Null<SongDifficulty> = difficultyId == null ? null : song.getDifficulty(difficultyId, Constants.DEFAULT_VARIATION);

    if (difficulty == null || difficulty.characters == null)
    {
      say('${song.songName} has nothing to play on $difficultyId.');
      return;
    }

    // The character is built from the file, and the offsets being tested are
    // still only on the sprite.
    harvestOffsets();

    var characters = difficulty.characters;

    playtestOverride =
      {
        characters: characters,
        player: characters.player,
        girlfriend: characters.girlfriend,
        opponent: characters.opponent,
        playerVocals: characters.playerVocals,
        opponentVocals: characters.opponentVocals
      };

    // A song with no list of its own works out which voice track belongs to
    // a side from whoever is standing in it, and there is no voice track
    // named after the character being edited -- so that side would come out
    // silent. Writing down who was standing there keeps its voice.
    switch (characterType)
    {
      case DAD:
        characters.opponentVocals = characters.opponentVocals ?? [characters.opponent];
        characters.opponent = characterId;
      case GF:
        characters.girlfriend = characterId;
      default:
        characters.playerVocals = characters.playerVocals ?? [characters.player];
        characters.player = characterId;
    }

    playtestAnimation = animationName;

    // The registry hands out one stage per id and the song is about to ask
    // for the same one this is standing on, which it would then fill with
    // its own characters and destroy on the way out.
    clearCharacter();

    // Put the windows away rather than only stopping them being drawn: they
    // belong to the toolkit rather than to this state, and one left up but
    // invisible would still be taking the taps that land on top of it.
    playtestWindows = [];
    for (id in windows.keys())
    {
      var window = windows.get(id);
      if (window != null && window.shown)
      {
        playtestWindows.push(id);
        showWindow(id, false);
      }
    }

    if (menubar != null) menubar.hidden = true;

    // The rest of the editor is drawn by this state, which stands down while
    // the song is up.
    persistentUpdate = false;
    persistentDraw = false;

    // A song resets the camera list, and resetting it destroys whatever was
    // in it -- so the editor's cameras come out of the list, rather than
    // being handed over to be thrown away. Named one by one rather than
    // taken off the list wholesale, so that nothing else's camera is carried
    // off with them.
    playtestCameras = [];

    var mine:Array<Null<flixel.FlxCamera>> = [FlxG.camera, camStage, camUI, camControls];

    for (cam in mine)
    {
      if (cam == null || playtestCameras.indexOf(cam) != -1) continue;
      if (FlxG.cameras.list.indexOf(cam) == -1) continue;

      playtestCameras.push(cam);
      FlxG.cameras.remove(cam, false);
    }

    // Something to be looking through in the meantime: an empty list leaves
    // the game with no camera at all, which is not a state anything between
    // here and the song's own cameras expects to be asked about. This one is
    // the song's to destroy when it resets the list itself.
    FlxG.cameras.reset(new FunkinCamera('charEditorPlaytest'));

    PlayStatePlaylist.reset();

    subStateClosed.add(afterPlaytest);

    LoadingState.loadPlayState(
      {
        targetSong: song,
        targetDifficulty: difficultyId,
        targetVariation: Constants.DEFAULT_VARIATION,
        botPlayMode: playtestBotPlay,
        // Nothing about a playtest should reach the save file, and dying
        // partway through a character's animations helps nobody.
        practiceMode: true
      }, false, true);
  }

  /**
   * Pick the editor back up after a playtest.
   */
  function afterPlaytest(_:flixel.FlxSubState):Void
  {
    subStateClosed.remove(afterPlaytest);

    if (playtestOverride != null)
    {
      var was = playtestOverride;
      was.characters.player = was.player;
      was.characters.girlfriend = was.girlfriend;
      was.characters.opponent = was.opponent;
      was.characters.playerVocals = was.playerVocals;
      was.characters.opponentVocals = was.opponentVocals;

      playtestOverride = null;
    }

    // The song pointed the asset paths at its own level on the way in.
    Paths.setCurrentLevel(null);

    // The editor's cameras go back, in the order they were in, in place of
    // the song's -- which resetting the list destroys, as it did to these on
    // the way in. This has to come before anything that draws or is placed,
    // since all of that names a camera.
    if (playtestCameras.length > 0)
    {
      FlxG.cameras.reset(playtestCameras[0]);
      playtestCameras[0].onResize();

      for (i in 1...playtestCameras.length)
      {
        FlxG.cameras.add(playtestCameras[i], false);
        playtestCameras[i].onResize();
      }

      playtestCameras = [];
    }

    persistentUpdate = true;
    persistentDraw = true;

    if (menubar != null) menubar.hidden = false;

    for (id in playtestWindows)
      showWindow(id, true);

    playtestWindows = [];

    FlxG.sound.music?.stop();

    // Built again from the file, which is where the offsets were put before
    // the song took the character away.
    loadCharacter(characterId, true);

    if (playtestAnimation != '' && animationNames.indexOf(playtestAnimation) != -1)
    {
      playAnimation(playtestAnimation);
      selectInDropdown(animationDropdown, animationNames.indexOf(playtestAnimation));
    }

    say('Back from the playtest.');
  }

  /**
   * Take the character, and whatever it is standing on, back off the screen.
   *
   * The stage owns what it was given and destroys it as it goes, so a
   * character standing on one is not the editor's to take down. One with no
   * stage under it is.
   */
  function clearCharacter():Void
  {
    showGhost(false);

    if (stage != null)
    {
      unloadStage();
    }
    else if (character != null)
    {
      remove(character);
      character.destroy();
    }

    character = null;
  }

  /**
   * @param force Load it again even if it is the one already up, for when
   *   something other than which character it is has changed.
   */
  function loadCharacter(id:Null<String>, force:Bool = false):Void
  {
    if (id == null || id == '')
    {
      say('No character to load.');
      return;
    }

    // Rebuilding the character and the stage is not cheap, and being asked
    // for the one already standing there is a thing that happens: a control
    // reporting the value it was just given reads no differently from a
    // person choosing it.
    if (!force && id == characterId && character != null) return;

    clearCharacter();

    characterId = id;
    data = CharacterDataParser.fetchCharacterData(id);

    if (data == null)
    {
      say('Could not load $id.');
      return;
    }

    // The stage first, while there is no character for taking it down to
    // throw away by accident.
    loadStage();

    character = CharacterDataParser.fetchCharacter(id, true);

    if (character == null)
    {
      say('Could not build $id.');
      return;
    }

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

    // The history is a list of animation names and numbers, and neither
    // belongs to this character.
    offsetHistory = [];

    lookAtCharacter();
    refreshBackdrop();

    if (characterNameLabel != null) characterNameLabel.text = '${data.name} [$characterId]';
    if (characterSlotLabel != null) characterSlotLabel.text = slotName();

    fillAnimationDropdown();

    if (animationNames.length > 0)
    {
      // Named on the control as well as played, or the dropdown sits blank
      // over an animation that is running.
      selectInDropdown(animationDropdown, 0);
      playAnimation(animationNames[0]);
    }

    refreshWindows();

    say('Loaded $id.');

    reportMissingArt();
  }

  /**
   * Say why a character came up with nothing to show.
   *
   * A character whose sheet did not load is not an error anywhere — the
   * sprite is simply built with no frames and draws nothing, which on a
   * stage looks the same as a character that is there but invisible. Since
   * the usual cause is a sheet the game cannot find, this says which files
   * were looked for and whether they were there.
   */
  function reportMissingArt():Void
  {
    if (character == null || data == null) return;
    if (character.frames != null && character.frames.frames.length > 0) return;

    var image:String = Paths.image(data.assetPath);
    var description:String = Paths.file('images/${data.assetPath}.xml');

    var haveImage:Bool = openfl.utils.Assets.exists(image);
    var haveDescription:Bool = openfl.utils.Assets.exists(description);

    say('No art for $characterId. image ${haveImage ? "ok" : "MISSING"} ($image), xml ${haveDescription ? "ok" : "MISSING"} ($description)');
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
   * Left until the next frame on purpose. Most of the calls to this come,
   * one way or another, from a dropdown's own change handler, which HaxeUI
   * runs in the middle of validating that dropdown; writing to it there is
   * changing a component while it is being validated, which the toolkit
   * catches as a possible infinite loop and turns into a crash.
   */
  function selectInDropdown(dropdown:Null<DropDown>, index:Int):Void
  {
    if (dropdown == null || index < 0) return;

    haxe.ui.Toolkit.callLater(function() {
      // The editor may be long gone by now: importing a sheet reloads the
      // assets, which rebuilds the state, and anything left over from the
      // old one is pointing at components that were thrown away with it.
      if (FlxG.state != this) return;

      populating = true;

      // A dropdown whose rows were swapped out under it keeps the index it
      // had and decides nothing has changed, and comes up blank. Standing it
      // down first makes the assignment land.
      if (dropdown.selectedIndex == index) dropdown.selectedIndex = -1;

      dropdown.selectedIndex = index;

      populating = false;
    });
  }

  function playAnimation(name:Null<String>):Void
  {
    if (character == null || name == null || name == '') return;

    animationName = name;
    character.playAnimation(name, true);

    refreshAnimationWarning();

    // The animation window is showing one animation's worth of the file, and
    // which animation that is has just changed.
    refreshWindows();
  }

  // -- adding, renaming and removing animations ---------------------------

  /**
   * Take an animation off the character.
   *
   * Removing an animation destroys it, and the controller goes on pointing
   * at whatever it was playing -- so removing the one that is playing leaves
   * it holding a destroyed animation, which is a crash on the next frame
   * rather than an error here. Standing it down first is what avoids that.
   */
  function dropAnimation(name:String):Void
  {
    if (character == null) return;

    if (character.animation.curAnim != null && character.animation.curAnim.name == name) character.animation.curAnim = null;

    character.animation.remove(name);
  }

  /**
   * Build one animation again from what the file now says.
   *
   * The sprite turns the file's animations into frames once, when it is
   * made, so a prefix or a list of frames changed afterwards means nothing
   * until the animation is put together again. Taking the old one off first
   * because adding over the top of a name that is already there does not
   * replace it.
   */
  function rebuildAnimation(entry:AnimationData):Void
  {
    if (character == null) return;

    var offsets = character.animationOffsets.get(entry.name);

    if (character.isAnimate)
    {
      // An Animate atlas character's animations are cut out of the atlas's
      // own frame labels rather than out of a sheet, and the two are not
      // interchangeable: handing one a sheet animation adds nothing at all.
      // Adding over the name is how this one is replaced, so the old one is
      // not taken off first.
      FlxAnimationUtil.addTextureAtlasAnimation(character, entry);
    }
    else
    {
      // Taking the old one off first, because adding over a name that is
      // already there does not replace it.
      dropAnimation(entry.name);
      FlxAnimationUtil.addAtlasAnimation(character, entry);
    }

    // Rebuilding loses the offsets, which live on the sprite rather than in
    // the animation, so they go back on afterwards.
    if (offsets != null) character.setAnimationOffsets(entry.name, offsets[0], offsets[1]);

    if (entry.name == animationName && character != null)
    {
      character.playAnimation(entry.name, true);
      refreshAnimationWarning();
    }
  }

  /**
   * Add an animation the sheet has frames for but the file does not mention.
   *
   * The guess made when a character is built from a sheet will not always
   * find everything, and a character missing `singRIGHT` is a character that
   * does not work in a song, so there has to be a way to add one by hand.
   */
  function addAnimation():Void
  {
    if (data == null) return;

    var name:String = unusedAnimationName('newAnimation');

    var entry:AnimationData =
      {
        name: name,
        prefix: '',
        offsets: [0.0, 0.0],
        looped: false,
        flipX: false,
        flipY: false,
        frameRate: 24,
        frameIndices: []
      };

    data.animations.push(entry);
    animationNames.push(name);
    animationName = name;

    if (character != null) character.setAnimationOffsets(name, 0, 0);

    fillAnimationDropdown();
    selectInDropdown(animationDropdown, animationNames.indexOf(name));
    refreshWindows();

    say('Added $name. Give it a prefix from the sheet.');
  }

  function deleteAnimation():Void
  {
    if (data == null || animationName == '') return;

    var entry = currentAnimation();
    if (entry == null) return;

    var going:String = entry.name;

    data.animations.remove(entry);
    animationNames.remove(going);
    offsetHistory = offsetHistory.filter(edit -> edit.animation != going);
    if (character != null)
    {
      dropAnimation(going);
      character.animationOffsets.remove(going);
    }

    animationName = animationNames.length > 0 ? animationNames[0] : '';

    fillAnimationDropdown();

    if (animationName != '')
    {
      selectInDropdown(animationDropdown, 0);
      playAnimation(animationName);
    }

    refreshWindows();

    say('Removed $going.');
  }

  /**
   * Give an animation a different name.
   *
   * The name is what the game asks for — `idle`, `singLEFT` — so getting it
   * right is the difference between a character that works and one that
   * stands still. It is also the key the offsets are filed under, in two
   * places, both of which have to move with it.
   */
  function renameAnimation(to:String):Void
  {
    if (data == null) return;

    var entry = currentAnimation();
    if (entry == null || to == '' || to == entry.name) return;

    if (animationNames.indexOf(to) != -1)
    {
      say('There is already an animation called $to.');
      return;
    }

    var from:String = entry.name;
    var offsets = character == null ? null : character.animationOffsets.get(from);

    entry.name = to;
    animationNames[animationNames.indexOf(from)] = to;
    animationName = to;

    // The history files its entries under the name too, so it moves as well
    // rather than pointing at an animation that no longer exists.
    for (edit in offsetHistory)
      if (edit.animation == from) edit.animation = to;

    if (character != null)
    {
      dropAnimation(from);
      character.animationOffsets.remove(from);

      FlxAnimationUtil.addAtlasAnimation(character, entry);
      if (offsets != null) character.setAnimationOffsets(to, offsets[0], offsets[1]);
    }

    fillAnimationDropdown();
    selectInDropdown(animationDropdown, animationNames.indexOf(to));
    playAnimation(to);

    say('Renamed $from to $to.');
  }

  function unusedAnimationName(wanted:String):String
  {
    if (animationNames.indexOf(wanted) == -1) return wanted;

    var attempt:Int = 2;
    while (animationNames.indexOf('$wanted$attempt') != -1)
      attempt++;

    return '$wanted$attempt';
  }

  /**
   * The frames an animation uses, as something a person can type.
   */
  static function describeIndices(indices:Null<Array<Int>>):String
  {
    if (indices == null || indices.length == 0) return '';

    return indices.join(', ');
  }

  static function readIndices(value:String):Array<Int>
  {
    var indices:Array<Int> = [];

    for (piece in value.split(','))
    {
      var number = Std.parseInt(StringTools.trim(piece));
      if (number != null) indices.push(number);
    }

    return indices;
  }

  /**
   * Push the current animation's settings onto the one that is playing.
   *
   * The sprite reads these once, when its animations are built out of the
   * file, so changing the frame rate afterwards changed a number nothing was
   * looking at any more and the animation carried on at whatever speed it
   * started at. These are the four that can be changed without rebuilding
   * the animation from its frames.
   */
  function applyAnimationSettings():Void
  {
    if (character == null || animationName == '') return;

    var settings = currentAnimation();
    if (settings == null) return;

    var playing = character.animation.getByName(animationName);
    if (playing == null) return;

    playing.frameRate = settings.frameRate ?? 24;
    playing.looped = settings.looped ?? false;
    playing.flipX = settings.flipX ?? false;
    playing.flipY = settings.flipY ?? false;
  }

  /**
   * An animation whose prefix is not in the sprite sheet plays nothing, and
   * that is the most common thing wrong with a character file, so say so
   * rather than leaving it to be discovered.
   */
  function refreshAnimationWarning():Void
  {
    if (animationWarning == null || character == null) return;

    animationWarning.text = character.hasAnimation(animationName) ? '' : 'No frames for this prefix';
  }

  function resetOffset():Void
  {
    recordOffset();
    setOffset(0, 0);
    say('Offset cleared for $animationName.');
  }

  /**
   * Write down where the current animation sits, before something moves it.
   *
   * A drag records once, when the finger goes down, rather than on every
   * frame it moves through: taking one back should put the character where
   * it stood before the drag, not a pixel back along it.
   */
  function recordOffset():Void
  {
    if (character == null || animationName == '') return;

    var offset = currentOffset();

    // An edit that changed nothing -- clearing an offset that is already
    // clear, say -- would otherwise become an undo that appears to do
    // nothing, and the one before it would need pressing twice.
    var last = offsetHistory[offsetHistory.length - 1];
    if (last != null && last.animation == animationName && last.x == offset[0] && last.y == offset[1]) return;

    offsetHistory.push({animation: animationName, x: offset[0], y: offset[1]});

    // Far more than anyone will walk back, and small enough to be free.
    if (offsetHistory.length > UNDO_DEPTH) offsetHistory.shift();
  }

  /**
   * Put the last offset that moved back where it was.
   *
   * The animation it belongs to is shown again on the way, since an offset
   * changing on an animation you cannot see would look like nothing
   * happening at all.
   */
  function undoOffset():Void
  {
    if (character == null) return;

    var last = offsetHistory.pop();

    if (last == null)
    {
      say('Nothing to undo.');
      return;
    }

    if (last.animation != animationName)
    {
      playAnimation(last.animation);
      selectInDropdown(animationDropdown, animationNames.indexOf(last.animation));
    }

    // Straight to the sprite rather than through setOffset, which would
    // record this as one more thing to undo and never let the stack empty.
    character.animOffsets = [last.x, last.y];
    character.setAnimationOffsets(last.animation, last.x, last.y);

    refreshOffsetLabel();
    say('Put ${last.animation} back to ${Std.int(last.x)}, ${Std.int(last.y)}.');
  }

  /**
   * Take another animation's offset for this one.
   *
   * Most of a character's animations are drawn from the same place on the
   * sheet, so once one of them sits right the rest usually want the same
   * numbers rather than the same guesswork again.
   */
  function copyOffsetFrom(name:Null<String>):Void
  {
    if (character == null || name == null || name == '') return;

    if (name == animationName)
    {
      say('That is the animation you are on.');
      return;
    }

    var source = character.animationOffsets.get(name);

    if (source == null)
    {
      say('$name has no offset to copy.');
      return;
    }

    recordOffset();
    setOffset(source[0], source[1]);
    say('Took ${animationName}\'s offset from $name.');
  }

  /**
   * Fill the list of animations an offset can be taken from.
   *
   * Everything but the animation being edited, which has nothing to give
   * itself.
   */
  function fillCopyDropdown():Void
  {
    if (copyOffsetDropdown == null) return;

    // Put the flag back rather than down: this runs as one of the refreshers,
    // which are all run with it up, and the ones after it still need it.
    var was = populating;
    populating = true;

    copyOffsetDropdown.dataSource.clear();

    for (name in animationNames)
      if (name != animationName) copyOffsetDropdown.dataSource.add({text: name});

    copyOffsetDropdown.selectedIndex = -1;
    copyOffsetChoice = null;
    populating = was;
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

  /**
   * Show where the current animation sits.
   *
   * Its own function rather than part of the general refresh because it runs
   * while a finger is dragging the character, many times a second.
   */
  function refreshOffsetLabel():Void
  {
    var offset = currentOffset();

    if (offsetLabel != null) offsetLabel.text = '${Std.int(offset[0])}, ${Std.int(offset[1])}';

    populating = true;

    if (animOffsetX != null) animOffsetX.pos = offset[0];
    if (animOffsetY != null) animOffsetY.pos = offset[1];

    populating = false;
  }

  /**
   * Point the character the way its file says to.
   *
   * A character standing in the boyfriend slot is drawn mirrored: the sheets
   * all face the way the opponent stands, and `flipX` in the file is written
   * against that. The stage applies the flip when it takes a character, so
   * setting the sprite straight from the file cancels it out.
   *
   * @param fromData Take the value from the file rather than from whatever
   *   the control last said, for when a character has just been loaded.
   */
  function applyFlipX(fromData:Bool = false):Void
  {
    if (data == null) return;

    var flipped:Bool = data.flipX ?? false;

    // Mirrored for boyfriend, but only once it is actually on a stage; on its
    // own the character wears the file's value as it is.
    if (stage != null && characterType == BF) flipped = !flipped;

    if (character != null) character.flipX = flipped;
  }

  /**
   * Leave a copy of the character where it stands, or take it away again.
   *
   * The copy is drawn where the character is being drawn now — which is not
   * where the character *is*, since the offsets move it at draw time — so
   * the sum is done here once rather than being carried by a sprite that
   * does not know about offsets.
   */
  function showGhost(on:Bool):Void
  {
    if (ghost != null)
    {
      remove(ghost);
      ghost.destroy();
      ghost = null;
    }

    if (!on || character == null) return;

    // A character of its own rather than a sprite wearing the same graphic:
    // an Animate atlas character is drawn from a timeline that only its own
    // class knows how to play, and a plain sprite handed those frames shows
    // whatever happens to be first in the file.
    var copy:Null<BaseCharacter> = CharacterDataParser.fetchCharacter(characterId, true);

    if (copy == null)
    {
      say('Could not make a ghost of $characterId.');
      return;
    }

    copy.flipX = character.flipX;
    copy.alpha = 0.4;
    copy.cameras = [camStage];

    if (animationName != '')
    {
      copy.playAnimation(animationName, true);

      // The end of the animation rather than the start of it: where a
      // character finishes is what has to line up, and the first frame of a
      // sing is usually the idle it grew out of.
      copy.animation.finish();
      copy.animation.pause();
    }

    // Drawn exactly where it is put. A character moves itself by its offsets
    // as it draws, and where it is being put is that sum already.
    copy.animOffsets = [0, 0];
    copy.globalOffsets = [0, 0];
    if (animationName != '') copy.setAnimationOffsets(animationName, 0, 0);

    var corner = drawnCorner();
    copy.setPosition(corner.x, corner.y);
    corner.put();

    // Frozen on the frame it was left on: nothing here should carry it on.
    copy.active = false;

    // Over the character rather than under it: at this alpha the one you are
    // dragging still reads as the solid one, and a ghost hidden behind the
    // character would be no use at all.
    ghost = copy;
    add(ghost);
  }

  function say(message:String):Void
  {
    if (statusLabel != null) statusLabel.text = message;
    if (statusText != null) statusText.text = message;
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

    bg.visible = stage == null;
  }

  /**
   * Put the green on a sprite. Idempotent, since it is measured from the
   * graphic's own size rather than from whatever size the sprite is now.
   */
  function styleBackdrop(sprite:FlxSprite):Void
  {
    sprite.loadGraphic(Paths.image('menuDesat'));
    sprite.color = 0xFF4CAF50;
    sprite.setGraphicSize(Std.int(sprite.frameWidth * 1.1 * FullScreenScaleMode.wideScale.x));
    sprite.updateHitbox();
    sprite.screenCenter();
    sprite.scrollFactor.set(0, 0);
  }

  // -- exporting ----------------------------------------------------------

  /**
   * Put the character into a mod.
   *
   * A character is two things that have to agree with each other: a file
   * saying what it is, and the sheet it is drawn from. Handing over only the
   * file, as this used to, gave someone half a character and a path pointing
   * at a folder inside this app that nothing else can see.
   *
   * So it asks for a mod folder and puts both parts where that mod keeps
   * them — the file under `data/characters`, the sheet under
   * `shared/images/characters` — and rewrites the path between them to match
   * where the sheet has landed.
   */
  function exportCharacter():Void
  {
    if (data == null || character == null)
    {
      say('Nothing to export.');
      return;
    }

    harvestOffsets();

    say('Choose the mod to put $characterId into...');

    FileUtil.browseForDirectory('Choose a mod folder', function(folder:String) {
      later(() -> exportInto(folder));
    }, function() {
      say('Export cancelled.');
    });
  }

  /**
   * Put the offsets back into the file.
   *
   * The sprite carries them while they are being dragged, since that is what
   * draws with them, so anything that reads the file rather than the sprite
   * -- writing it out, or building the character again for a playtest --
   * has to collect them first.
   */
  function harvestOffsets():Void
  {
    if (data == null || character == null) return;

    for (animation in data.animations)
    {
      var offsets = character.animationOffsets.get(animation.name);
      if (offsets != null) animation.offsets = [offsets[0], offsets[1]];
    }
  }

  function exportInto(folder:String):Void
  {
    #if sys
    if (data == null)
    {
      say('Nothing to export.');
      return;
    }

    var sheet:String = sheetFileName(data.assetPath);

    // A copy, because the path only changes for the exported file: the
    // character on screen is still being drawn from where it came from.
    var exported:Dynamic = haxe.Json.parse(haxe.Json.stringify(data));
    exported.assetPath = 'shared:characters/$sheet';

    var staging:String = '$MOD_ROOT/$MOD_ID/export';

    try
    {
      makeModDirs();
      FileUtil.createDirIfNotExists(staging);
      FileUtil.writeStringToPath('$staging/$characterId.json', haxe.Json.stringify(exported, null, '  '), Force);
    }
    catch (error)
    {
      say('Could not prepare the export: $error');
      return;
    }

    var placed:Int = 0;
    if (placeInMod(folder, 'data/characters/$characterId.json', '$staging/$characterId.json')) placed++;

    // The sheet comes out of the asset system rather than off the disk,
    // which is the only way to reach one that came with the game rather than
    // having been imported.
    if (stageSheet(staging, sheet))
    {
      if (placeInMod(folder, 'shared/images/characters/$sheet.png', '$staging/$sheet.png')) placed++;
      if (placeInMod(folder, 'shared/images/characters/$sheet.xml', '$staging/$sheet.xml')) placed++;
    }

    if (placed == 0)
    {
      say('Could not write into that folder.');
      return;
    }

    say(placed >= 3 ? 'Exported $characterId and its sheet.' : 'Exported $characterId. The sheet could not be copied; put it in shared/images/characters yourself.');
    #else
    say('Exporting needs a filesystem.');
    #end
  }

  /**
   * Write the character's sheet out where it can be copied from.
   */
  function stageSheet(staging:String, sheet:String):Bool
  {
    #if sys
    if (data == null) return false;

    var imageId:String = Paths.image(data.assetPath);
    var describedId:String = Paths.file('images/${data.assetPath}.xml');

    if (!openfl.utils.Assets.exists(imageId) || !openfl.utils.Assets.exists(describedId)) return false;

    try
    {
      var image:haxe.io.Bytes = openfl.utils.Assets.getBytes(imageId);
      if (image == null) return false;

      FileUtil.writeBytesToPath('$staging/$sheet.png', lime.utils.Bytes.fromBytes(image), Force);
      FileUtil.writeStringToPath('$staging/$sheet.xml', openfl.utils.Assets.getText(describedId), Force);

      return true;
    }
    catch (error)
    {
      return false;
    }
    #else
    return false;
    #end
  }

  /**
   * Put one file inside the chosen mod folder.
   *
   * On Android the folder is not a path — the picker hands back a tree URI,
   * and writing inside one means asking the document provider to make each
   * directory and file. Everywhere else it is a path and this is a copy.
   */
  function placeInMod(folder:String, relativePath:String, sourcePath:String):Bool
  {
    #if android
    if (StringTools.startsWith(folder, 'content://'))
    {
      return funkin.external.android.ModFolderUtil.copyInto(folder, relativePath, sourcePath);
    }
    #end

    #if sys
    try
    {
      var target:String = haxe.io.Path.join([folder, relativePath]);
      var directory:String = haxe.io.Path.directory(target);

      // A level at a time, since createDirIfNotExists does not make a whole
      // branch. Rooted paths keep their leading slash, which splitting on it
      // would otherwise drop.
      var walked:String = StringTools.startsWith(directory, '/') ? '/' : '';

      for (piece in directory.split('/'))
      {
        if (piece == '') continue;

        walked = (walked == '' || walked == '/') ? walked + piece : '$walked/$piece';
        FileUtil.createDirIfNotExists(walked);
      }

      FileUtil.writeBytesToPath(target, FileUtil.readBytesFromPath(sourcePath), Force);

      return true;
    }
    catch (error)
    {
      return false;
    }
    #else
    return false;
    #end
  }

  /**
   * The name of the sheet an asset path points at, without the library it
   * lives in or the folders above it.
   */
  static function sheetFileName(assetPath:String):String
  {
    var withoutLibrary:String = assetPath.indexOf(':') == -1 ? assetPath : assetPath.substr(assetPath.indexOf(':') + 1);

    return haxe.io.Path.withoutDirectory(withoutLibrary);
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
    unloadStage();

    stage = StageRegistry.instance.fetchEntry(STAGE_ID);

    if (stage == null) return;

    stage.revive();
    ScriptEventDispatcher.callEvent(stage, new ScriptEvent(CREATE, false));

    stage.cameras = [camStage];
    add(stage);
  }

  /**
   * Put the stage away.
   *
   * The registry hands out one stage and hands out the same one every time,
   * so a stage that is merely dropped and fetched again is the same object
   * with everything still on it — and building it once more builds a second
   * set of props on top of the first, and a third, until the frame rate says
   * so. Destroying it is what empties it, and takes whatever was standing on
   * it along too.
   */
  function unloadStage():Void
  {
    if (stage == null) return;

    ScriptEventDispatcher.callEvent(stage, new ScriptEvent(DESTROY, false));
    remove(stage);
    stage.kill();
    stage = null;

    // Destroyed along with the stage it was standing on.
    character = null;
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


  // -- making a character out of a sprite sheet ---------------------------

  /**
   * Where to tell someone to put a sheet.
   *
   * Absolute, because a relative path is no help at all to a person holding
   * a phone and a file manager.
   */
  function sheetFolder():String
  {
    #if sys
    try
    {
      return haxe.io.Path.join([Sys.getCwd(), SHEET_DIR]);
    }
    catch (error)
    {
      return SHEET_DIR;
    }
    #else
    return SHEET_DIR;
    #end
  }

  /**
   * Look again at what is in the folder.
   */
  function rescanSheets():Void
  {
    sheetNames = SpriteSheetImport.listSheets(SHEET_DIR);

    if (sheetDropdown != null)
    {
      populating = true;
      sheetDropdown.dataSource.clear();

      for (name in sheetNames)
        sheetDropdown.dataSource.add({text: name});

      populating = false;

      if (sheetNames.length > 0) selectInDropdown(sheetDropdown, 0);
    }

    if (sheetNames.length == 0)
    {
      if (sheetSummaryLabel != null) sheetSummaryLabel.text = '';
      sayNew('Nothing here yet. Import one, or drop a .png and a .xml of the same name into the folder above.');
      return;
    }

    sayNew('Found ${sheetNames.length} sheet${sheetNames.length == 1 ? "" : "s"}.');
    describeSheet();
  }

  /**
   * Say what is in the chosen sheet before anything is made from it.
   */
  function describeSheet():Void
  {
    if (sheetSummaryLabel == null) return;

    var sheet:Null<String> = chosenSheet();

    if (sheet == null)
    {
      sheetSummaryLabel.text = '';
      return;
    }

    var prefixes:Array<String> = SpriteSheetImport.readPrefixes('$SHEET_DIR/$sheet.xml');

    sheetSummaryLabel.text = prefixes.length == 0 ? 'No frames found in $sheet.xml' : '${prefixes.length} animations';
  }

  function chosenSheet():Null<String>
  {
    if (sheetDropdown == null) return null;

    var index:Int = sheetDropdown.selectedIndex;
    if (index < 0 || index >= sheetNames.length) return null;

    return sheetNames[index];
  }

  /**
   * Build a character from a sheet and open it, without writing it anywhere.
   *
   * The sheet itself is already a file — it has to be, or nothing could load
   * the image — but the character is only ever in memory until File > Export
   * says where it goes. The reload is for the sheet: the game only knows
   * about files it has looked at, and it looked before this one existed.
   */
  function createFromSheet():Void
  {
    #if sys
    var sheet:Null<String> = chosenSheet();

    if (sheet == null)
    {
      sayNew('Pick a sheet first.');
      return;
    }

    var prefixes:Array<String> = SpriteSheetImport.readPrefixes('$SHEET_DIR/$sheet.xml');

    if (prefixes.length == 0)
    {
      sayNew('No frames found in $sheet.xml.');
      return;
    }

    var id:String = SpriteSheetImport.uniqueId(sheet, CharacterDataParser.listCharacterIds());

    pendingCharacterId = id;
    pendingCharacterJson = SpriteSheetImport.buildCharacterJson(id, sheet, 'characters/$sheet', prefixes);

    sayNew('Loading $id...');
    later(reloadAssets);
    #else
    sayNew('Making characters needs a filesystem.');
    #end
  }

  function sayNew(message:String):Void
  {
    if (newCharacterStatus != null) newCharacterStatus.text = message;
  }
  /**
   * Bring a sheet in from wherever it is on the phone.
   *
   * The folder this editor reads is one it can be sure of, which is why it
   * reads a folder — but getting a file into that folder otherwise means a
   * cable or a file manager that can see into the app's own storage, and on
   * a recent Android that second one is not a given. This asks the system
   * for the file instead, and puts it in the folder itself.
   *
   * A Sparrow sheet is two files, so it asks twice.
   */
  function importSheet():Void
  {
    #if sys
    sayNew('Choose the image...');

    FileUtil.browseForFile('Choose a sprite sheet image', [FileUtil.FILE_FILTER_PNG], function(image:SelectedFileData) {
      if (image?.bytes == null)
      {
        sayNew('Could not read that image.');
        return;
      }

      var name:String = sheetNameOf(image);
      sayNew('Now choose $name.xml...');

      FileUtil.browseForFile('Choose the matching .xml', [FileUtil.FILE_FILTER_XML], function(description:SelectedFileData) {
        if (description?.bytes == null)
        {
          sayNew('Could not read that .xml.');
          return;
        }

        writeSheet(name, image.bytes, description.bytes);
      }, function() sayNew('Cancelled — a sheet needs its .xml too.'));
    }, function() sayNew('Cancelled.'));
    #else
    sayNew('Importing needs a filesystem.');
    #end
  }

  /**
   * Put both halves of a sheet in the folder and pick it.
   */
  function writeSheet(name:String, image:lime.utils.Bytes, description:lime.utils.Bytes):Void
  {
    #if sys
    try
    {
      makeModDirs();
      FileUtil.writeBytesToPath('$SHEET_DIR/$name.png', image, Force);
      FileUtil.writeBytesToPath('$SHEET_DIR/$name.xml', description, Force);
    }
    catch (error)
    {
      sayNew('Could not save the sheet: $error');
      return;
    }

    rescanSheets();

    var index:Int = sheetNames.indexOf(name);
    if (index >= 0) selectInDropdown(sheetDropdown, index);

    sayNew('Brought in $name.');
    #end
  }

  /**
   * What to call a sheet the system handed over.
   *
   * Android answers a file request with a `content://` URI rather than a
   * path, and the readable name is the last part of it with the separators
   * written as escapes, so it needs unpicking before it can be a file name
   * again.
   */
  function sheetNameOf(file:SelectedFileData):String
  {
    var raw:String = decodePercent(file.fullPath ?? file.name ?? 'sheet');

    for (separator in ['/', ':', '\\'])
    {
      var at:Int = raw.lastIndexOf(separator);
      if (at != -1) raw = raw.substr(at + 1);
    }

    var dot:Int = raw.lastIndexOf('.');
    if (dot > 0) raw = raw.substr(0, dot);

    var cleaned:StringBuf = new StringBuf();
    for (index in 0...raw.length)
    {
      var code:Int = StringTools.fastCodeAt(raw, index);
      var safe:Bool = (code >= 'a'.code && code <= 'z'.code)
        || (code >= 'A'.code && code <= 'Z'.code)
        || (code >= '0'.code && code <= '9'.code)
        || code == '-'.code
        || code == '_'.code;

      if (safe) cleaned.addChar(code);
    }

    var name:String = cleaned.toString();
    return name == '' ? 'sheet' : name;
  }

  /**
   * `%2F` and friends back into the characters they stand for.
   *
   * Not `StringTools.urlDecode`, which also reads `+` as a space and would
   * quietly rename a file that has one in it.
   */
  function decodePercent(value:String):String
  {
    var out:StringBuf = new StringBuf();
    var index:Int = 0;

    while (index < value.length)
    {
      var code:Int = StringTools.fastCodeAt(value, index);

      if (code == '%'.code && index + 2 < value.length)
      {
        var digits:Null<Int> = Std.parseInt('0x' + value.substr(index + 1, 2));

        if (digits != null)
        {
          out.addChar(digits);
          index += 3;
          continue;
        }
      }

      out.addChar(code);
      index++;
    }

    return out.toString();
  }

  /**
   * Make sure the editor's own mod is a mod.
   *
   * The folders are the easy half. The other half is the metadata file:
   * without one, the scan that finds mods skips the folder entirely and
   * everything in it — a sprite sheet included — is not an asset as far as
   * the game is concerned, which looks exactly like a character whose art
   * failed to load.
   */
  function makeModDirs():Void
  {
    #if sys
    var root:String = '$MOD_ROOT/$MOD_ID';

    FileUtil.createDirIfNotExists(MOD_ROOT);
    FileUtil.createDirIfNotExists(root);
    FileUtil.createDirIfNotExists('$root/data');
    FileUtil.createDirIfNotExists('$root/data/characters');
    FileUtil.createDirIfNotExists('$root/images');
    FileUtil.createDirIfNotExists('$root/images/characters');

    // Left alone if it is already there, in case it has been edited.
    var meta:String = haxe.io.Path.join([root, polymod.PolymodConfig.modMetadataFile]);
    if (!FileUtil.fileExists(meta)) FileUtil.writeStringToPath(meta, modMeta(), Force);
    #end
  }

  /**
   * What makes the folder a mod.
   *
   * `api_version` has to satisfy the game's own rule or the scan skips the
   * folder with a warning, exactly as if the file were not there — so it is
   * taken from the rule rather than picked.
   */
  function modMeta():String
  {
    return haxe.Json.stringify({
      title: "Editor",
      description: "Sprite sheets brought into the character editor.",
      contributors: [],
      api_version: "0.8.0",
      mod_version: "1.0.0",
      license: "Unlicense"
    }, null, '  ');
  }

  // -- input --------------------------------------------------------------

  override function update(elapsed:Float):Void
  {
    super.update(elapsed);

    if (afterThisFrame != null)
    {
      var action = afterThisFrame;
      afterThisFrame = null;
      action();

      // Whatever that was, this may no longer be the state running.
      return;
    }

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

  /**
   * The top-left of the character as drawn, in the world.
   *
   * Not the same as where the character *is*: the offsets are applied at
   * draw time rather than to its position, so the sum has to be done by hand
   * anywhere the drawn shape matters.
   */
  function drawnCorner():FlxPoint
  {
    var corner = FlxPoint.get();

    if (character == null) return corner;

    var offset = currentOffset();
    var global = character.globalOffsets;

    corner.set(character.x - (offset[0] - global[0]) * character.scale.x,
      character.y - (offset[1] - global[1]) * character.scale.y);

    return corner;
  }

  /**
   * Whether a point in the world is on the character as it is drawn.
   *
   * What decides whether a finger going down is going to move the character
   * or the view: on it moves the character, anywhere else moves the view.
   */
  function overCharacter(x:Float, y:Float):Bool
  {
    if (character == null) return false;

    var corner = drawnCorner();
    var on = x >= corner.x && x <= corner.x + character.width && y >= corner.y && y <= corner.y + character.height;
    corner.put();

    return on;
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
      panning = false;

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
      lastPan.set(view.x, view.y);
      view.putWeak();

      pressWasDrag = false;

      if (!over)
      {
        var point = TouchUtil.touch.getWorldPosition(camStage);

        // A finger that goes down on the character moves the character.
        // Anywhere else on the stage it moves the view, which is the only
        // way to reach a character that has been dragged off the screen.
        if (overCharacter(point.x, point.y))
        {
          var offset = currentOffset();

          dragging = true;
          dragAnchor.set(point.x + offset[0], point.y + offset[1]);
        }
        else
        {
          panning = true;
        }

        point.putWeak();
      }
    }

    if (TouchUtil.pressed && (dragging || panning))
    {
      var view = TouchUtil.touch.getWorldPosition(camUI);
      var wandered = view.distanceTo(pressedAt);

      // Until the finger has gone somewhere this might still turn out to be a
      // tap, and moving the character on the way would undo itself anyway.
      if (wandered > TAP_SLOP)
      {
        // The drag starts here rather than where the finger landed: a finger
        // that goes down and comes back up has asked to see the animation
        // again and moved nothing, and writing that down would leave an undo
        // that undoes nothing. Nothing has moved yet on this frame, so what
        // gets written down is still where the character stood.
        if (dragging && !pressWasDrag) recordOffset();

        pressWasDrag = true;

        if (dragging)
        {
          var point = TouchUtil.touch.getWorldPosition(camStage);
          setOffset(dragAnchor.x - point.x, dragAnchor.y - point.y);
          point.putWeak();
        }
        else
        {
          camStage.scroll.x -= (view.x - lastPan.x) / camStage.zoom;
          camStage.scroll.y -= (view.y - lastPan.y) / camStage.zoom;
        }
      }

      lastPan.set(view.x, view.y);
      view.putWeak();
    }

    if (!TouchUtil.pressed)
    {
      // Let go without having moved and you were asking to see the animation
      // again, not to place the character. A pinch cancels the drag before it
      // gets here, so moving the view never replays anything.
      if (dragging && !pressWasDrag) replayAnimation();

      dragging = false;
      panning = false;
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
      lastPan.set(view.x, view.y);
      view.putWeak();

      pressWasDrag = false;

      if (!over)
      {
        var point = FlxG.mouse.getWorldPosition(camStage);

        if (overCharacter(point.x, point.y))
        {
          var offset = currentOffset();

          dragging = true;
          dragAnchor.set(point.x + offset[0], point.y + offset[1]);
        }
        else
        {
          panning = true;
        }

        point.putWeak();
      }
    }

    if (FlxG.mouse.pressed && (dragging || panning))
    {
      var view = FlxG.mouse.getViewPosition(camUI);
      var wandered = view.distanceTo(pressedAt);

      if (wandered > TAP_SLOP)
      {
        // The drag starts here rather than where the finger landed: a finger
        // that goes down and comes back up has asked to see the animation
        // again and moved nothing, and writing that down would leave an undo
        // that undoes nothing. Nothing has moved yet on this frame, so what
        // gets written down is still where the character stood.
        if (dragging && !pressWasDrag) recordOffset();

        pressWasDrag = true;

        if (dragging)
        {
          var point = FlxG.mouse.getWorldPosition(camStage);
          setOffset(dragAnchor.x - point.x, dragAnchor.y - point.y);
          point.putWeak();
        }
        else
        {
          camStage.scroll.x -= (view.x - lastPan.x) / camStage.zoom;
          camStage.scroll.y -= (view.y - lastPan.y) / camStage.zoom;
        }
      }

      lastPan.set(view.x, view.y);
      view.putWeak();
    }

    if (!FlxG.mouse.pressed)
    {
      if (dragging && !pressWasDrag) replayAnimation();

      dragging = false;
      panning = false;
    }

    if (FlxG.mouse.wheel != 0)
    {
      var zoom = camStage.zoom + FlxG.mouse.wheel * 0.1;
      camStage.zoom = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, zoom));
    }
  }
  #end


  override function destroy():Void
  {
    // The registry keeps its stage between visits, so anything still
    // standing on it when the editor closes is still standing on it the
    // next time anything builds it — a song included.
    unloadStage();

    super.destroy();
  }

  function goBack():Void
  {
    FlxG.switchState(() -> new funkin.ui.debug.EditorHubState());
  }
}

/**
 * A window the editor can put up and take away.
 *
 * Where it goes is worked out once, when it is built, and kept — otherwise a
 * window would land somewhere new every time it was reopened.
 */
typedef EditorWindow =
{
  var dialog:CollapsibleDialog;
  var shown:Bool;
  var left:Null<Float>;
  var top:Null<Float>;
}

/**
 * What a song said about its characters before a playtest changed it.
 */
typedef PlaytestOverride =
{
  var characters:funkin.data.song.SongData.SongCharacterData;
  var player:String;
  var girlfriend:String;
  var opponent:String;
  var playerVocals:Null<Array<String>>;
  var opponentVocals:Null<Array<String>>;
}

/**
 * Where one animation's offset stood before something moved it.
 */
typedef OffsetEdit =
{
  var animation:String;
  var x:Float;
  var y:Float;
}
