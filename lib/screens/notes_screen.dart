import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/database_service.dart';
import '../widgets/database_unavailable.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});
  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  List<Map<String, Object?>> _notes = [];
  String _query = '';
  bool _loading = true;
  final Map<int, String> _dropZones = {};

  String _classifyDropZone(RenderBox? box, Offset offset) {
    if (box == null || box.size.width == 0) return 'reorder';
    final x = box.globalToLocal(offset).dx / box.size.width;
    if (x < 0.32) return 'out';
    if (x > 0.68) return 'child';
    return 'reorder';
  }

  Widget _dropZoneGuide(String? active) {
    final colors = Theme.of(context).colorScheme;
    final zones = [
      ('out', '← OUT', colors.secondaryContainer),
      ('reorder', '↕ ORDER', colors.primaryContainer),
      ('child', 'CHILD →', colors.tertiaryContainer),
    ];
    return Row(
      children: [
        for (final zone in zones)
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 3),
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: zone.$3,
                borderRadius: BorderRadius.circular(4),
                border: active == zone.$1
                    ? Border.all(color: colors.onSurface, width: 1.5)
                    : null,
              ),
              alignment: Alignment.center,
              child:
                  Text(zone.$2, style: Theme.of(context).textTheme.labelSmall),
            ),
          ),
      ],
    );
  }

  Future<void> _load() async {
    final db = context.read<DatabaseService>().db;
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final notes = await db.query('notes', orderBy: 'sort_order, id');
    if (mounted)
      setState(() {
        _notes = notes;
        _loading = false;
      });
  }

  List<Map<String, Object?>> _children(Object? parent) =>
      _notes.where((n) => n['parent_id'] == parent).toList();

  Future<void> _moveNote(int id, Object? parentId, int position) async {
    final descendants = <int>{};
    void collect(int current) {
      for (final child in _children(current)) {
        final childId = child['id'] as int;
        descendants.add(childId);
        collect(childId);
      }
    }

    collect(id);
    if (parentId == id || (parentId is int && descendants.contains(parentId))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('A note cannot be moved inside itself.')));
      return;
    }
    final note = _notes.firstWhere((n) => n['id'] == id);
    final oldParent = note['parent_id'];
    final oldSiblings =
        _children(oldParent).where((n) => n['id'] != id).toList();
    if (oldParent == parentId &&
        _children(oldParent).indexWhere((n) => n['id'] == id) < position) {
      position--;
    }
    final newSiblings = (oldParent == parentId
        ? oldSiblings
        : _children(parentId).where((n) => n['id'] != id).toList());
    final safePosition = position.clamp(0, newSiblings.length).toInt();
    newSiblings.insert(safePosition, note);
    final db = context.read<DatabaseService>().db!;
    await db.transaction((txn) async {
      await txn.update('notes', {'parent_id': parentId},
          where: 'id = ?', whereArgs: [id]);
      for (var i = 0; i < oldSiblings.length; i++) {
        await txn.update('notes', {'sort_order': i},
            where: 'id = ?', whereArgs: [oldSiblings[i]['id']]);
      }
      for (var i = 0; i < newSiblings.length; i++) {
        await txn.update('notes', {'sort_order': i},
            where: 'id = ?', whereArgs: [newSiblings[i]['id']]);
      }
    });
    await _load();
  }

  Future<void> _moveRelative(Map<String, Object?> note,
      {required bool indent}) async {
    final id = note['id'] as int;
    final parent = note['parent_id'];
    final siblings = _children(parent);
    final index = siblings.indexWhere((n) => n['id'] == id);
    if (indent) {
      if (index <= 0) return;
      final newParent = siblings[index - 1];
      await _moveNote(id, newParent['id'], _children(newParent['id']).length);
    } else {
      if (parent is! int) return;
      final parentNote = _notes.firstWhere((n) => n['id'] == parent);
      final grandparent = parentNote['parent_id'];
      final parentSiblings = _children(grandparent);
      final parentIndex = parentSiblings.indexWhere((n) => n['id'] == parent);
      await _moveNote(id, grandparent, parentIndex + 1);
    }
  }

  bool _matches(Map<String, Object?> note) =>
      _query.isEmpty ||
      '${note['title']} ${note['content']} ${note['tags']}'
          .toLowerCase()
          .contains(_query.toLowerCase());

  Future<void> _edit({Map<String, Object?>? note, Object? parentId}) async {
    final title = TextEditingController(text: '${note?['title'] ?? ''}');
    final content = TextEditingController(text: '${note?['content'] ?? ''}');
    final tagsValue = TextEditingController(text: _tagString(note?['tags']));
    final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(note == null
                  ? (parentId == null ? 'New note' : 'New subnote')
                  : 'Edit note'),
              content: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: title,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Title')),
                    TextField(
                        controller: content,
                        minLines: 8,
                        maxLines: 16,
                        decoration: const InputDecoration(
                            labelText: 'Write your note')),
                    TextField(
                        controller: tagsValue,
                        decoration: const InputDecoration(
                            labelText: 'Tags (comma separated)')),
                  ]))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save'))
              ],
            ));
    final t = title.text.trim();
    final body = content.text;
    final tags = tagsValue.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    title.dispose();
    content.dispose();
    tagsValue.dispose();
    if (saved != true || t.isEmpty) return;
    final db = context.read<DatabaseService>().db!;
    if (note == null) {
      final siblings = _children(parentId);
      await db.insert('notes', {
        'title': t,
        'content': body,
        'tags': jsonEncode(tags),
        'parent_id': parentId,
        'sort_order': siblings.length
      });
    } else {
      await db.update(
          'notes',
          {
            'title': t,
            'content': body,
            'tags': jsonEncode(tags),
            'updated_at': DateTime.now().toIso8601String()
          },
          where: 'id = ?',
          whereArgs: [note['id']]);
    }
    await _load();
  }

  String _tagString(Object? value) {
    if (value == null) return '';
    try {
      final parsed = jsonDecode('$value');
      if (parsed is List) return parsed.join(', ');
    } catch (_) {}
    return '$value';
  }

  Future<void> _delete(Map<String, Object?> note) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Delete note?'),
                content: Text(
                    '“${note['title']}” and its subnotes will be removed.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'))
                ]));
    if (yes != true) return;
    final db = context.read<DatabaseService>().db!;
    final descendants = <int>[];
    void collect(int id) {
      for (final child in _children(id)) {
        collect(child['id'] as int);
        descendants.add(child['id'] as int);
      }
    }

    collect(note['id'] as int);
    await db.transaction((txn) async {
      for (final id in descendants.reversed) {
        await txn.delete('notes', where: 'id = ?', whereArgs: [id]);
      }
      await txn.delete('notes', where: 'id = ?', whereArgs: [note['id']]);
    });
    await _load();
  }

  void _open(Map<String, Object?> note) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NoteDetailScreen(
            note: note,
            allNotes: _notes,
            onEdit: () async {
              Navigator.of(context).pop();
              await _edit(note: note);
              if (mounted) await _load();
            },
            onDelete: () async {
              Navigator.of(context).pop();
              await _delete(note);
            })));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final roots = _children(null);
    return Scaffold(
      appBar: AppBar(title: const Text('Notes'), actions: [
        IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh))
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(),
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('New note')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : context.read<DatabaseService>().db == null
              ? DatabaseUnavailable(
                  message: context.read<DatabaseService>().initializationError,
                  onRetry: () async {
                    await context.read<DatabaseService>().init();
                    await _load();
                  })
              : Column(children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: TextField(
                          decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search notes and tags',
                              border: OutlineInputBorder()),
                          onChanged: (v) => setState(() => _query = v.trim()))),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                              'Drop left to move out one level, middle to reorder, or right to make a child.',
                              style: Theme.of(context).textTheme.bodySmall))),
                  Expanded(
                      child: _notes.isEmpty
                          ? const Center(
                              child:
                                  Text('Capture an idea before it slips away.'))
                          : !_notes.any(_matches)
                              ? const Center(
                                  child: Text('No notes match your search.'))
                              : ListView(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 8, 12, 92),
                                  children: [
                                      for (final note in roots)
                                        _noteTile(note, 0)
                                    ])),
                ]),
    );
  }

  Widget _noteTile(Map<String, Object?> note, int depth) {
    final children = _children(note['id']);
    final show = _matches(note) || children.any(_hasMatchingDescendant);
    if (!show) return const SizedBox.shrink();
    final tags = _tagString(note['tags'])
        .split(',')
        .where((t) => t.trim().isNotEmpty)
        .toList();
    RenderBox? targetBox;
    return Padding(
        padding: EdgeInsets.only(left: depth * 18.0),
        child: Card(
            child: Column(children: [
          DragTarget<int>(
            onWillAcceptWithDetails: (details) => details.data != note['id'],
            onMove: (details) {
              final id = note['id'] as int;
              final zone = _classifyDropZone(targetBox, details.offset);
              if (_dropZones[id] != zone && mounted) {
                setState(() => _dropZones[id] = zone);
              }
            },
            onLeave: (_) {
              final id = note['id'] as int;
              if (_dropZones.remove(id) != null && mounted) setState(() {});
            },
            onAcceptWithDetails: (details) {
              final id = details.data;
              final box = targetBox;
              final local = box?.globalToLocal(details.offset);
              final siblings = _children(note['parent_id']);
              final index = siblings.indexWhere((n) => n['id'] == note['id']);
              final zone = _classifyDropZone(box, details.offset);
              if (zone == 'child') {
                _moveNote(id, note['id'], _children(note['id']).length);
              } else if (zone == 'out') {
                _moveNote(id, note['parent_id'], index);
              } else {
                final after =
                    local != null && local.dy > (box!.size.height / 2);
                _moveNote(id, note['parent_id'], index + (after ? 1 : 0));
              }
              _dropZones.remove(note['id']);
              if (mounted) setState(() {});
            },
            builder: (ctx, candidates, rejected) {
              targetBox = ctx.findRenderObject() as RenderBox?;
              return ListTile(
                leading: Row(mainAxisSize: MainAxisSize.min, children: [
                  Draggable<int>(
                    data: note['id'] as int,
                    feedback: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('${note['title']}'),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.drag_indicator),
                    ),
                  ),
                  const Icon(Icons.description_outlined),
                ]),
                title: Text('${note['title']}'),
                subtitle: candidates.isEmpty
                    ? Text('${note['content'] ?? ''}',
                        maxLines: 2, overflow: TextOverflow.ellipsis)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${note['content'] ?? ''}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          _dropZoneGuide(_dropZones[note['id']]),
                        ],
                      ),
                onTap: () => _open(note),
                trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'subnote')
                        _edit(parentId: note['id']);
                      else if (v == 'edit')
                        _edit(note: note);
                      else if (v == 'indent')
                        _moveRelative(note, indent: true);
                      else if (v == 'outdent')
                        _moveRelative(note, indent: false);
                      else
                        _delete(note);
                    },
                    itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'subnote', child: Text('Add subnote')),
                          const PopupMenuItem(
                              value: 'indent',
                              child: Text('Nest under previous note')),
                          if (note['parent_id'] != null)
                            const PopupMenuItem(
                                value: 'outdent',
                                child: Text('Move up one level')),
                          const PopupMenuItem(
                              value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Delete'))
                        ]),
                tileColor: candidates.isEmpty
                    ? null
                    : switch (_dropZones[note['id']]) {
                        'out' =>
                          Theme.of(context).colorScheme.secondaryContainer,
                        'child' =>
                          Theme.of(context).colorScheme.tertiaryContainer,
                        _ => Theme.of(context).colorScheme.primaryContainer,
                      },
              );
            },
          ),
          if (tags.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 4, children: [
                      for (final tag in tags)
                        Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(tag))
                    ]))),
          for (final child in children) _noteTile(child, depth + 1),
        ])));
  }

  bool _hasMatchingDescendant(Map<String, Object?> note) =>
      _matches(note) || _children(note['id']).any(_hasMatchingDescendant);
}

class NoteDetailScreen extends StatelessWidget {
  final Map<String, Object?> note;
  final List<Map<String, Object?>> allNotes;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;
  const NoteDetailScreen(
      {super.key,
      required this.note,
      required this.allNotes,
      required this.onEdit,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final links = RegExp(r'\[\[([^\]]+)\]\]')
        .allMatches('${note['content'] ?? ''}')
        .map((m) => m.group(1)!)
        .toList();
    final tags = '${note['tags'] ?? '[]'}';
    List<dynamic> parsedTags = [];
    try {
      parsedTags = jsonDecode(tags) as List<dynamic>;
    } catch (_) {}
    return Scaffold(
        appBar: AppBar(title: Text('${note['title']}'), actions: [
          IconButton(
              onPressed: onEdit,
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined)),
          IconButton(
              onPressed: onDelete,
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline))
        ]),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text('${note['title']}',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('Updated ${note['updated_at'] ?? ''}',
              style: Theme.of(context).textTheme.bodySmall),
          if (parsedTags.isNotEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Wrap(spacing: 6, children: [
                  for (final tag in parsedTags) Chip(label: Text('$tag'))
                ])),
          const Divider(height: 32),
          SelectableText('${note['content'] ?? ''}',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(height: 1.55)),
          if (links.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Linked note titles',
                style: Theme.of(context).textTheme.titleSmall),
            Wrap(children: [
              for (final link in links)
                ActionChip(
                    label: Text(link),
                    onPressed: () {
                      final target =
                          allNotes.where((n) => n['title'] == link).firstOrNull;
                      if (target != null)
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => NoteDetailScreen(
                                note: target,
                                allNotes: allNotes,
                                onEdit: () async {},
                                onDelete: () async {})));
                    })
            ])
          ],
        ]));
  }
}
