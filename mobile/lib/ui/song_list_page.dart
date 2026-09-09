import 'package:flutter/material.dart';

import '../editors/chart/chart_editor_page.dart';
import '../services/workspace.dart';
import '../theme/funkin_theme.dart';

/// Every song in the folder, and which variations each one has.
class SongListPage extends StatefulWidget {
  const SongListPage({super.key, required this.workspace});

  final Workspace workspace;

  @override
  State<SongListPage> createState() => _SongListPageState();
}

class _SongListPageState extends State<SongListPage> {
  String _filter = '';
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final songs = widget.workspace.songs
        .where((song) => song.id.toLowerCase().contains(_filter.toLowerCase()))
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Songs')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Find a song',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _filter = value),
            ),
          ),
          if (_opening) const LinearProgressIndicator(),
          Expanded(
            child: songs.isEmpty
                ? const Center(
                    child: Text('Nothing here.',
                        style: TextStyle(color: FunkinColors.muted)),
                  )
                : ListView.separated(
                    itemCount: songs.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final song = songs[index];

                      return ListTile(
                        title: Text(song.id),
                        subtitle: Text(
                          [
                            song.variations.join(', '),
                            if (song.audioDirectory == null) 'no audio',
                          ].join(' · '),
                          style: const TextStyle(
                              color: FunkinColors.muted, fontSize: 12),
                        ),
                        trailing: song.isPlayable
                            ? const Icon(Icons.chevron_right)
                            : const Tooltip(
                                message: 'Missing a metadata or chart file',
                                child: Icon(Icons.warning_amber,
                                    color: Colors.orangeAccent),
                              ),
                        onTap: () => _open(song),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(SongRef song) async {
    final variations = song.variations;

    final variation = variations.length == 1
        ? variations.first
        : await showModalBottomSheet<String>(
            context: context,
            backgroundColor: FunkinColors.panel,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Which variation?',
                        style: TextStyle(fontSize: 16)),
                  ),
                  for (final name in variations)
                    ListTile(
                      title: Text(name),
                      onTap: () => Navigator.of(context).pop(name),
                    ),
                ],
              ),
            ),
          );

    if (variation == null || !mounted) return;

    setState(() => _opening = true);

    try {
      final project =
          await widget.workspace.loadSong(song, variation: variation);

      if (!mounted) return;

      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (context) => ChartEditorPage(
          workspace: widget.workspace,
          project: project,
        ),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open ${song.id}: $error')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }
}
