package funkin.ui.debug;

import flixel.math.FlxPoint;
#if mobile
import funkin.util.TouchUtil;
#end

/**
 * The gestures the editors have in common.
 *
 * The editors were built for a mouse, and a mouse says where it is at all
 * times. A finger only says so while it is down, and says nothing about
 * what it means by it — the same press is a scroll, a drag or a selection
 * depending on what happens next. So rather than each editor guessing, this
 * watches the touches and answers the three questions all of them ask: are
 * two fingers moving the view, is one finger dragging, and has one been
 * still long enough to mean something other than a tap.
 *
 * Where those answers are acted on is each editor's business — what counts
 * as a scroll in one is a selection in another.
 *
 * On anything with a real pointer this reports nothing and costs nothing,
 * so the editors can ask without caring what they are running on.
 */
class EditorTouch
{
  /**
   * How long a finger has to stay put before it counts as a hold.
   */
  public static final HOLD_TIME:Float = 0.32;

  /**
   * How far it may wander in that time and still count as still.
   *
   * Generous, because a finger resting on glass is never actually still and
   * the alternative is a hold that almost never fires.
   */
  public static final HOLD_SLOP:Float = 18;

  /**
   * Whether two fingers are on the screen, moving the view between them.
   *
   * While this is true, everything a single finger would have meant is off:
   * the second finger landing turns a drag into a gesture.
   */
  public var pinching(default, null):Bool = false;

  /**
   * How far the two fingers moved together since the last frame.
   */
  public var panX(default, null):Float = 0;

  public var panY(default, null):Float = 0;

  /**
   * How much further apart they got since the last frame, as a ratio. One
   * means they held their distance.
   */
  public var spread(default, null):Float = 1;

  /**
   * Whether exactly one finger is down.
   */
  public var dragging(default, null):Bool = false;

  /**
   * Where that finger went down, and how far it has moved since the last
   * frame.
   */
  public var startX(default, null):Float = 0;

  public var startY(default, null):Float = 0;

  public var dragX(default, null):Float = 0;

  public var dragY(default, null):Float = 0;

  /**
   * How far the finger has strayed from where it went down.
   *
   * The distance from the start rather than the distance travelled, so a
   * finger that wobbles and comes back is still holding still.
   */
  public var wandered(default, null):Float = 0;

  /**
   * Whether the finger has been still long enough to mean a hold, and the
   * one frame on which that became true.
   */
  public var held(default, null):Bool = false;

  public var justHeld(default, null):Bool = false;

  var lastX:Float = 0;
  var lastY:Float = 0;
  var lastSpread:Float = 0;
  var downFor:Float = 0;

  public function new() {}

  /**
   * Look at the screen and answer the three questions.
   */
  public function update(elapsed:Float):Void
  {
    panX = 0;
    panY = 0;
    spread = 1;
    dragX = 0;
    dragY = 0;
    justHeld = false;

    #if mobile
    var touches = flixel.FlxG.touches.list;

    if (touches.length >= 2)
    {
      twoFingers(touches[0].viewX, touches[0].viewY, touches[1].viewX, touches[1].viewY);
      return;
    }

    if (pinching) forget();

    if (touches.length == 1)
    {
      oneFinger(touches[0].viewX, touches[0].viewY, elapsed);
      return;
    }
    #end

    if (dragging || held) forget();
  }

  /**
   * Two fingers: the view moves with the point between them and scales with
   * the distance between them.
   */
  function twoFingers(ax:Float, ay:Float, bx:Float, by:Float):Void
  {
    var midX:Float = (ax + bx) / 2;
    var midY:Float = (ay + by) / 2;
    var apart:Float = FlxPoint.weak(ax, ay).distanceTo(FlxPoint.weak(bx, by));

    if (pinching)
    {
      panX = midX - lastX;
      panY = midY - lastY;

      // Only when both readings are real: a ratio taken against nothing is
      // an enormous jump on the frame the second finger lands.
      if (lastSpread > 1 && apart > 1) spread = apart / lastSpread;
    }

    pinching = true;
    dragging = false;
    held = false;

    lastX = midX;
    lastY = midY;
    lastSpread = apart;
  }

  /**
   * One finger: a drag, and a hold once it has stayed put long enough.
   */
  function oneFinger(x:Float, y:Float, elapsed:Float):Void
  {
    if (!dragging)
    {
      dragging = true;
      startX = x;
      startY = y;
      lastX = x;
      lastY = y;
      downFor = 0;
      wandered = 0;
      held = false;
    }

    dragX = x - lastX;
    dragY = y - lastY;
    lastX = x;
    lastY = y;

    wandered = FlxPoint.weak(x, y).distanceTo(FlxPoint.weak(startX, startY));
    downFor += elapsed;

    // A hold is a finger that went down and stayed. Once it has wandered it
    // is a drag, and no amount of waiting turns it back.
    if (!held && wandered <= HOLD_SLOP && downFor >= HOLD_TIME)
    {
      held = true;
      justHeld = true;
    }
  }

  function forget():Void
  {
    pinching = false;
    dragging = false;
    held = false;
    lastSpread = 0;
    downFor = 0;
    wandered = 0;
  }
}
