package funkin.ui.debug;

import flixel.FlxSprite;
import flixel.addons.transition.FlxTransitionableState;
import flixel.util.FlxColor;
import funkin.audio.FunkinSound;
import funkin.graphics.FunkinCamera;
import funkin.graphics.FunkinSprite;
import funkin.ui.MusicBeatState;
#if mobile
import funkin.util.TouchUtil;
#end

/**
 * The screen the editor app opens on, before the list of editors.
 *
 * A fade up out of black onto the menu art, blurred and drained of colour,
 * with the camera easing outwards under it. Then the people who made the
 * thing arrive the way a rank arrives in freeplay: enormous, then not,
 * knocking the screen as each one lands.
 *
 * Everything here is driven from one clock rather than from a chain of
 * tweens and timers. The sequence was timed against the music by ear on a
 * sixteenth-note grid, and the numbers below are those measurements; a
 * chain of callbacks would put each of them a frame or two out and leave
 * nothing to skip cleanly to.
 */
class EditorIntroState extends MusicBeatState
{
  // -- when things happen, in milliseconds from the first frame -----------

  /**
   * The fade up out of black.
   */
  static final FADE:Float = 400;

  /**
   * How long the camera goes on easing outwards. It outlives the fade on
   * purpose: the room is visible early and keeps settling underneath
   * everything that lands on top of it.
   */
  static final ZOOM:Float = 1314;

  static final AT_CARDS:Float = 738;

  static final AT_NAMES:Float = 1226;

  static final AT_STING:Float = 1513;

  static final AT_LOGO:Float = 1882;

  /**
   * How long the wordmark holds before the editors take over.
   */
  static final HOLD:Float = 1700;

  static final ENDS:Float = AT_LOGO + HOLD;

  // -- how a slam behaves --------------------------------------------------

  /**
   * How long a slam takes to land, and what it starts at.
   *
   * The freeplay rank sets itself to twenty times its size and tweens to
   * full size in a tenth of a second with no easing at all. Linear is the
   * point: an ease would show the thing arriving, and it is meant to be
   * already there. A hundred and ten milliseconds rather than the game's
   * hundred, because that is one sixteenth note at this tempo and it puts
   * the sounds back on the grid.
   */
  static final SLAM:Float = 110;

  static final SLAM_FROM:Float = 20;

  /**
   * How far off level a slam lands, and how long it rocks back.
   */
  static final TILT:Float = 3;

  static final TILT_FOR:Float = 500;

  /**
   * The knock the screen takes, as a fraction of its width, on the last and
   * hardest of the slams. Earlier ones get a share of it.
   */
  static final SHAKE:Float = 20 / 1920;

  static final SHAKE_FOR:Float = 260;

  /**
   * How often the shake picks a new offset.
   *
   * Stepped rather than smooth, the way the game's own shake is: it moves
   * thirty times a second and sits still in between, and that judder is
   * most of what the effect is.
   */
  static final SHAKE_STEP:Float = 1000 / 30;

  // -- where things sit ----------------------------------------------------

  /**
   * Read off the layout this was drawn against. Sizes are fractions of the
   * screen's width and centres are fractions of each axis, so the whole
   * thing holds its shape whatever the screen turns out to be.
   */
  static final CARD_WIDTH:Float = 0.198;

  static final CARD_LEFT:Float = 0.318;

  static final CARD_RIGHT:Float = 0.646;

  static final CARD_MIDDLE:Float = 0.306;

  static final NAME_HEIGHT:Float = 0.042;

  static final NAME_MIDDLE:Float = 0.555;

  static final LOGO_WIDTH:Float = 0.44;

  static final LOGO_MIDDLE:Float = 0.759;

  /**
   * How much wider than the screen the backdrop is.
   *
   * The shake moves the camera, and a backdrop cut exactly to the screen
   * would show black down one edge every time it did.
   */
  static final BACKDROP_OVERHANG:Float = 1.08;

  var camIntro:FunkinCamera;

  var backdrop:FunkinSprite;

  var blackout:FlxSprite;

  /**
   * The things that slam in, with the size each one settles at.
   *
   * Held rather than measured, because a sprite's width is its scaled width
   * and a slam is in the middle of changing that.
   */
  var slammers:Array<Slammer> = [];

  /**
   * The moments a slam lands, in order, which is what the shake and the
   * sounds hang off.
   */
  var landings:Array<Float> = [AT_CARDS + SLAM, AT_NAMES + SLAM, AT_LOGO + SLAM];

  var clock:Float = 0;

  /**
   * How many of the three sounds have gone, so none of them goes twice.
   */
  var played:Int = 0;

  /**
   * Set once the editors have been asked for, so a slow switch cannot ask
   * for them again on the next frame.
   */
  var leaving:Bool = false;

  override function create():Void
  {
    FlxTransitionableState.skipNextTransIn = true;
    super.create();

    camIntro = new FunkinCamera('camIntro');
    camIntro.bgColor = FlxColor.BLACK;
    FlxG.cameras.reset(camIntro);

    backdrop = byWidth('background', BACKDROP_OVERHANG);
    backdrop.x = (FlxG.width - backdrop.width) / 2;
    backdrop.y = (FlxG.height - backdrop.height) / 2;

    var cardLeft = byWidth('len', CARD_WIDTH);
    var cardRight = byWidth('thatoneidiot', CARD_WIDTH);
    var nameLeft = byHeight('len-name', NAME_HEIGHT);
    var nameRight = byHeight('thatoneidiot-name', NAME_HEIGHT);
    var logo = byWidth('made-with-claude', LOGO_WIDTH);

    slamAt(cardLeft, CARD_LEFT, CARD_MIDDLE, AT_CARDS);
    slamAt(cardRight, CARD_RIGHT, CARD_MIDDLE, AT_CARDS);
    slamAt(nameLeft, CARD_LEFT, NAME_MIDDLE, AT_NAMES);
    slamAt(nameRight, CARD_RIGHT, NAME_MIDDLE, AT_NAMES);
    slamAt(logo, 0.5, LOGO_MIDDLE, AT_LOGO);

    // Over everything, so the fade is a fade of the whole picture rather
    // than of each thing in it. Twice the screen so the shake cannot drag
    // an edge of it into view.
    blackout = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
    blackout.scale.set(FlxG.width * 2, FlxG.height * 2);
    blackout.updateHitbox();
    blackout.screenCenter();
    blackout.scrollFactor.set(0, 0);
    add(blackout);

    // Started here and left alone: the editors screen plays the same track
    // and will not restart something already going, so the music carries
    // straight through the cut rather than beginning again behind it.
    FunkinSound.playMusic('chartEditorLoop',
      {
        overrideExisting: true,
        restartTrack: true,
        persist: true
      });

    tick(0);
  }

  /**
   * Load a piece of the picture, sized against the screen's width.
   */
  function byWidth(name:String, ofScreen:Float):FunkinSprite
  {
    var sprite:FunkinSprite = FunkinSprite.create('editors-intro/$name');

    sprite.antialiasing = true;
    sprite.setGraphicSize(Std.int(FlxG.width * ofScreen));
    sprite.updateHitbox();

    add(sprite);
    return sprite;
  }

  /**
   * The same, but sized by height, for the two nameplates.
   *
   * They are different widths and the same height, so matching them on
   * height is what keeps them looking like a pair. Still a fraction of the
   * screen's width, so the pair scales with everything else.
   */
  function byHeight(name:String, ofScreenWidth:Float):FunkinSprite
  {
    var sprite:FunkinSprite = FunkinSprite.create('editors-intro/$name');

    sprite.antialiasing = true;
    sprite.setGraphicSize(0, Std.int(FlxG.width * ofScreenWidth));
    sprite.updateHitbox();

    add(sprite);
    return sprite;
  }

  /**
   * Put something where it belongs and say when it arrives.
   */
  function slamAt(sprite:FunkinSprite, acrossScreen:Float, downScreen:Float, at:Float):Void
  {
    sprite.x = FlxG.width * acrossScreen - sprite.width / 2;
    sprite.y = FlxG.height * downScreen - sprite.height / 2;

    slammers.push(
      {
        sprite: sprite,
        at: at,
        restX: sprite.scale.x,
        restY: sprite.scale.y
      });
  }

  override function update(elapsed:Float):Void
  {
    super.update(elapsed);

    if (leaving) return;

    var skipped:Bool = FlxG.keys.justPressed.ANY
      || FlxG.mouse.justPressed #if mobile || TouchUtil.justPressed #end;

    clock += elapsed * 1000;

    if (skipped || clock >= ENDS)
    {
      leaving = true;
      FlxG.switchState(() -> new EditorHubState());
      return;
    }

    tick(clock);
  }

  /**
   * Put everything where it should be at this moment.
   */
  function tick(now:Float):Void
  {
    blackout.alpha = 1 - eased(Math.min(1, now / FADE), 2);

    // Cubic, so most of the movement is over early and the rest is a drift.
    camIntro.zoom = 1.18 - 0.18 * eased(Math.min(1, now / ZOOM), 3);

    for (slammer in slammers)
      land(slammer, now);

    shake(now);
    sound(now);
  }

  /**
   * A slam, as the freeplay rank does one: from many times its own size to
   * full size, linearly, then held tilted and rocked back level.
   */
  function land(slammer:Slammer, now:Float):Void
  {
    var sprite:FunkinSprite = slammer.sprite;

    sprite.visible = now >= slammer.at;
    if (!sprite.visible) return;

    var travelled:Float = Math.min(1, (now - slammer.at) / SLAM);
    var size:Float = SLAM_FROM + (1 - SLAM_FROM) * travelled;

    sprite.scale.set(slammer.restX * size, slammer.restY * size);

    if (travelled < 1)
    {
      sprite.angle = -TILT;
      return;
    }

    var rocked:Float = Math.min(1, (now - slammer.at - SLAM) / TILT_FOR);
    sprite.angle = -TILT * (1 - backOut(rocked));
  }

  /**
   * The knock each landing gives the screen, growing with every one.
   *
   * The camera takes it rather than the sprites, so the room is hit along
   * with everything standing in it.
   */
  function shake(now:Float):Void
  {
    var x:Float = 0;
    var y:Float = 0;

    for (index in 0...landings.length)
    {
      var age:Float = now - landings[index];
      if (age < 0 || age > SHAKE_FOR) continue;

      // Falls away on a quad-out, which comes to one minus the progress,
      // squared.
      var left:Float = Math.pow(1 - age / SHAKE_FOR, 2);
      var strength:Float = SHAKE * FlxG.width * ((index + 1) / landings.length) * left;
      var step:Int = Std.int(age / SHAKE_STEP);

      x += scatter(index * 97 + step * 2) * strength;
      y += scatter(index * 97 + step * 2 + 1) * strength;
    }

    camIntro.scroll.set(x, y);
  }

  /**
   * The three sounds, each on the frame its slam lands rather than the frame
   * it sets off. The sting is its own thing: it moves nothing, so it has no
   * travel to wait for.
   */
  function sound(now:Float):Void
  {
    if (played < 1 && now >= landings[0])
    {
      FunkinSound.playOnce(Paths.sound('ranks/rankinnormal'));
      played = 1;
    }

    if (played < 2 && now >= landings[1])
    {
      FunkinSound.playOnce(Paths.sound('ranks/rankinperfect'));
      played = 2;
    }

    if (played < 3 && now >= AT_STING)
    {
      FunkinSound.playOnce(Paths.sound('ranks/excellent'));
      played = 3;
    }
  }

  // -- the shapes of things ------------------------------------------------

  /**
   * Eased out to the given power: all of the distance covered early.
   */
  static function eased(t:Float, power:Int):Float
  {
    return 1 - Math.pow(1 - t, power);
  }

  /**
   * Overshoots a little past the target and comes back, the way
   * `FlxEase.backOut` does, so the rock reads as weight.
   */
  static function backOut(t:Float):Float
  {
    var b:Float = 1.70158;
    return 1 + (b + 1) * Math.pow(t - 1, 3) + b * Math.pow(t - 1, 2);
  }

  /**
   * A scatter that depends only on which step of which shake it is.
   *
   * Not random: the same moment has to look the same however many times it
   * is drawn, or a dropped frame moves the screen somewhere else.
   */
  static function scatter(n:Int):Float
  {
    var x:Float = Math.sin(n * 127.1 + 311.7) * 43758.5453;
    return (x - Math.floor(x)) * 2 - 1;
  }
}

/**
 * Something that slams in, and the size it settles at.
 */
typedef Slammer =
{
  var sprite:FunkinSprite;
  var at:Float;
  var restX:Float;
  var restY:Float;
}
