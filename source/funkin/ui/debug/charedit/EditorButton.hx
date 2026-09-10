package funkin.ui.debug.charedit;

import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.ui.MusicBeatState;
#if mobile
import funkin.util.TouchUtil;
#end

/**
 * A button big enough to hit with a thumb.
 *
 * The editors are built out of HaxeUI, which is fine behind a mouse and
 * miserable behind a finger. This is deliberately not that: a rectangle and a
 * label, sized so it can be hit without aiming.
 */
class EditorButton
{
  public static final HEIGHT:Float = 40;

  public var label(default, null):String;

  var background:FlxSprite;

  var text:FlxText;

  var action:Void->Void;

  var selected:Bool = false;

  var tint:FlxColor = FlxColor.WHITE;

  public function new(label:String, x:Float, y:Float, width:Float, action:Void->Void)
  {
    this.label = label;
    this.action = action;

    background = new FlxSprite(x, y).makeGraphic(Std.int(width), Std.int(HEIGHT), FlxColor.BLACK);
    background.alpha = 0.55;
    background.scrollFactor.set(0, 0);

    text = new FlxText(x, y + 6, width, label);
    text.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
    text.scrollFactor.set(0, 0);
  }

  public function attachTo(state:MusicBeatState, camera:flixel.FlxCamera):Void
  {
    background.cameras = [camera];
    text.cameras = [camera];

    state.add(background);
    state.add(text);
  }

  public function detachFrom(state:MusicBeatState):Void
  {
    state.remove(background);
    state.remove(text);

    background.destroy();
    text.destroy();
  }

  public function setTint(color:FlxColor):Void
  {
    tint = color;
    text.color = color;
  }

  public function setSelected(value:Bool):Void
  {
    selected = value;
    background.alpha = value ? 0.85 : 0.55;
    background.color = value ? FlxColor.fromRGB(0x2E, 0x7D, 0x32) : FlxColor.BLACK;
  }

  #if mobile
  /**
   * Whether this was just tapped, firing it if so.
   *
   * Returns true either way when the touch was inside it, so the caller can
   * stop rather than also treating the same touch as something else.
   */
  public function wasTapped(camera:flixel.FlxCamera):Bool
  {
    if (!TouchUtil.justPressed) return false;
    if (!TouchUtil.overlaps(background, camera)) return false;

    if (action != null) action();
    return true;
  }
  #else
  public function wasClicked(camera:flixel.FlxCamera):Bool
  {
    if (!FlxG.mouse.justPressed) return false;

    var point = FlxG.mouse.getWorldPosition(camera);
    var inside = background.overlapsPoint(point, true, camera);
    point.putWeak();

    if (!inside) return false;

    if (action != null) action();
    return true;
  }
  #end
}
