import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../services/database_service.dart';
import '../services/import_export_service.dart';

class ImportExportScreen extends StatefulWidget {
  const ImportExportScreen({super.key});
  @override
  State<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends State<ImportExportScreen> {
  bool _working = false;
  String? _message;
  final _syncPath = TextEditingController();

  Database get _db => context.read<DatabaseService>().db!;
  DatabaseService get _databaseService => context.read<DatabaseService>();

  @override
  void initState() {
    super.initState();
    final home = Platform.environment['HOME'] ?? '.';
    _syncPath.text = p.join(home, 'optimalorganizer-usb');
  }

  @override
  void dispose() {
    _syncPath.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    if (_working) return;
    setState(() {
      _working = true;
      _message = null;
    });
    try {
      final result = await action();
      if (mounted) setState(() => _message = result);
    } catch (e) {
      if (mounted) {
        setState(
            () => _message = e is _Cancelled ? e.message : 'Action failed: $e');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveText(String filename, String text,
      {required String extension, required String title}) async {
    final path = await FilePicker.platform.saveFile(
        dialogTitle: title,
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: [extension]);
    if (path == null) throw const _Cancelled('Export cancelled.');
    await File(path).writeAsString(text, flush: true);
  }

  Future<(String, String)?> _readFile(List<String> extensions) async {
    final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: extensions, withData: true);
    final file = picked?.files.single;
    if (file == null) return null;
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null)
      throw const FormatException('Could not read the selected file.');
    return (file.name, utf8.decode(bytes));
  }

  Future<void> _exportFull({required bool yaml}) => _run(() async {
        final data = await ImportExportService.exportAll(
            _db, _databaseService.dataDirectory!);
        final text = yaml
            ? ImportExportService.encodeYaml(data)
            : const JsonEncoder.withIndent('  ').convert(data);
        await _saveText(
            yaml ? 'optimalorganizer-backup.yaml' : 'optimalorganizer-backup.json', text,
            extension: yaml ? 'yaml' : 'json',
            title:
                yaml ? 'Export full YAML backup' : 'Export full JSON backup');
        return 'Full backup exported.';
      });

  Future<void> _importFull() async {
    final picked = await _readFile(['json', 'yaml', 'yml']);
    if (picked == null) return;
    final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Replace all organizer data?'),
              content: Text(
                  'Restoring ${picked.$1} replaces the current habits, notes, tasks, events, history, and other app data. Included attachments will also be restored.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Replace data')),
              ],
            ));
    if (replace != true) return;
    final isYaml =
        ['.yaml', '.yml'].contains(p.extension(picked.$1).toLowerCase());
    await _run(() async {
      final payload = ImportExportService.decodeBackup(picked.$2, yaml: isYaml);
      final count = await ImportExportService.restoreAll(
          _db, _databaseService.dataDirectory!, payload);
      return 'Restored $count records from ${picked.$1}.';
    });
  }

  Future<void> _exportPartial(String type) => _run(() async {
        switch (type) {
          case 'notes-md':
            await _saveText('optimalorganizer-notes.md',
                await ImportExportService.exportNotesMarkdown(_db),
                extension: 'md', title: 'Export notes as Markdown');
            return 'Notes exported as Markdown.';
          case 'notes-txt':
            await _saveText('optimalorganizer-notes.txt',
                await ImportExportService.exportNotesText(_db),
                extension: 'txt', title: 'Export notes as text');
            return 'Notes exported as text.';
          case 'mindmap-opml':
            await _saveText('optimalorganizer-mindmap.opml',
                await ImportExportService.exportOpml(_db),
                extension: 'opml', title: 'Export mind map as OPML');
            return 'Mind map exported as OPML.';
          default:
            final csv = await ImportExportService.exportCsv(_db, type);
            await _saveText('optimalorganizer-$type.csv', csv,
                extension: 'csv', title: 'Export $type as CSV');
            return '$type exported as CSV.';
        }
      });

  Future<void> _importPartial(String type) async {
    final extension = switch (type) {
      'notes-md' => ['md', 'markdown'],
      'notes-txt' => ['txt'],
      'mindmap-opml' => ['opml', 'xml'],
      'notes-opml' => ['opml', 'xml'],
      _ => ['csv'],
    };
    final picked = await _readFile(extension);
    if (picked == null) return;
    await _run(() async {
      final count = switch (type) {
        'notes-md' => await ImportExportService.importMarkdown(_db, picked.$2),
        'notes-txt' => await _db.insert('notes', {
            'title': p.basenameWithoutExtension(picked.$1),
            'content': picked.$2,
            'tags': '[]',
            'sort_order': (await _db.query('notes')).length,
          }),
        'mindmap-opml' => await ImportExportService.importOpml(_db, picked.$2),
        'notes-opml' =>
          await ImportExportService.importOpmlAsNotes(_db, picked.$2),
        _ => await ImportExportService.importCsv(_db, type, picked.$2),
      };
      await ImportExportService.writeNotesToDisk(
          _db, _databaseService.dataDirectory!);
      return 'Imported $count records from ${picked.$1}.';
    });
  }

  Future<void> _syncExport() => _run(() async {
        final directory = _syncPath.text.trim();
        if (directory.isEmpty)
          throw const FormatException('Choose a folder first.');
        await Directory(directory).create(recursive: true);
        final data = await ImportExportService.exportAll(
            _db, _databaseService.dataDirectory!);
        final file = File(p.join(directory, 'optimalorganizer-sync.json'));
        await file.writeAsString(
            const JsonEncoder.withIndent('  ').convert(data),
            flush: true);
        return 'Full backup synced to ${file.path}.';
      });

  Future<void> _syncImport() async {
    final path = p.join(_syncPath.text.trim(), 'optimalorganizer-sync.json');
    final file = File(path);
    if (!await file.exists()) {
      setState(() => _message = 'No sync backup found at $path');
      return;
    }
    final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Restore from sync folder?'),
              content: const Text(
                  'This replaces all current organizer data with the backup in the selected folder.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Restore')),
              ],
            ));
    if (replace != true) return;
    await _run(() async {
      final payload = ImportExportService.decodeBackup(
          await file.readAsString(),
          yaml: false);
      final count = await ImportExportService.restoreAll(
          _db, _databaseService.dataDirectory!, payload);
      return 'Restored $count records from $path.';
    });
  }

  Future<void> _chooseSyncFolder() async {
    final path = await FilePicker.platform
        .getDirectoryPath(dialogTitle: 'Choose USB or sync folder');
    if (path != null) setState(() => _syncPath.text = path);
  }

  void _detectUsb() {
    final user = Platform.environment['USER'] ?? '';
    final paths = [
      '/media/$user/OPTIMALORGANIZER',
      '/mnt/usb/optimalorganizer',
      '/mnt/optimalorganizer',
      '/run/media/$user/OPTIMALORGANIZER',
    ];
    for (final path in paths) {
      if (Directory(path).existsSync()) {
        setState(() {
          _syncPath.text = path;
          _message = 'Found USB folder: $path';
        });
        return;
      }
    }
    setState(() => _message =
        'No common USB mount found. Choose a folder or enter its path.');
  }

  Future<void> _notesToDisk({required bool import}) => _run(() async {
        final count = import
            ? await ImportExportService.syncNotesFromDisk(
                _db, _databaseService.dataDirectory!)
            : await ImportExportService.writeNotesToDisk(
                _db, _databaseService.dataDirectory!);
        return import
            ? 'Synced $count Markdown notes into the database.'
            : 'Wrote $count notes to ${p.join(_databaseService.dataDirectory!, 'notes')}.';
      });

  Future<void> _selectDataFolder() async {
    final path = await FilePicker.platform
        .getDirectoryPath(dialogTitle: 'Choose existing OptimalOrganizer data folder');
    if (path == null) return;
    final use = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Switch data folder?'),
              content: Text(
                  'Use $path if it contains optimalorganizer.db. Your current data folder will remain unchanged.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Switch folder')),
              ],
            ));
    if (use != true) return;
    await _run(() async {
      await _databaseService.useDataDirectory(path);
      return 'Now using data folder $path.';
    });
  }

  Future<void> _deleteData() async {
    final first = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Delete all OptimalOrganizer data?'),
              content: Text(
                  'This permanently removes the database, notes, and attachments from ${_databaseService.dataDirectory}.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Continue')),
              ],
            ));
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('This cannot be undone'),
              content: const Text('Delete the organizer data now?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete everything')),
              ],
            ));
    if (second != true || !mounted) return;
    await _run(() async {
      await _databaseService.deleteAllOrganizerData();
      return 'Deleted all data from this folder.';
    });
  }

  Future<void> _disconnectDatabase() async {
    final first = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Disconnect / switch database?'),
              content: Text(
                  'This will let you choose a different data folder and restart the database connection. The current folder at ${_databaseService.dataDirectory} will remain on disk unless you explicitly delete it.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Continue')),
              ],
            ));
    if (first != true || !mounted) return;
    final path = await FilePicker.platform
        .getDirectoryPath(dialogTitle: 'Choose a different OptimalOrganizer data folder (or create one)');
    if (path == null || !mounted) return;
    await _run(() async {
      await _databaseService.useDataDirectory(path);
      return 'Disconnected and switched to $path.';
    });
  }

  Widget _action(String title, IconData icon, VoidCallback onPressed,
      {bool prominent = false, bool danger = false}) {
    return SizedBox(
      width: double.infinity,
      child: prominent
          ? FilledButton.icon(
              onPressed: _working ? null : onPressed,
              icon: Icon(icon),
              label: Text(title))
          : OutlinedButton.icon(
              onPressed: _working ? null : onPressed,
              icon: Icon(icon,
                  color: danger ? Theme.of(context).colorScheme.error : null),
              label: Text(title)),
    );
  }

  Widget _panel(String title, String description, List<Widget> actions) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            for (var i = 0; i < actions.length; i++) ...[
              actions[i],
              if (i < actions.length - 1) const SizedBox(height: 8),
            ],
          ]),
        ),
      );

  List<Widget> _partialExportActions() => [
        _action('Notes as Markdown (.md)', Icons.article_outlined,
            () => _exportPartial('notes-md')),
        _action('Notes as text (.txt)', Icons.subject,
            () => _exportPartial('notes-txt')),
        _action('Mind map as OPML (.opml)', Icons.account_tree_outlined,
            () => _exportPartial('mindmap-opml')),
        for (final table in ['habits', 'events', 'captures', 'tasks'])
          _action('$table as CSV (.csv)', Icons.table_view,
              () => _exportPartial(table)),
      ];

  List<Widget> _partialImportActions() => [
        _action('Notes from Markdown (.md)', Icons.article_outlined,
            () => _importPartial('notes-md')),
        _action('Single note from text (.txt)', Icons.subject,
            () => _importPartial('notes-txt')),
        _action('Mind map from OPML (.opml)', Icons.account_tree_outlined,
            () => _importPartial('mindmap-opml')),
        _action('Nested notes from OPML (.opml)', Icons.account_tree,
            () => _importPartial('notes-opml')),
        for (final table in ['habits', 'events', 'captures', 'tasks'])
          _action('$table from CSV (.csv)', Icons.table_view,
              () => _importPartial(table)),
      ];

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Import & Export'),
            bottom: const TabBar(tabs: [
              Tab(text: 'Export', icon: Icon(Icons.file_download_outlined)),
              Tab(text: 'Import', icon: Icon(Icons.file_upload_outlined)),
              Tab(text: 'Sync & Storage', icon: Icon(Icons.sync)),
            ]),
          ),
          body: Column(children: [
            if (_working) const LinearProgressIndicator(),
            if (_message != null)
              MaterialBanner(
                content: Text(_message!),
                actions: [
                  TextButton(
                      onPressed: () => setState(() => _message = null),
                      child: const Text('Dismiss'))
                ],
              ),
            Expanded(
              child: TabBarView(children: [
                ListView(padding: const EdgeInsets.all(16), children: [
                  _panel(
                      'Complete backup',
                      'Export every organizer table and its attachment files. JSON and YAML backups can be restored by the Python and Go versions too.',
                      [
                        _action(
                            'Export full JSON backup',
                            Icons.archive_outlined,
                            () => _exportFull(yaml: false),
                            prominent: true),
                        _action(
                            'Export full YAML backup',
                            Icons.description_outlined,
                            () => _exportFull(yaml: true)),
                      ]),
                  _panel(
                      'Selected data',
                      'These files export only the selected content and do not contain a full backup.',
                      _partialExportActions()),
                ]),
                ListView(padding: const EdgeInsets.all(16), children: [
                  _panel(
                      'Complete restore',
                      'A full backup replaces all current organizer data. You will be asked to confirm before anything is replaced.',
                      [
                        _action('Restore JSON or YAML backup', Icons.restore,
                            _importFull,
                            prominent: true),
                      ]),
                  _panel(
                      'Add selected data',
                      'Partial imports add content to the current organizer and leave other records in place.',
                      _partialImportActions()),
                ]),
                ListView(padding: const EdgeInsets.all(16), children: [
                  _panel(
                      'USB or folder sync',
                      'A sync folder holds a complete portable backup named optimalorganizer-sync.json.',
                      [
                        TextField(
                            controller: _syncPath,
                            decoration: const InputDecoration(
                                labelText: 'Folder path',
                                hintText: '/media/you/USB/OptimalOrganizer')),
                        _action('Choose folder…', Icons.folder_open,
                            _chooseSyncFolder),
                        _action(
                            'Detect common USB mount', Icons.usb, _detectUsb),
                        _action('Export full backup to folder', Icons.upload,
                            _syncExport,
                            prominent: true),
                        _action('Restore full backup from folder',
                            Icons.download, _syncImport),
                      ]),
                  _panel(
                      'Notes on disk',
                      'Mirror notes into Markdown files in the active data folder, or rebuild notes from those files.',
                      [
                        _action(
                            'Write notes to Markdown files',
                            Icons.file_present,
                            () => _notesToDisk(import: false)),
                        _action('Sync Markdown files into notes', Icons.sync,
                            () => _notesToDisk(import: true)),
                      ]),
                  _panel(
                      'Data folder',
                      'Current folder: ${_databaseService.dataDirectory ?? 'Loading…'}',
                      [
                        _action('Choose existing data folder…',
                            Icons.folder_special, _selectDataFolder),
                        _action('Delete all data in this folder…',
                            Icons.delete_forever, _deleteData,
                            danger: true),
                        _action('Disconnect / Switch database location…',
                            Icons.link_off, _disconnectDatabase,
                            danger: true),
                      ]),
                ]),
              ]),
            ),
          ]),
        ),
      );
}

class _Cancelled implements Exception {
  final String message;
  const _Cancelled(this.message);
  @override
  String toString() => message;
}
