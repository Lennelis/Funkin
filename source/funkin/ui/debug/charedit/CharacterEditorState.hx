package funkin.ui.debug.charedit;

import flixel.FlxSprite;
import flixel.addons.transition.FlxTransitionableState;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.data.character.CharacterData;
import funkin.data.character.CharacterData.CharacterDataParser;
import funkin.graphics.FunkinCamera;
import funkin.play.character.BaseCharacter;
import funkin.ui.FullScreenScaleMode;
import funkin.ui.MusicBeatState;
import funkin.util.FileUtil;
import funkin.util.SortUtil;
#if mobile
import funkin.util.TouchUtil;
#end

/**
 * A character editor you can use with your thumbs.
 *
 * The existing one is built for a mouse and a keyboard: offsets are nudged
 * with the arrow keys and saving goes through a desktop file dialog, neither
 * of which exists on a phone. So it opens there and then cannot do the two
 * things it is for.
 *
 * This keeps the parts of that which are not about input — the character
 * loading, the animation playback, the offsets living on the sprite — and
 * replaces the rest. You drag the character to place it, two fingers move and
 * zoom the view, and saving writes a mod the game reads back.
 */
class CharacterEditorState extends MusicBeatState
{
  /**
   * Where a saved character goes.
   *
   * Writing into a mod rather than over the game's own files means an edit is
   * live the next time the game loads, and that the original is still there
   * if the edit was a mistake.
   */
  static final MOD_ROOT:String = 'mods';

  static final MOD_ID:String = 'editor';

  static final ZOOM_MIN:Float = 0.15;

  static final ZOOM_MAX:Float = 4.0;

  /**
   * The view the character sits in, which moves and zooms under two fingers.
   */
  var camStage:FunkinCamera;

  /**
   * Everything that should stay put while the view moves.
   */
  var camUI:FunkinCamera;

  var character:Null<BaseCharacter> = null;

  var data:Null<CharacterData> = null;

  var characterIds:Array<String> = [];

  var characterIndex:Int = 0;

  var animationNames:Array<String> = [];

  var animationIndex:Int = 0;

  var info:FlxText;

  var status:FlxText;

  /**
   * The animation list down the right, and the buttons along the bottom.
   */
  var buttons:Array<EditorButton> = [];

  var animationButtons:Array<EditorButton> = [];

  // -- gesture state ------------------------------------------------------

  var dragging:Bool = false;

  /**
   * Where the character's offset would be if the finger were at the origin,
   * so a drag can be turned into an offset without accumulating error.
   */
  var dragAnchor:FlxPoint = new FlxPoint();

  var pinching:Bool = false;

  var lastMid:FlxPoint = new FlxPoint();

  var lastPinchDistance:Float = 0;

  override function create():Void
  {
    FlxTransitionableState.skipNextTransIn = true;
    super.create();

    // The same green as the screen this was opened from, so it reads as part
    // of the same app rather than as the game with a character in it.
    var bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
    bg.color = 0xFF4CAF50;
    bg.setGraphicSize(Std.int(bg.width * 1.1 * FullScreenScaleMode.wideScale.x));
    bg.updateHitbox();
    bg.screenCenter();
    bg.scrollFactor.set(0, 0);
    add(bg);

    camStage = new FunkinCamera('camStage');
    camStage.bgColor = 0x0;
    FlxG.cameras.add(camStage, false);

    camUI = new FunkinCamera('camUI');
    camUI.bgColor = 0x0;
    FlxG.cameras.add(camUI, false);

    characterIds = CharacterDataParser.listCharacterIds();
    characterIds.sort(SortUtil.alphabetically);

    buildUI();
    loadCharacter(characterIds.length > 0 ? characterIds[0] : null);

    #if mobile
    // Also what puts a camera at index 1, which the engine's touch handling
    // measures taps against.
    addBackButton(FlxG.width - 230, FlxG.height - 200, FlxColor.WHITE, goBack, 1.0);
    #end
  }

  // -- the screen ---------------------------------------------------------

  function buildUI():Void
  {
    info = new FlxText(16, 16, FlxG.width * 0.6, "");
    info.setFormat(Paths.font("vcr.ttf"), 28, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
    info.scrollFactor.set(0, 0);
    info.cameras = [camUI];
    add(info);

    status = new FlxText(16, FlxG.height - 54, FlxG.width - 32, "");
    status.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
    status.scrollFactor.set(0, 0);
    status.cameras = [camUI];
    add(status);

    addButton("<", 16, FlxG.height - 130, 70, previousCharacter);
    addButton(">", 96, FlxG.height - 130, 70, nextCharacter);
    addButton("SAVE", 186, FlxG.height - 130, 150, save);
    addButton("RESET", 346, FlxG.height - 130, 170, resetOffset);
  }

  function addButton(label:String, x:Float, y:Float, width:Float, action:Void->Void):EditorButton
  {
    var button = new EditorButton(label, x, y, width, action);
    button.attachTo(this, camUI);
    buttons.push(button);
    return button;
  }

  /**
   * The animation list, rebuilt whenever the character changes.
   *
   * An animation whose prefix is not in the sprite sheet plays nothing, and
   * that is by far the most common thing wrong with a character file, so the
   * list says which ones those are rather than leaving you to find out.
   */
  function buildAnimationList():Void
  {
    for (button in animationButtons)
      button.detachFrom(this);

    animationButtons = [];

    var top:Float = 70;
    var spacing:Float = 46;
    var width:Float = 300;
    var x:Float = FlxG.width - width - 16;

    for (index in 0...animationNames.length)
    {
      var name = animationNames[index];
      var y = top + index * spacing;

      // Only as many as fit; the rest need paging, which is not built yet.
      if (y + spacing > FlxG.height - 150) break;

      var missing = character != null && !character.hasAnimation(name);
      var chosen = index;

      var button = new EditorButton(missing ? '$name (no frames)' : name, x, y, width, () -> selectAnimation(chosen));
      button.setTint(missing ? 0xFFFFA726 : FlxColor.WHITE);
      button.attachTo(this, camUI);

      animationButtons.push(button);
    }

    highlightAnimation();
  }

  function highlightAnimation():Void
  {
    for (index in 0...animationButtons.length)
      animationButtons[index].setSelected(index == animationIndex);
  }

  // -- the character ------------------------------------------------------

  function loadCharacter(id:Null<String>):Void
  {
    if (id == null)
    {
      say('No characters found.');
      return;
    }

    if (character != null)
    {
      remove(character);
      character.destroy();
      character = null;
    }

    data = CharacterDataParser.fetchCharacterData(id);
    character = CharacterDataParser.fetchCharacter(id, true);

    if (character == null || data == null)
    {
      say('Could not load $id.');
      animationNames = [];
      buildAnimationList();
      return;
    }

    character.cameras = [camStage];
    character.screenCenter();
    add(character);

    animationNames = [for (animation in data.animations) animation.name];
    animationIndex = 0;

    camStage.zoom = 1;
    camStage.scroll.set(0, 0);

    buildAnimationList();
    if (animationNames.length > 0) selectAnimation(0);

    refreshInfo();
    say('Loaded $id.');
  }

  function selectAnimation(index:Int):Void
  {
    if (character == null || index < 0 || index >= animationNames.length) return;

    animationIndex = index;
    character.playAnimation(animationNames[index], true);

    highlightAnimation();
    refreshInfo();
  }

  function currentAnimation():String
  {
    if (animationIndex < 0 || animationIndex >= animationNames.length) return '';
    return animationNames[animationIndex];
  }

  function previousCharacter():Void
  {
    if (characterIds.length == 0) return;

    characterIndex = (characterIndex - 1 + characterIds.length) % characterIds.length;
    loadCharacter(characterIds[characterIndex]);
  }

  function nextCharacter():Void
  {
    if (characterIds.length == 0) return;

    characterIndex = (characterIndex + 1) % characterIds.length;
    loadCharacter(characterIds[characterIndex]);
  }

  function resetOffset():Void
  {
    setOffset(0, 0);
    say('Offset cleared for ${currentAnimation()}.');
  }

  function setOffset(x:Float, y:Float):Void
  {
    if (character == null) return;

    var name = currentAnimation();
    if (name == '') return;

    // Both, because the map is what gets saved and the field is what the
    // sprite draws itself with.
    character.animOffsets = [x, y];
    character.setAnimationOffsets(name, x, y);

    refreshInfo();
  }

  function currentOffset():Array<Float>
  {
    if (character == null) return [0, 0];

    var stored = character.animationOffsets.get(currentAnimation());
    return stored == null ? [0, 0] : stored;
  }

  function refreshInfo():Void
  {
    if (character == null || data == null)
    {
      info.text = 'No character loaded';
      return;
    }

    var offset = currentOffset();

    info.text = '${data.name}  (${characterIndex + 1}/${characterIds.length})\n'
      + '${currentAnimation()}\n'
      + 'offset ${Std.int(offset[0])}, ${Std.int(offset[1])}';
  }

  function say(message:String):Void
  {
    status.text = message;
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

  #if mobile
  function updateGestures():Void
  {
    var touches = FlxG.touches.list;

    if (touches.length >= 2)
    {
      // Two fingers move and scale the view. A drag that was underway is
      // abandoned rather than fighting the pinch.
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

    for (button in buttons)
      if (button.wasTapped(camUI)) return;

    for (button in animationButtons)
      if (button.wasTapped(camUI)) return;

    if (character == null) return;

    if (TouchUtil.justPressed)
    {
      var point = TouchUtil.touch.getWorldPosition(camStage);
      var offset = currentOffset();

      dragging = true;
      dragAnchor.set(point.x + offset[0], point.y + offset[1]);
      point.putWeak();
    }

    if (dragging && TouchUtil.pressed)
    {
      var point = TouchUtil.touch.getWorldPosition(camStage);
      setOffset(dragAnchor.x - point.x, dragAnchor.y - point.y);
      point.putWeak();
    }

    if (!TouchUtil.pressed) dragging = false;
  }

  function goBack():Void
  {
    FlxG.switchState(() -> new funkin.ui.debug.EditorHubState());
  }
  #else
  function updateMouse():Void
  {
    for (button in buttons)
      if (button.wasClicked(camUI)) return;

    for (button in animationButtons)
      if (button.wasClicked(camUI)) return;

    if (character == null) return;

    if (FlxG.mouse.justPressed)
    {
      var point = FlxG.mouse.getWorldPosition(camStage);
      var offset = currentOffset();

      dragging = true;
      dragAnchor.set(point.x + offset[0], point.y + offset[1]);
      point.putWeak();
    }

    if (dragging && FlxG.mouse.pressed)
    {
      var point = FlxG.mouse.getWorldPosition(camStage);
      setOffset(dragAnchor.x - point.x, dragAnchor.y - point.y);
      point.putWeak();
    }

    if (!FlxG.mouse.pressed) dragging = false;

    if (FlxG.mouse.wheel != 0)
    {
      var zoom = camStage.zoom + FlxG.mouse.wheel * 0.1;
      camStage.zoom = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, zoom));
    }
  }
  #end

  // -- saving -------------------------------------------------------------

  /**
   * Write the character out as a mod.
   *
   * The old editor saves through a desktop file dialog, which is why it
   * cannot save on a phone at all. This writes the file itself, and says so
   * on screen either way — there is no console to check.
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
      var id = characterIds[characterIndex];

      FileUtil.writeStringToPath('$root/data/characters/$id.json', haxe.Json.stringify(data, null, '  '), Force);

      say('Saved to $root/data/characters/$id.json');
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
