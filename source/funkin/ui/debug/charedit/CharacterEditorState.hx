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
import funkin.util.FileUtil.SelectedFileData;
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
  var animOffsetX:Null<NumberStepper> = null;
  var animOffsetY:Null<NumberStepper> = null;

  /**
   * A see-through copy of the character, left where it was.
   *
   * Setting an offset is judging a distance, and a distance needs two things
   * to be between. This is the other one: it stays put while the character
   * moves, so what you are dragging is the gap.
   */
  var ghost:Null<FlxSprite> = null;
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
    wireMenuItem('menuExit', () -> later(goBack));
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

    buildCharacterSelect(select);
    buildAnimationWindow(animation);
    buildCharacterDataWindow(characterData);
    buildHealthIconWindow(healthIcon);
    buildNewCharacterWindow(newCharacter);

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
      write(field.text ?? '');
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

    bindStepper(dialog, 'animOffsetXStepper', () -> currentOffset()[0], function(value) setOffset(value, currentOffset()[1]));
    bindStepper(dialog, 'animOffsetYStepper', () -> currentOffset()[1], function(value) setOffset(currentOffset()[0], value));

    bindField(dialog, 'prefixField', () -> currentAnimation()?.prefix ?? '', function(value) {
      var animation = currentAnimation();
      if (animation == null) return;

      animation.prefix = value;
      say('The prefix takes effect on reload.');
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
    bindButton(dialog, 'replayButton', replayAnimation);

    var ghostCheck = dialog.findComponent('ghostCheck', CheckBox);
    if (ghostCheck != null)
    {
      ghostCheck.onChange = function(_) {
        if (populating) return;
        showGhost(ghostCheck.selected);
      };
    }
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

    // The stage owns what it was given and destroys it as it goes, so a
    // character standing on one is not the editor's to take down. One with
    // no stage under it is.
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

    showGhost(false);

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

    // An animation whose prefix is not in the sprite sheet plays nothing, and
    // that is the most common thing wrong with a character file, so say so
    // rather than leaving it to be discovered.
    if (animationWarning != null)
    {
      var missing = !character.hasAnimation(name);
      animationWarning.text = missing ? 'No frames for this prefix' : '';
    }

    // The animation window is showing one animation's worth of the file, and
    // which animation that is has just changed.
    refreshWindows();
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

    var copy = new FlxSprite();
    copy.loadGraphicFromSprite(character);
    copy.scale.copyFrom(character.scale);
    copy.updateHitbox();
    copy.flipX = character.flipX;
    copy.antialiasing = character.antialiasing;
    copy.alpha = 0.4;
    copy.cameras = [camStage];

    if (animationName != '')
    {
      // The end of the animation rather than the start of it: where a
      // character finishes is what has to line up, and the first frame of a
      // sing is usually the idle it grew out of.
      copy.animation.play(animationName, true);

      if (copy.animation.curAnim != null)
      {
        copy.animation.curAnim.curFrame = copy.animation.curAnim.numFrames - 1;
      }

      copy.animation.pause();
    }

    var corner = drawnCorner();
    copy.setPosition(corner.x, corner.y);
    corner.put();

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
   * Hand the character file to the system to put somewhere.
   *
   * Just the character's own JSON, and wherever the person says — the editor
   * has a folder it writes sheets into because it has to be able to read them
   * back, but a finished character is theirs to put where they want it.
   */
  function exportCharacter():Void
  {
    if (data == null || character == null)
    {
      say('Nothing to export.');
      return;
    }

    // The sprite has been carrying the offsets while they were dragged; put
    // them back into the data before it is written.
    for (animation in data.animations)
    {
      var offsets = character.animationOffsets.get(animation.name);
      if (offsets != null) animation.offsets = [offsets[0], offsets[1]];
    }

    var json:String = haxe.Json.stringify(data, null, '  ');
    var bytes = lime.utils.Bytes.fromBytes(haxe.io.Bytes.ofString(json));

    say('Choose where to put $characterId.json...');

    FileUtil.saveFile('Export $characterId.json', bytes, [FileUtil.FILE_FILTER_JSON], function(path:String) {
      say('Exported $characterId.json.');
    }, function() {
      say('Export cancelled.');
    }, '$characterId.json');
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
