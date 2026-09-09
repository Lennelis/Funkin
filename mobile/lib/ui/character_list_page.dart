import 'package:flutter/material.dart';

import '../editors/character/character_editor_page.dart';
import '../services/storage/storage_backend.dart';
import '../services/workspace.dart';
import '../theme/funkin_theme.dart';

/// Every character file in the folder.
class CharacterListPage extends StatefulWidget {
  const CharacterListPage({super.key, required this.workspace});

  final Workspace workspace;

  @override
  State<CharacterListPage> createState() => _CharacterListPageState();
}

class _CharacterListPageState extends State<CharacterListPage> {
  late Future<List<StorageEntry>> _files = widget.workspace.characterFiles();
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Characters')),
      body: FutureBuilder<List<StorageEntry>>(
        future: _files,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Could not read that folder:\n${snapshot.error}'));
          }

          final files = (snapshot.data ?? const <StorageEntry>[])
              .where((file) =>
                  file.stem.toLowerCase().contains(_filter.toLowerCase()))
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Find a character',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _filter = value),
                ),
              ),
              Expanded(
                child: files.isEmpty
                    ? const Center(
                        child: Text('Nothing here.',
                            style: TextStyle(color: FunkinColors.muted)),
                      )
                    : ListView.separated(
                        itemCount: files.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final file = files[index];

                          return ListTile(
                            title: Text(file.stem),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) => CharacterEditorPage(
                                    workspace: widget.workspace,
                                    file: file,
                                  ),
                                ),
                              );

                              // The editor may have written a new name into
                              // the file that the list is showing.
                              if (mounted) {
                                setState(() =>
                                    _files = widget.workspace.characterFiles());
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
