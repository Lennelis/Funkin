import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/character_data.dart';
import '../../services/sparrow_atlas.dart';
import '../../services/storage/storage_backend.dart';
import '../../services/workspace.dart';
import '../../theme/funkin_theme.dart';
import '../../ui/widgets/confirm.dart';

/// The character editor.
///
/// The thing a character file mostly needs is its offsets nudged until the
/// animations line up, and that cannot be done by typing numbers into a form
/// and guessing — you have to see it. So this plays the animation from the
/// character's own sheet and moves it as you drag.
class CharacterEditorPage extends StatefulWidget {
  const CharacterEditorPage({
    super.key,
    required this.workspace,
    required this.file,
  });

  final Workspace workspace;
  final StorageEntry file;

  @override
  State<CharacterEditorPage> createState() => _CharacterEditorPageState();
}

class _CharacterEditorPageState extends State<CharacterEditorPage>
    with SingleTickerProviderStateMixin {
  CharacterData? _character;
  SparrowAtlas? _atlas;
  ui.Image? _sheet;

  String? _problem;
  bool _loading = true;
  bool _dirty = false;

  int _animationIndex = 0;
  int _frameIndex = 0;
  bool _playing = true;
  double _sinceFrame = 0;
  Duration _lastTick = Duration.zero;

  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    _load();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sheet?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final contents = await widget.workspace.storage.readString(widget.file.id);
      final character = CharacterData.fromJson(_decode(contents));

      setState(() => _character = character);

      await _loadSheet(character);
    } catch (error) {
      setState(() => _problem = 'Could not read that character: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _decode(String contents) {
    final decoded = json.decode(contents);
    if (decoded is! Map) throw const FormatException('Not a JSON object');
    return decoded.cast<String, dynamic>();
  }

  /// Load the sheet the character is drawn from.
  ///
  /// Only sparrow sheets can be shown. The animate-atlas render types are a
  /// different format altogether — a whole Flash timeline rather than a grid of
  /// frames — and drawing one properly is its own project, so those say so
  /// rather than showing something wrong.
  Future<void> _loadSheet(CharacterData character) async {
    if (!character.renderType.contains('sparrow')) {
      setState(() => _problem =
          'Preview is for sparrow sheets. This one is ${character.renderType}, '
          'so the offsets below are editable but not shown.');
      return;
    }

    final png =
        await widget.workspace.resolveImage(character.assetPath, 'png');
    final xml =
        await widget.workspace.resolveImage(character.assetPath, 'xml');

    if (png == null || xml == null) {
      setState(() => _problem =
          'No sheet found at ${CharacterData.stripLibrary(character.assetPath)}');
      return;
    }

    final atlas =
        SparrowAtlas.parse(await widget.workspace.storage.readString(xml.id));
    final bytes = await widget.workspace.storage.readBytes(png.id);
    final image = await decodeImageFromList(bytes);

    if (!mounted) return;
    setState(() {
      _atlas = atlas;
      _sheet = image;
      _problem = null;
    });
  }

  void _tick(Duration elapsed) {
    if (!_playing || _atlas == null) {
      _lastTick = elapsed;
      return;
    }

    final delta = (elapsed - _lastTick).inMicroseconds / 1000000.0;
    _lastTick = elapsed;

    final frames = _currentFrames;
    if (frames.length < 2) return;

    // 24 is what the game uses when an animation does not say otherwise.
    final rate = (_currentAnimation?.frameRate ?? 24).clamp(1, 120);
    _sinceFrame += delta;

    if (_sinceFrame < 1 / rate) return;

    _sinceFrame = 0;
    setState(() => _frameIndex = (_frameIndex + 1) % frames.length);
  }

  AnimationData? get _currentAnimation {
    final animations = _character?.animations;
    if (animations == null || animations.isEmpty) return null;
    if (_animationIndex >= animations.length) return animations.first;
    return animations[_animationIndex];
  }

  List<AtlasFrame> get _currentFrames {
    final animation = _currentAnimation;
    final atlas = _atlas;
    if (animation == null || atlas == null) return const [];

    final all = atlas.framesFor(animation.prefix);

    // An animation can name the frames it wants out of the prefix, which is
    // how a sheet holding several animations under one name is split up.
    final indices = animation.frameIndices;
    if (indices == null || indices.isEmpty) return all;

    return [
      for (final index in indices)
        if (index >= 0 && index < all.length) all[index],
    ];
  }

  Future<void> _save() async {
    final character = _character;
    if (character == null) return;

    try {
      await widget.workspace.storage
          .writeString(widget.file.id, encodeJson(character.toJson()));

      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved ${widget.file.name}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  void _nudge(double x, double y) {
    final animation = _currentAnimation;
    if (animation == null) return;

    setState(() {
      animation.setOffsets(animation.offsetX + x, animation.offsetY + y);
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final character = _character;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        if (_dirty) {
          final leave = await confirm(
            context,
            title: 'Leave without saving?',
            message: 'This character has changes that are not written yet.',
            confirmLabel: 'Discard',
            destructive: true,
          );
          if (!leave) return;
        }

        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(character?.name ?? widget.file.stem),
          actions: [
            IconButton(
              onPressed: () => setState(() => _playing = !_playing),
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              tooltip: _playing ? 'Pause' : 'Play',
            ),
            IconButton(
              onPressed: character == null ? null : _save,
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : character == null
                ? Center(child: Text(_problem ?? 'Nothing to show'))
                : _buildEditor(character),
      ),
    );
  }

  Widget _buildEditor(CharacterData character) {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            // Dragging the character is the offset. Nothing else in the editor
            // needs a gesture, so the whole stage can be one.
            onPanUpdate: (details) =>
                _nudge(details.delta.dx, details.delta.dy),
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: _sheet == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _problem ?? 'No preview',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: FunkinColors.muted),
                        ),
                      ),
                    )
                  : CustomPaint(
                      painter: _CharacterPainter(
                        sheet: _sheet!,
                        frames: _currentFrames,
                        frameIndex: _frameIndex,
                        offsetX: _currentAnimation?.offsetX ?? 0,
                        offsetY: _currentAnimation?.offsetY ?? 0,
                        flipX: character.flipX ?? false,
                        scale: character.scale ?? 1,
                      ),
                    ),
            ),
          ),
        ),
        _OffsetPad(
          animation: _currentAnimation,
          onNudge: _nudge,
          onReset: () {
            final animation = _currentAnimation;
            if (animation == null) return;
            setState(() {
              animation.offsets = [0, 0];
              _dirty = true;
            });
          },
        ),
        SizedBox(
          height: 88,
          child: _AnimationStrip(
            character: character,
            atlas: _atlas,
            selected: _animationIndex,
            onSelect: (index) => setState(() {
              _animationIndex = index;
              _frameIndex = 0;
              _sinceFrame = 0;
            }),
          ),
        ),
      ],
    );
  }
}

class _CharacterPainter extends CustomPainter {
  _CharacterPainter({
    required this.sheet,
    required this.frames,
    required this.frameIndex,
    required this.offsetX,
    required this.offsetY,
    required this.flipX,
    required this.scale,
  });

  final ui.Image sheet;
  final List<AtlasFrame> frames;
  final int frameIndex;
  final double offsetX;
  final double offsetY;
  final bool flipX;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (frames.isEmpty) return;

    final frame = frames[frameIndex % frames.length];

    // Fit the frame's untrimmed size to the stage, so an animation whose
    // frames were packed at different sizes does not jump about.
    final fit = _fitScale(size, frame) * scale;

    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.62);
    if (flipX) canvas.scale(-1, 1);
    canvas.scale(fit, fit);

    // The offset in a character file moves the sprite the opposite way, which
    // is how the game applies it.
    canvas.translate(-offsetX, -offsetY);

    final source = Rect.fromLTWH(frame.x, frame.y, frame.width, frame.height);
    final destination = Rect.fromLTWH(
      -frame.frameWidth / 2 + frame.offsetX,
      -frame.frameHeight + frame.offsetY,
      frame.width,
      frame.height,
    );

    canvas.drawImageRect(sheet, source, destination, Paint());
    canvas.restore();

    // Where the character's feet sit, which is what the offsets are lining up.
    final ground = Paint()
      ..color = FunkinColors.pink.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height * 0.62),
      Offset(size.width, size.height * 0.62),
      ground,
    );
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      ground,
    );
  }

  double _fitScale(Size size, AtlasFrame frame) {
    final width = frame.frameWidth;
    final height = frame.frameHeight;
    if (width <= 0 || height <= 0) return 1;

    final byWidth = (size.width * 0.7) / width;
    final byHeight = (size.height * 0.8) / height;
    return byWidth < byHeight ? byWidth : byHeight;
  }

  @override
  bool shouldRepaint(_CharacterPainter old) =>
      old.frameIndex != frameIndex ||
      old.frames != frames ||
      old.offsetX != offsetX ||
      old.offsetY != offsetY ||
      old.flipX != flipX ||
      old.scale != scale ||
      old.sheet != sheet;
}

/// The offset controls: drag the character, or step it a pixel at a time when
/// a drag is too coarse.
class _OffsetPad extends StatelessWidget {
  const _OffsetPad({
    required this.animation,
    required this.onNudge,
    required this.onReset,
  });

  final AnimationData? animation;
  final void Function(double x, double y) onNudge;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final current = animation;

    return Container(
      color: FunkinColors.panel,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current?.name ?? 'No animation',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  current == null
                      ? ''
                      : 'offset ${_trim(current.offsetX)}, ${_trim(current.offsetY)}'
                          '  ·  ${current.prefix}',
                  style:
                      const TextStyle(color: FunkinColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => onNudge(-1, 0),
            icon: const Icon(Icons.chevron_left),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => onNudge(0, -1),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.keyboard_arrow_up, size: 20),
                ),
              ),
              InkWell(
                onTap: () => onNudge(0, 1),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.keyboard_arrow_down, size: 20),
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: () => onNudge(1, 0),
            icon: const Icon(Icons.chevron_right),
          ),
          IconButton(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Zero the offset',
          ),
        ],
      ),
    );
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : value.toStringAsFixed(1);
}

class _AnimationStrip extends StatelessWidget {
  const _AnimationStrip({
    required this.character,
    required this.atlas,
    required this.selected,
    required this.onSelect,
  });

  final CharacterData character;
  final SparrowAtlas? atlas;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: character.animations.length,
      itemBuilder: (context, index) {
        final animation = character.animations[index];
        final isSelected = index == selected;

        // An animation whose prefix is not in the sheet will play nothing, and
        // it is much easier to fix when the list says which one.
        final missing =
            atlas != null && atlas!.framesFor(animation.prefix).isEmpty;

        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: InkWell(
            onTap: () => onSelect(index),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(minWidth: 84),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? FunkinColors.pink : FunkinColors.raised,
                borderRadius: BorderRadius.circular(10),
                border: missing
                    ? Border.all(color: Colors.orangeAccent, width: 1)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(animation.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    missing ? 'no frames' : animation.prefix,
                    style: TextStyle(
                      fontSize: 11,
                      color: missing ? Colors.orangeAccent : FunkinColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
