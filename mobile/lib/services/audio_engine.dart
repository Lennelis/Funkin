import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// The song, playing.
///
/// A chart is written against several tracks at once — the instrumental and
/// one vocal track per side — and they have to stay together, so one player is
/// nominated the clock and the others are pulled back to it whenever they
/// drift. The alternative, mixing them into one buffer up front, would mean
/// decoding several minutes of audio before the editor could open.
class AudioEngine {
  AudioEngine();

  final AudioPlayer _clock = AudioPlayer();
  final Map<String, AudioPlayer> _extras = {};
  final Map<String, double> _offsets = {};

  /// How far a track is allowed to wander before it is put back. Below about
  /// 30ms nobody hears it, and correcting more often than that is audible in
  /// itself.
  static const Duration _driftLimit = Duration(milliseconds: 40);

  Duration _length = Duration.zero;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get isPlaying => _clock.playing;
  Duration get length => _length;

  /// Where the song is now, in milliseconds. just_audio carries the position
  /// forward against the system clock between the updates it gets from the
  /// platform, so this is fine to read once a frame.
  double get positionMs => _clock.position.inMicroseconds / 1000.0;

  Stream<PlayerState> get stateChanges => _clock.playerStateStream;

  /// Point the engine at a set of tracks. [instrumental] is the clock, so it
  /// has to be there; the rest are optional and each may carry its own offset
  /// in milliseconds from the song's metadata.
  Future<void> load({
    required String instrumental,
    Map<String, String> vocals = const {},
    Map<String, double> offsets = const {},
  }) async {
    await stop();
    await _disposeExtras();
    _offsets
      ..clear()
      ..addAll(offsets);

    _length = await _setSource(_clock, instrumental) ?? Duration.zero;

    for (final entry in vocals.entries) {
      final player = AudioPlayer();
      final duration = await _setSource(player, entry.value);

      if (duration == null) {
        await player.dispose();
        continue;
      }

      _extras[entry.key] = player;
      // A vocal track can run past the end of the instrumental; the editor
      // still has to be able to scroll to the end of it.
      if (duration > _length) _length = duration;
    }

    _loaded = true;
  }

  Future<Duration?> _setSource(AudioPlayer player, String uri) async {
    try {
      // Content URIs from the folder picker go straight to the platform
      // player, so nothing has to be copied out of the mod folder first.
      return await player.setAudioSource(AudioSource.uri(Uri.parse(uri)));
    } catch (error) {
      return null;
    }
  }

  /// Whether a track is being heard. Turning the opponent's voice off while
  /// charting their half is the usual reason to touch this.
  bool isMuted(String track) => (_extras[track]?.volume ?? 1) == 0;

  Future<void> setMuted(String track, bool muted) async {
    if (track == instrumentalTrack) {
      await _clock.setVolume(muted ? 0 : 1);
      return;
    }
    await _extras[track]?.setVolume(muted ? 0 : 1);
  }

  bool get isInstrumentalMuted => _clock.volume == 0;

  List<String> get vocalTracks => _extras.keys.toList();

  static const String instrumentalTrack = 'Inst';

  Future<void> play() async {
    if (!_loaded) return;

    // Everything is started from a known position rather than resumed where
    // it happens to be, because a track that was paused mid-correction is
    // already out by however much the last seek had not settled.
    await seek(positionMs);

    await Future.wait([
      _clock.play(),
      for (final player in _extras.values) player.play(),
    ]);
  }

  Future<void> pause() async {
    await Future.wait([
      _clock.pause(),
      for (final player in _extras.values) player.pause(),
    ]);
  }

  Future<void> stop() async {
    await pause();
    if (_loaded) await seek(0);
  }

  Future<void> seek(double milliseconds) async {
    if (!_loaded) return;

    final target = _clamp(milliseconds);

    await _clock.seek(Duration(microseconds: (target * 1000).round()));

    for (final entry in _extras.entries) {
      final offset = _offsets[entry.key] ?? 0;
      await entry.value
          .seek(Duration(microseconds: ((target + offset) * 1000).round()));
    }
  }

  /// Put any track that has wandered back where it belongs. Called from the
  /// editor's frame ticker while playing; doing nothing is the common case.
  Future<void> correctDrift() async {
    if (!_loaded || !isPlaying || _extras.isEmpty) return;

    final clockPosition = _clock.position;

    for (final entry in _extras.entries) {
      final offset = _offsets[entry.key] ?? 0;
      final expected =
          clockPosition + Duration(microseconds: (offset * 1000).round());
      final drift = entry.value.position - expected;

      if (drift.abs() > _driftLimit) await entry.value.seek(expected);
    }
  }

  double _clamp(double milliseconds) {
    final end = _length.inMicroseconds / 1000.0;
    if (milliseconds < 0) return 0;
    if (end > 0 && milliseconds > end) return end;
    return milliseconds;
  }

  Future<void> _disposeExtras() async {
    for (final player in _extras.values) {
      await player.dispose();
    }
    _extras.clear();
  }

  Future<void> dispose() async {
    await _disposeExtras();
    await _clock.dispose();
  }
}
