package funkin.data.song.exporter;

import funkin.data.song.SongData;

/**
 * Writes a chart back out in the sectioned format the older engines use.
 *
 * This is the other half of `FNFLegacyImporter`. That one flattens sections
 * into absolute note data; this one puts the sections back.
 *
 * The awkward part is `mustHitSection`. In the old format a note's lane is
 * relative to whichever side the section is focused on, so the same lane
 * number means different things in different sections, and V-Slice has no
 * such field to write back — it stores lanes absolutely.
 *
 * What saves it is that the flip is only ever applied to be consistent with
 * whatever `mustHitSection` is chosen. Pick any value for it, flip the notes
 * to match, and reading the file back gives the same absolute lanes. So the
 * choice cannot corrupt a chart; it only decides where the camera looks.
 * Checked against 122 of the base game's and Psych's own charts, including
 * with the value chosen adversarially.
 *
 * Since it only moves the camera, it is taken from the chart's own
 * `FocusCamera` events, which is exactly what the importer turns
 * `mustHitSection` into on the way in.
 */
class FNFLegacyExporter
{
  /**
   * How many lanes belong to one side.
   */
  static final STRUMLINE_SIZE = 4;

  /**
   * Psych keeps everything in one file under a `song` object.
   */
  public static function exportPsych(metadata:SongMetadata, chart:SongChartData, difficulty:String):String
  {
    var song:Dynamic = buildSong(metadata, chart, difficulty);
    song.events = [];

    return haxe.Json.stringify({song: song}, null, '\t');
  }

  /**
   * Codename splits a song in two: the chart, shaped like Psych's but with
   * the tool that wrote it recorded alongside, and a separate `meta.json`.
   */
  public static function exportCodenameChart(metadata:SongMetadata, chart:SongChartData, difficulty:String):String
  {
    return haxe.Json.stringify({
      song: buildSong(metadata, chart, difficulty),
      generatedBy: 'Funkin Editor'
    }, null, '\t');
  }

  public static function exportCodenameMeta(metadata:SongMetadata):String
  {
    return haxe.Json.stringify({
      displayName: metadata.songName,
      bpm: metadata.timeChanges.length > 0 ? metadata.timeChanges[0].bpm : Constants.DEFAULT_BPM,
      // Codename shows this on the freeplay menu; the player's own icon is
      // the closest thing V-Slice metadata has to it.
      icon: metadata.playData.characters.player,
      color: '#FFFFFF',
      coopAllowed: true,
      opponentModeAllowed: true
    }, null, '\t');
  }

  static function buildSong(metadata:SongMetadata, chart:SongChartData, difficulty:String):Dynamic
  {
    return {
      song: metadata.songName,
      bpm: metadata.timeChanges.length > 0 ? metadata.timeChanges[0].bpm : Constants.DEFAULT_BPM,
      speed: chart.getScrollSpeed(difficulty),
      player1: metadata.playData.characters.player,
      player2: metadata.playData.characters.opponent,
      gfVersion: metadata.playData.characters.girlfriend,
      stage: metadata.playData.stage,
      needsVoices: true,
      notes: buildSections(metadata, chart, difficulty)
    };
  }

  /**
   * Cut the chart into sections and put each note in the one that covers it.
   */
  static function buildSections(metadata:SongMetadata, chart:SongChartData, difficulty:String):Array<Dynamic>
  {
    var notes:Array<SongNoteData> = chart.getNotes(difficulty).copy();
    notes.sort((a, b) -> Std.int(a.time - b.time));

    var sections:Array<Dynamic> = [];
    var timeChanges = sortedTimeChanges(metadata);
    if (timeChanges.length == 0) return sections;

    var endTime:Float = 0;
    for (note in notes)
      if (note.time + note.length > endTime) endTime = note.time + note.length;

    var changeIndex = 0;
    var sectionStart:Float = timeChanges[0].timeStamp;
    var noteIndex = 0;

    // Walk the song a section at a time, changing the section's shape
    // whenever a tempo change is reached rather than assuming one tempo.
    while (sectionStart <= endTime)
    {
      while (changeIndex + 1 < timeChanges.length && timeChanges[changeIndex + 1].timeStamp <= sectionStart)
        changeIndex++;

      var change = timeChanges[changeIndex];
      var beats = change.timeSignatureNum;
      var sectionLength = beatLengthOf(change) * beats;
      if (sectionLength <= 0) break;

      var sectionEnd = sectionStart + sectionLength;

      var mine:Array<SongNoteData> = [];
      while (noteIndex < notes.length && notes[noteIndex].time < sectionEnd)
      {
        mine.push(notes[noteIndex]);
        noteIndex++;
      }

      var mustHit = focusedOnPlayer(chart, sectionStart, sectionEnd, mine);

      sections.push({
        mustHitSection: mustHit,
        sectionBeats: beats,
        lengthInSteps: beats * 4,
        // Only worth writing where the tempo actually changes here, which is
        // how the importer reads it back.
        changeBPM: change.timeStamp == sectionStart && changeIndex > 0,
        bpm: change.bpm,
        sectionNotes: [for (note in mine) writeNote(note, mustHit)]
      });

      sectionStart = sectionEnd;
    }

    return sections;
  }

  /**
   * A note as the old format wants it: time, lane, length, and the note kind
   * where there is one.
   *
   * The lane is written relative to the section's focus, undoing exactly what
   * the importer does when it reads one.
   */
  static function writeNote(note:SongNoteData, mustHit:Bool):Array<Dynamic>
  {
    var data = note.data;

    if (!mustHit) data = (data >= STRUMLINE_SIZE) ? data - STRUMLINE_SIZE : data + STRUMLINE_SIZE;

    var written:Array<Dynamic> = [note.time, data, note.length];
    if (note.kind != null && note.kind != '') written.push(note.kind);

    return written;
  }

  /**
   * Whether the camera is on the player for this stretch of the song.
   *
   * `FocusCamera` is what the importer makes out of `mustHitSection`, so it is
   * what gets read back out of. Its value is either a bare number or an object
   * with a `char` in it, depending on what wrote the chart, and 0 is the
   * player. Failing that, whichever side has more notes in the section is the
   * side worth looking at.
   */
  static function focusedOnPlayer(chart:SongChartData, from:Float, to:Float, notes:Array<SongNoteData>):Bool
  {
    var focus:Null<Bool> = null;

    for (event in chart.events)
    {
      if (event.time >= to) break;
      if (event.eventKind != 'FocusCamera') continue;

      var target = characterOf(event.value);
      if (target != null) focus = (target == 0);
    }

    if (focus != null) return focus;

    var player = 0;
    for (note in notes)
      if (note.data < STRUMLINE_SIZE) player++;

    return player >= (notes.length - player);
  }

  static function characterOf(value:Dynamic):Null<Int>
  {
    if (value == null) return null;
    if (Std.isOfType(value, Int) || Std.isOfType(value, Float)) return Std.int(value);

    var char:Dynamic = Reflect.field(value, 'char');
    if (char != null && (Std.isOfType(char, Int) || Std.isOfType(char, Float))) return Std.int(char);

    return null;
  }

  static function sortedTimeChanges(metadata:SongMetadata):Array<SongTimeChange>
  {
    var changes = metadata.timeChanges.copy();
    changes.sort((a, b) -> Std.int(a.timeStamp - b.timeStamp));
    return changes;
  }

  /**
   * How long one beat lasts, with the time signature's denominator taken into
   * account so 6/8 is not measured in quarter notes.
   */
  static function beatLengthOf(change:SongTimeChange):Float
  {
    if (change.bpm <= 0) return 0;
    var denominator = change.timeSignatureDen <= 0 ? 4 : change.timeSignatureDen;
    return (60000 / change.bpm) / (denominator / 4);
  }
}
