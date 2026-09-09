import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/song_chart.dart';
import '../../services/audio_engine.dart';
import '../../services/workspace.dart';
import '../../theme/funkin_theme.dart';
import '../../ui/widgets/confirm.dart';
import '../metadata/metadata_editor_page.dart';
import 'chart_controller.dart';
import 'chart_geometry.dart';
import 'chart_grid_painter.dart';
import 'event_sheet.dart';

/// The chart editor.
///
/// One surface does the lot: a tap puts a note down or takes it away, a drag
/// scrolls the song, a pinch zooms and a long press pulls a hold out of a note.
/// That is deliberate — there is no room on a phone for a mode for each, and
/// having to switch tools to delete something you just misplaced is the thing
/// that makes charting on a touchscreen tiring.
class ChartEditorPage extends StatefulWidget {
  const ChartEditorPage({
    super.key,
    required this.workspace,
    required this.project,
  });

  final Workspace workspace;
  final SongProject project;

  @override
  State<ChartEditorPage> createState() => _ChartEditorPageState();
}

class _ChartEditorPageState extends State<ChartEditorPage>
    with SingleTickerProviderStateMixin {
  late final ChartController _controller;
  late final AudioEngine _audio;
  late final Ticker _ticker;

  /// The hold being dragged out, if one is.
  ({SongNoteData note, double endMs})? _drag;

  double _zoomAtGestureStart = 1;
  bool _isScrubbing = false;

  String? _audioMessage;
  bool _loadingAudio = true;

  @override
  void initState() {
    super.initState();

    _audio = AudioEngine();
    _controller = ChartController(
      workspace: widget.workspace,
      project: widget.project,
      audio: _audio,
    )..addListener(_onControllerChanged);

    // One tick per frame keeps the grid on the audio rather than on a timer
    // that happens to fire near it.
    _ticker = createTicker((_) => _controller.followAudio())..start();

    _loadAudio();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _audio.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadAudio() async {
    final tracks = await widget.workspace.audioTracks(widget.project.ref);

    if (tracks.isEmpty) {
      if (mounted) {
        setState(() {
          _loadingAudio = false;
          _audioMessage = 'No audio in songs/${widget.project.id}';
        });
      }
      return;
    }

    // The instrumental for a variation is named after it — Inst-erect — and
    // falls back to the plain one, which is what the game does too.
    final variation = widget.project.variation;
    final instrumental = tracks['Inst-$variation'] ?? tracks['Inst'];

    if (instrumental == null) {
      if (mounted) {
        setState(() {
          _loadingAudio = false;
          _audioMessage = 'No instrumental track found';
        });
      }
      return;
    }

    final vocals = <String, String>{};
    for (final entry in tracks.entries) {
      if (!entry.key.startsWith('Voices')) continue;

      // Only this variation's vocals, or the unsuffixed ones when it has none
      // of its own. Loading every variation's would play them over each other.
      final matchesVariation = entry.key.endsWith('-$variation');
      final isPlain = !entry.key.contains('-') ||
          !widget.project.metadata.playData.songVariations
              .any((name) => entry.key.endsWith('-$name'));

      if (variation == 'default' ? isPlain : matchesVariation) {
        vocals[entry.key] = entry.value.id;
      }
    }

    final offsets = <String, double>{
      for (final name in vocals.keys)
        name: widget.project.metadata.offsets
            .vocalOffset(name.replaceFirst('Voices-', ''), variation: variation),
    };

    try {
      await _audio.load(
        instrumental: instrumental.id,
        vocals: vocals,
        offsets: offsets,
      );
      if (mounted) setState(() => _loadingAudio = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadingAudio = false;
          _audioMessage = 'That audio would not play';
        });
      }
    }
  }

  // -- gestures -----------------------------------------------------------

  ChartGeometry _geometryFor(Size size) => ChartGeometry(
        size: size,
        timeMs: _controller.timeMs,
        pixelsPerMs: _controller.zoom,
      );

  void _onTapUp(TapUpDetails details, Size size) {
    final geometry = _geometryFor(size);
    final position = details.localPosition;

    final lane = geometry.laneForX(position.dx);
    final time = geometry.timeForY(position.dy);

    if (lane == null) {
      _openEventsAt(time);
      return;
    }

    if (_controller.tool == ChartTool.select) {
      final tolerance = _controller.conductor.snapIncrement(time, _controller.snap);
      final note = _controller.noteAt(lane, time, tolerance);
      if (note != null) _controller.toggleSelected(note);
      return;
    }

    _controller.toggleNote(lane, time);
  }

  void _onLongPressStart(LongPressStartDetails details, Size size) {
    final geometry = _geometryFor(size);
    final position = details.localPosition;

    final lane = geometry.laneForX(position.dx);
    if (lane == null) return;

    final time = geometry.timeForY(position.dy);
    final tolerance = _controller.conductor.snapIncrement(time, _controller.snap);

    final note = _controller.noteAt(lane, time, tolerance);
    if (note == null) return;

    setState(() => _drag = (note: note, endMs: note.endTime));
  }

  void _onLongPressMove(LongPressMoveUpdateDetails details, Size size) {
    final drag = _drag;
    if (drag == null) return;

    final geometry = _geometryFor(size);
    final time = geometry.timeForY(details.localPosition.dy);

    setState(() => _drag = (note: drag.note, endMs: time));
  }

  void _onLongPressEnd() {
    final drag = _drag;
    setState(() => _drag = null);
    if (drag == null) return;

    _controller.resizeHold(drag.note, drag.endMs);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _zoomAtGestureStart = _controller.zoom;
    _isScrubbing = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Two fingers is a zoom; one is a scroll. Flutter reports both through the
    // same callback, and the pointer count is the only honest way to tell.
    if (details.pointerCount > 1) {
      _controller.setZoom(_zoomAtGestureStart * details.verticalScale);
      return;
    }

    if (!_isScrubbing) {
      _isScrubbing = true;
      if (_audio.isPlaying) _audio.pause();
    }

    // Dragging down moves back through the song, the way a paper roll would.
    final delta = details.focalPointDelta.dy / _controller.zoom;
    _controller.seek(_controller.timeMs - delta);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _isScrubbing = false;
  }

  // -- actions ------------------------------------------------------------

  Future<void> _save() async {
    try {
      await _controller.save();
      _say('Saved ${widget.project.id}');
    } catch (error) {
      _say('Could not save: $error');
    }
  }

  Future<bool> _confirmLeaving() async {
    if (!_controller.isDirty) return true;

    final choice = await confirm(
      context,
      title: 'Leave without saving?',
      message: 'This chart has changes that are not written to the file yet.',
      confirmLabel: 'Discard',
      destructive: true,
    );

    return choice;
  }

  void _openEventsAt(double timeMs) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: FunkinColors.panel,
      isScrollControlled: true,
      builder: (context) => EventSheet(controller: _controller, timeMs: timeMs),
    );
  }

  Future<void> _openMetadata() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => MetadataEditorPage(
        workspace: widget.workspace,
        project: widget.project,
      ),
    ));

    // The tempo map may have moved under the grid while that was open.
    _controller.refreshTiming();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // -- building -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        final leave = await _confirmLeaving();
        if (!leave || !context.mounted) return;

        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.project.metadata.songName,
                  style: const TextStyle(fontSize: 16)),
              Text(
                '${widget.project.variation} · ${_controller.difficulty}'
                '${_controller.isDirty ? ' · unsaved' : ''}',
                style: const TextStyle(fontSize: 12, color: FunkinColors.muted),
              ),
            ],
          ),
          actions: [
            IconButton(
              onPressed: _controller.canUndo ? _controller.undo : null,
              icon: const Icon(Icons.undo),
              tooltip: 'Undo',
            ),
            IconButton(
              onPressed: _controller.canRedo ? _controller.redo : null,
              icon: const Icon(Icons.redo),
              tooltip: 'Redo',
            ),
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save',
            ),
            PopupMenuButton<String>(
              onSelected: (value) => switch (value) {
                'metadata' => _openMetadata(),
                'flip' => _controller.flipSelection(),
                'delete' => _controller.removeSelection(),
                _ => null,
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'metadata', child: Text('Song metadata')),
                PopupMenuItem(value: 'flip', child: Text('Flip selection sides')),
                PopupMenuItem(value: 'delete', child: Text('Delete selection')),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: _StrumHeader(controller: _controller),
          ),
        ),
        body: Column(
          children: [
            if (_audioMessage != null)
              _Banner(message: _audioMessage!)
            else if (_loadingAudio)
              const _Banner(message: 'Loading audio…'),
            Expanded(child: _buildGrid()),
            _TransportBar(
              controller: _controller,
              audio: _audio,
              onOpenEvents: () => _openEventsAt(_controller.timeMs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _onTapUp(details, size),
          onLongPressStart: (details) => _onLongPressStart(details, size),
          onLongPressMoveUpdate: (details) => _onLongPressMove(details, size),
          onLongPressEnd: (_) => _onLongPressEnd(),
          onLongPressCancel: _onLongPressEnd,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: CustomPaint(
            size: size,
            painter: ChartGridPainter(
              geometry: _geometryFor(size),
              conductor: _controller.conductor,
              notes: _controller.notes,
              events: _controller.events,
              selection: _controller.selection,
              snap: _controller.snap,
              dragPreview: _drag,
            ),
          ),
        );
      },
    );
  }
}

/// The eight arrows across the top, so a lane can be read without counting.
class _StrumHeader extends StatelessWidget {
  const _StrumHeader({required this.controller});

  final ChartController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          const SizedBox(width: ChartGeometry.gutter),
          for (var column = 0; column < 8; column++)
            Expanded(
              child: _StrumIcon(
                lane: ChartGeometry.laneForColumn(column),
                showSeam: column == 4,
              ),
            ),
        ],
      ),
    );
  }
}

class _StrumIcon extends StatelessWidget {
  const _StrumIcon({required this.lane, required this.showSeam});

  final int lane;
  final bool showSeam;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: showSeam
            ? const Border(left: BorderSide(color: FunkinColors.pink, width: 2))
            : null,
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CustomPaint(painter: _ArrowPainter(lane % 4)),
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter(this.direction);

  final int direction;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      arrowPath(Offset.zero & size, direction),
      Paint()..color = FunkinColors.arrows[direction],
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.direction != direction;
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: FunkinColors.raised,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(message,
          style: const TextStyle(color: FunkinColors.muted, fontSize: 12)),
    );
  }
}

/// Play, position, snap and zoom, along the bottom where a thumb reaches.
class _TransportBar extends StatelessWidget {
  const _TransportBar({
    required this.controller,
    required this.audio,
    required this.onOpenEvents,
  });

  final ChartController controller;
  final AudioEngine audio;
  final VoidCallback onOpenEvents;

  static const List<int> _snaps = [4, 8, 12, 16, 24, 32, 48];

  @override
  Widget build(BuildContext context) {
    final length = controller.lengthMs;

    return Container(
      color: FunkinColors.panel,
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 6,
        bottom: 6 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  _clock(controller.timeMs),
                  style: const TextStyle(
                      fontSize: 12,
                      color: FunkinColors.muted,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
              Expanded(
                child: Slider(
                  value: controller.timeMs.clamp(0, length),
                  max: length <= 0 ? 1 : length,
                  onChanged: (value) => controller.seek(value),
                ),
              ),
              SizedBox(
                width: 62,
                child: Text(
                  _clock(length),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12,
                      color: FunkinColors.muted,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                onPressed: () => controller.nudge(-1),
                icon: const Icon(Icons.keyboard_arrow_up),
                tooltip: 'Back one step',
              ),
              IconButton.filled(
                onPressed: controller.togglePlayback,
                icon: Icon(audio.isPlaying ? Icons.pause : Icons.play_arrow),
                tooltip: audio.isPlaying ? 'Pause' : 'Play',
              ),
              IconButton(
                onPressed: () => controller.nudge(1),
                icon: const Icon(Icons.keyboard_arrow_down),
                tooltip: 'On one step',
              ),
              const SizedBox(width: 4),
              _Chip(
                label: '1/${controller.snap}',
                onTap: () {
                  final next = _snaps[(_snaps.indexOf(controller.snap) + 1) % _snaps.length];
                  controller.setSnap(next);
                },
              ),
              const SizedBox(width: 6),
              _Chip(
                label: controller.tool == ChartTool.place ? 'Place' : 'Select',
                active: controller.tool == ChartTool.select,
                onTap: () => controller.setTool(controller.tool == ChartTool.place
                    ? ChartTool.select
                    : ChartTool.place),
              ),
              const Spacer(),
              if (controller.selection.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text('${controller.selection.length}',
                      style: const TextStyle(color: FunkinColors.muted)),
                ),
              IconButton(
                onPressed: onOpenEvents,
                icon: const Icon(Icons.bolt_outlined),
                tooltip: 'Events',
              ),
              _DifficultyButton(controller: controller),
            ],
          ),
        ],
      ),
    );
  }

  static String _clock(double milliseconds) {
    final total = milliseconds / 1000;
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).floor().toString().padLeft(2, '0');
    final hundredths =
        ((total - total.floor()) * 100).floor().toString().padLeft(2, '0');
    return '$minutes:$seconds.$hundredths';
  }
}

class _DifficultyButton extends StatelessWidget {
  const _DifficultyButton({required this.controller});

  final ChartController controller;

  @override
  Widget build(BuildContext context) {
    final difficulties = {
      ...controller.project.chart.difficulties,
      ...controller.project.metadata.playData.difficulties,
      controller.difficulty,
    }.toList()
      ..sort();

    return PopupMenuButton<String>(
      onSelected: controller.setDifficulty,
      itemBuilder: (context) => [
        for (final name in difficulties)
          PopupMenuItem(
            value: name,
            child: Row(
              children: [
                if (name == controller.difficulty)
                  const Icon(Icons.check, size: 16)
                else
                  const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(name),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Text(
          controller.difficulty,
          style: const TextStyle(color: FunkinColors.text),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onTap, this.active = false});

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minWidth: 52, minHeight: 40),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? FunkinColors.pink : FunkinColors.raised,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(label, style: const TextStyle(color: FunkinColors.text)),
      ),
    );
  }
}
