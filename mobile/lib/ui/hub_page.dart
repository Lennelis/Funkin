import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/funkin_theme.dart';
import 'character_list_page.dart';
import 'song_list_page.dart';

/// The way in.
///
/// Nothing else in the app works until a folder is chosen, so the first screen
/// is about that and says plainly what it is looking for. Once one is open it
/// becomes the list of what is in it.
class HubPage extends StatelessWidget {
  const HubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Funkin Editors'),
        actions: [
          if (state.hasWorkspace)
            IconButton(
              onPressed: state.rescan,
              icon: const Icon(Icons.refresh),
              tooltip: 'Rescan folder',
            ),
          if (state.workspace != null)
            IconButton(
              onPressed: state.close,
              icon: const Icon(Icons.folder_off_outlined),
              tooltip: 'Close folder',
            ),
        ],
      ),
      body: state.isScanning
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context, state),
    );
  }

  Widget _buildBody(BuildContext context, AppState state) {
    final workspace = state.workspace;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (workspace == null || !state.hasWorkspace) _Welcome(state: state),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: FunkinColors.raised,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
              ),
              child: Text(state.error!),
            ),
          ),
        if (workspace != null && state.hasWorkspace) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              workspace.displayName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Text(
              state.storage.displayPath(workspace.root.id),
              style: const TextStyle(color: FunkinColors.muted, fontSize: 12),
            ),
          ),
          _ToolCard(
            title: 'Chart Editor',
            subtitle: '${workspace.songs.length} '
                '${workspace.songs.length == 1 ? 'song' : 'songs'}',
            icon: Icons.grid_on,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (context) => SongListPage(workspace: workspace),
            )),
          ),
          _ToolCard(
            title: 'Character Editor',
            subtitle: workspace.charactersData == null
                ? 'No data/characters folder'
                : 'Animations and offsets',
            icon: Icons.person_outline,
            enabled: workspace.charactersData != null,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (context) => CharacterListPage(workspace: workspace),
            )),
          ),
        ],
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        const Text(
          'Open a mod folder',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        const Text(
          'Pick the folder with data/songs in it — a mod, or the game’s own '
          'assets. Everything is edited in place, so what you save is the file '
          'the game loads.',
          style: TextStyle(color: FunkinColors.muted, height: 1.4),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: state.pickFolder,
          icon: const Icon(Icons.folder_open),
          label: const Text('Choose folder'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: FunkinColors.panel,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(16),
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: FunkinColors.pink.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: FunkinColors.pink),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: const TextStyle(
                                color: FunkinColors.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: FunkinColors.muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
