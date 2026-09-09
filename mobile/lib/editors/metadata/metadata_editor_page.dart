import 'package:flutter/material.dart';

import '../../data/song_metadata.dart';
import '../../services/workspace.dart';
import '../../theme/funkin_theme.dart';
import '../../ui/widgets/confirm.dart';

/// The other half of a song: who is in it, where it happens, and how fast.
///
/// The tempo map is the part that matters most here — every line the chart
/// editor draws comes out of it — so it gets a proper editor rather than a
/// single BPM box.
class MetadataEditorPage extends StatefulWidget {
  const MetadataEditorPage({
    super.key,
    required this.workspace,
    required this.project,
  });

  final Workspace workspace;
  final SongProject project;

  @override
  State<MetadataEditorPage> createState() => _MetadataEditorPageState();
}

class _MetadataEditorPageState extends State<MetadataEditorPage> {
  late final SongMetadata _metadata = widget.project.metadata;

  late final TextEditingController _songName =
      TextEditingController(text: _metadata.songName);
  late final TextEditingController _artist =
      TextEditingController(text: _metadata.artist);
  late final TextEditingController _charter =
      TextEditingController(text: _metadata.charter ?? '');
  late final TextEditingController _stage =
      TextEditingController(text: _metadata.playData.stage);
  late final TextEditingController _noteStyle =
      TextEditingController(text: _metadata.playData.noteStyle);
  late final TextEditingController _player =
      TextEditingController(text: _metadata.playData.characters.player);
  late final TextEditingController _girlfriend =
      TextEditingController(text: _metadata.playData.characters.girlfriend);
  late final TextEditingController _opponent =
      TextEditingController(text: _metadata.playData.characters.opponent);
  late final TextEditingController _instrumentalOffset = TextEditingController(
      text: _trimNumber(_metadata.offsets.instrumental));

  bool _dirty = false;

  @override
  void dispose() {
    for (final controller in [
      _songName, _artist, _charter, _stage, _noteStyle,
      _player, _girlfriend, _opponent, _instrumentalOffset,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _touch() {
    if (!_dirty) setState(() => _dirty = true);
  }

  /// Take what is in the fields back into the model. Done once at save rather
  /// than on every keystroke, so a half-typed number never becomes the tempo.
  void _collect() {
    _metadata.songName = _songName.text.trim();
    _metadata.artist = _artist.text.trim();

    final charter = _charter.text.trim();
    _metadata.charter = charter.isEmpty ? null : charter;

    _metadata.playData
      ..stage = _stage.text.trim()
      ..noteStyle = _noteStyle.text.trim();

    _metadata.playData.characters
      ..player = _player.text.trim()
      ..girlfriend = _girlfriend.text.trim()
      ..opponent = _opponent.text.trim();

    _metadata.offsets.instrumental =
        double.tryParse(_instrumentalOffset.text.trim()) ?? 0;
  }

  Future<void> _save() async {
    _collect();

    try {
      await widget.workspace.saveMetadata(widget.project);
      if (!mounted) return;

      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Metadata saved')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        if (_dirty) {
          final leave = await confirm(
            context,
            title: 'Leave without saving?',
            message: 'The metadata has changes that are not written yet.',
            confirmLabel: 'Discard',
            destructive: true,
          );
          if (!leave) return;
        }

        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Song metadata'),
          actions: [
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save',
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _Section(
              title: 'Song',
              children: [
                _Field(label: 'Name', controller: _songName, onChanged: _touch),
                _Field(label: 'Artist', controller: _artist, onChanged: _touch),
                _Field(label: 'Charter', controller: _charter, onChanged: _touch),
              ],
            ),
            _Section(
              title: 'Stage',
              children: [
                _Field(label: 'Stage id', controller: _stage, onChanged: _touch),
                _Field(
                    label: 'Note style',
                    controller: _noteStyle,
                    onChanged: _touch),
              ],
            ),
            _Section(
              title: 'Characters',
              children: [
                _Field(
                    label: 'Player', controller: _player, onChanged: _touch),
                _Field(
                    label: 'Girlfriend',
                    controller: _girlfriend,
                    onChanged: _touch),
                _Field(
                    label: 'Opponent',
                    controller: _opponent,
                    onChanged: _touch),
              ],
            ),
            _Section(
              title: 'Difficulties',
              children: [_buildDifficulties()],
            ),
            _Section(
              title: 'Timing',
              children: [_buildTimeChanges()],
            ),
            _Section(
              title: 'Offsets',
              children: [
                _Field(
                  label: 'Instrumental (ms)',
                  controller: _instrumentalOffset,
                  keyboardType:
                      const TextInputType.numberWithOptions(signed: true, decimal: true),
                  onChanged: _touch,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDifficulties() {
    final difficulties = _metadata.playData.difficulties;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final name in difficulties)
          InputChip(
            label: Text(name),
            backgroundColor: FunkinColors.raised,
            onDeleted: difficulties.length <= 1
                ? null
                : () {
                    setState(() {
                      difficulties.remove(name);
                      _dirty = true;
                    });
                  },
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('Add'),
          onPressed: _addDifficulty,
        ),
      ],
    );
  }

  Future<void> _addDifficulty() async {
    final field = TextEditingController();

    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FunkinColors.panel,
        title: const Text('Add difficulty'),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'erect, nightmare…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (added != true) return;

    final name = field.text.trim();
    if (name.isEmpty) return;
    if (_metadata.playData.difficulties.contains(name)) return;

    setState(() {
      _metadata.playData.difficulties.add(name);
      // The chart needs somewhere to put notes for it, or the difficulty is
      // listed in the menu and plays nothing.
      widget.project.chart.notes.putIfAbsent(name, () => []);
      _dirty = true;
    });
  }

  Widget _buildTimeChanges() {
    final changes = _metadata.timeChanges;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < changes.length; index++)
          _TimeChangeRow(
            change: changes[index],
            // The first one is where the song starts, so it has no timestamp
            // to edit and cannot be taken away.
            isFirst: index == 0,
            onChanged: _touch,
            onDelete: index == 0
                ? null
                : () => setState(() {
                      changes.removeAt(index);
                      _dirty = true;
                    }),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              final last = changes.last;
              changes.add(SongTimeChange(
                // A new change eight bars past the last one, which is a more
                // useful starting point than another at the same moment.
                timeStamp: last.timeStamp + last.measureLengthMs * 8,
                bpm: last.bpm,
                timeSignatureNum: last.timeSignatureNum,
                timeSignatureDen: last.timeSignatureDen,
              ));
              changes.sort((a, b) => a.timeStamp.compareTo(b.timeStamp));
              _dirty = true;
            });
          },
          icon: const Icon(Icons.add),
          label: const Text('Add time change'),
        ),
      ],
    );
  }
}

class _TimeChangeRow extends StatelessWidget {
  const _TimeChangeRow({
    required this.change,
    required this.isFirst,
    required this.onChanged,
    this.onDelete,
  });

  final SongTimeChange change;
  final bool isFirst;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: _NumberBox(
              label: isFirst ? 'Start' : 'At (ms)',
              value: change.timeStamp,
              enabled: !isFirst,
              onChanged: (value) {
                change.timeStamp = value;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _NumberBox(
              label: 'BPM',
              value: change.bpm,
              onChanged: (value) {
                // A tempo of zero divides the whole grid by nothing.
                if (value > 0) change.bpm = value;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _NumberBox(
              label: 'Beats',
              value: change.timeSignatureNum.toDouble(),
              onChanged: (value) {
                if (value >= 1) change.timeSignatureNum = value.round();
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _NumberBox(
              label: 'Of',
              value: change.timeSignatureDen.toDouble(),
              onChanged: (value) {
                if (value >= 1) change.timeSignatureDen = value.round();
                onChanged();
              },
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _NumberBox extends StatefulWidget {
  const _NumberBox({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  State<_NumberBox> createState() => _NumberBoxState();
}

class _NumberBoxState extends State<_NumberBox> {
  late final TextEditingController _controller =
      TextEditingController(text: _trimNumber(widget.value));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
      style: const TextStyle(fontSize: 14),
      onChanged: (text) {
        final parsed = double.tryParse(text.trim());
        if (parsed != null) widget.onChanged(parsed);
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: FunkinColors.muted,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

/// `100` rather than `100.0`, which is what a person expects to see in a box
/// they are about to type a tempo into.
String _trimNumber(double value) =>
    value == value.roundToDouble() ? '${value.toInt()}' : '$value';
