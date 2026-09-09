import 'package:flutter/material.dart';

import '../../data/song_chart.dart';
import '../../theme/funkin_theme.dart';
import 'chart_controller.dart';

/// The events near the playhead, and a way to add one.
///
/// Events are the part of a chart with no fixed shape — a kind is a string and
/// its value is whatever that kind reads — so this shows the value as the JSON
/// it is rather than pretending to know the fields. The kinds the base game
/// ships are offered as a starting point.
class EventSheet extends StatefulWidget {
  const EventSheet({super.key, required this.controller, required this.timeMs});

  final ChartController controller;

  /// Where the sheet was opened from; a new event lands here.
  final double timeMs;

  @override
  State<EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<EventSheet> {
  /// The event kinds in `assets/data/events`, which is what the base game
  /// fires. A mod can add its own, so the field is free text and these are
  /// only suggestions.
  static const List<String> _knownKinds = [
    'FocusCamera',
    'PlayAnimation',
    'ZoomCamera',
    'SetCameraBop',
    'ScrollSpeed',
    'PlaySound',
  ];

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    // Everything within a couple of seconds either way, which is about what
    // fits on screen at a normal zoom.
    final nearby = controller.events
        .where((event) => (event.time - widget.timeMs).abs() < 2500)
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('Events',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _edit(null),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),
            if (nearby.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Text('Nothing around the playhead.',
                    style: TextStyle(color: FunkinColors.muted)),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: nearby.length,
                  itemBuilder: (context, index) {
                    final event = nearby[index];
                    return ListTile(
                      title: Text(event.kind),
                      subtitle: Text(
                        '${(event.time / 1000).toStringAsFixed(2)}s · ${event.summary}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: FunkinColors.muted),
                      ),
                      onTap: () => _edit(event),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          controller.removeEvent(event);
                          setState(() {});
                        },
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(SongEventData? event) async {
    final kindField = TextEditingController(text: event?.kind ?? 'FocusCamera');
    final valueField = TextEditingController(
        text: ChartController.formatEventValue(event?.value));

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FunkinColors.panel,
        title: Text(event == null ? 'New event' : 'Edit event'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: kindField,
                decoration: const InputDecoration(labelText: 'Kind'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final kind in _knownKinds)
                    ActionChip(
                      label: Text(kind, style: const TextStyle(fontSize: 11)),
                      onPressed: () => kindField.text = kind,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueField,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Value',
                  helperText: 'JSON, a number, or plain text',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final kind = kindField.text.trim();
    if (kind.isEmpty) return;

    final value = ChartController.parseEventValue(valueField.text);

    if (event == null) {
      widget.controller.addEvent(kind, value, widget.timeMs);
    } else {
      widget.controller.updateEvent(event, kind, value);
    }

    if (mounted) setState(() {});
  }
}
