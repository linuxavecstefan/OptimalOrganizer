import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/database_service.dart';
import '../widgets/database_unavailable.dart';

class TodosScreen extends StatefulWidget {
  const TodosScreen({super.key});

  @override
  State<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends State<TodosScreen> {
  List<Map<String, Object?>> _todos = [];
  List<Map<String, Object?>> _history = [];
  bool _showHistory = false;
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
    final today = _date(DateTime.now());
    await db.transaction((txn) async {
      // Keep completion records for progress history while removing them from
      // the active tree after midnight. Active children are lifted out first.
      while (true) {
        final count = (await txn.rawQuery('''
          SELECT COUNT(*) AS count FROM todos child JOIN todos parent ON child.parent_id = parent.id
          WHERE child.archived = 0 AND parent.archived = 1
        ''')).first['count'] as int;
        if (count == 0) break;
        await txn.rawUpdate('''
          UPDATE todos SET parent_id = (SELECT parent_id FROM todos parent WHERE parent.id = todos.parent_id)
          WHERE id IN (SELECT child.id FROM todos child JOIN todos parent ON child.parent_id = parent.id
            WHERE child.archived = 0 AND parent.archived = 1)
        ''');
      }
      await txn.update('todos', {'archived': 1},
          where: 'completed = 1 AND completed_at IS NOT NULL AND substr(completed_at, 1, 10) < ? AND archived = 0',
          whereArgs: [today]);
    });
    final rows = await db.query('todos', where: 'archived = 0', orderBy: 'sort_order, id');
    final history = await db.query('todos', where: 'archived = 1', orderBy: 'completed_at DESC, id DESC');
    if (mounted)
      setState(() {
        _todos = rows;
        _history = history;
        _loading = false;
      });
  }

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  List<Map<String, Object?>> _children(Object? parentId) =>
      _todos.where((row) => row['parent_id'] == parentId).toList();

  Future<void> _moveTodo(int id, Object? parentId, int position) async {
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
          content: Text('A to-do cannot be moved inside itself.')));
      return;
    }
    final todo = _todos.firstWhere((t) => t['id'] == id);
    final oldParent = todo['parent_id'];
    final oldSiblings =
        _children(oldParent).where((t) => t['id'] != id).toList();
    if (oldParent == parentId &&
        _children(oldParent).indexWhere((t) => t['id'] == id) < position) {
      position--;
    }
    final newSiblings = oldParent == parentId
        ? oldSiblings
        : _children(parentId).where((t) => t['id'] != id).toList();
    newSiblings.insert(position.clamp(0, newSiblings.length).toInt(), todo);
    final db = context.read<DatabaseService>().db!;
    await db.transaction((txn) async {
      await txn.update('todos', {'parent_id': parentId},
          where: 'id = ?', whereArgs: [id]);
      for (var i = 0; i < oldSiblings.length; i++) {
        await txn.update('todos', {'sort_order': i},
            where: 'id = ?', whereArgs: [oldSiblings[i]['id']]);
      }
      for (var i = 0; i < newSiblings.length; i++) {
        await txn.update('todos', {'sort_order': i},
            where: 'id = ?', whereArgs: [newSiblings[i]['id']]);
      }
    });
    await _load();
  }

  Future<void> _moveRelative(Map<String, Object?> todo,
      {required bool indent}) async {
    final id = todo['id'] as int;
    final parent = todo['parent_id'];
    final siblings = _children(parent);
    final index = siblings.indexWhere((t) => t['id'] == id);
    if (indent) {
      if (index <= 0) return;
      final newParent = siblings[index - 1];
      await _moveTodo(id, newParent['id'], _children(newParent['id']).length);
    } else {
      if (parent is! int) return;
      final parentTodo = _todos.firstWhere((t) => t['id'] == parent);
      final grandparent = parentTodo['parent_id'];
      final parentSiblings = _children(grandparent);
      final parentIndex = parentSiblings.indexWhere((t) => t['id'] == parent);
      await _moveTodo(id, grandparent, parentIndex + 1);
    }
  }

  Future<void> _edit({Map<String, Object?>? todo, Object? parentId}) async {
    final title = TextEditingController(text: '${todo?['title'] ?? ''}');
    DateTime? due = DateTime.tryParse('${todo?['due_date'] ?? ''}');
    final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: Text(todo == null
                      ? (parentId == null ? 'Add to-do' : 'Add subtask')
                      : 'Edit to-do'),
                  content: SizedBox(
                      width: 420,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                            controller: title,
                            autofocus: true,
                            decoration:
                                const InputDecoration(labelText: 'Task')),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: Text(due == null
                                  ? 'No due date'
                                  : 'Due ${_date(due!)}')),
                          TextButton(
                              onPressed: () async {
                                final selected = await showDatePicker(
                                    context: ctx,
                                    initialDate: due ?? DateTime.now(),
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100));
                                if (selected != null)
                                  update(() => due = selected);
                              },
                              child: const Text('Choose')),
                          if (due != null)
                            IconButton(
                                tooltip: 'Clear due date',
                                onPressed: () => update(() => due = null),
                                icon: const Icon(Icons.clear)),
                        ]),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Save')),
                  ],
                )));
    final text = title.text.trim();
    title.dispose();
    if (saved != true || text.isEmpty) return;
    final db = context.read<DatabaseService>().db!;
    if (todo == null) {
      final siblings = _children(parentId);
      await db.insert('todos', {
        'title': text,
        'due_date': due == null ? null : _date(due!),
        'parent_id': parentId,
        'sort_order': siblings.length
      });
    } else {
      await db.update('todos',
          {'title': text, 'due_date': due == null ? null : _date(due!)},
          where: 'id = ?', whereArgs: [todo['id']]);
    }
    await _load();
  }

  Future<void> _toggle(Map<String, Object?> todo) async {
    final complete = (todo['completed'] as int? ?? 0) == 1;
    await context.read<DatabaseService>().db!.update(
        'todos',
        {
          'completed': complete ? 0 : 1,
          'completed_at': complete ? null : DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [todo['id']]);
    await _load();
  }

  Future<void> _delete(Map<String, Object?> todo) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Delete to-do?'),
              content:
                  Text('“${todo['title']}” and its subtasks will be removed.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete'))
              ],
            ));
    if (yes != true) return;
    final db = context.read<DatabaseService>().db!;
    final descendants = <int>[];
    void collect(int id) {
      for (final child in _children(id)) {
        collect(child['id'] as int);
        descendants.add(child['id'] as int);
      }
    }

    collect(todo['id'] as int);
    await db.transaction((txn) async {
      for (final id in descendants.reversed) {
        await txn.delete('todos', where: 'id = ?', whereArgs: [id]);
      }
      await txn.delete('todos', where: 'id = ?', whereArgs: [todo['id']]);
    });
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final roots = _children(null);
    final complete = _todos.where((t) => t['completed'] == 1).length;
    return Scaffold(
      appBar: AppBar(title: Text(_showHistory ? 'Completed history' : 'To-dos'), actions: [
        IconButton(tooltip: _showHistory ? 'Show active to-dos' : 'Completed history', onPressed: () => setState(() => _showHistory = !_showHistory), icon: Icon(_showHistory ? Icons.task_alt : Icons.history)),
        IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh))
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(),
          icon: const Icon(Icons.add),
          label: const Text('Add to-do')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _showHistory
              ? _historyView()
              : context.read<DatabaseService>().db == null
              ? DatabaseUnavailable(
                  message: context.read<DatabaseService>().initializationError,
                  onRetry: () async {
                    await context.read<DatabaseService>().init();
                    await _load();
                  })
              : Column(children: [
                  if (_todos.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                        child: Row(children: [
                          Expanded(
                              child: LinearProgressIndicator(
                                  value: _todos.isEmpty
                                      ? 0
                                      : complete / _todos.length)),
                          const SizedBox(width: 12),
                          Text('$complete/${_todos.length} done')
                        ])),
                  if (_todos.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                                'Drop left to move out one level, middle to reorder, or right to make a child.',
                                style: Theme.of(context).textTheme.bodySmall))),
                  Expanded(
                      child: roots.isEmpty
                          ? Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                  const Icon(Icons.task_alt, size: 52),
                                  const SizedBox(height: 12),
                                  Text('Clear your mind',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                  const Text(
                                      'Add a to-do or break it into smaller steps.')
                                ]))
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 92),
                              children: [
                                  for (final todo in roots) _todoTile(todo, 0)
                                ])),
                ]),
    );
  }

  Widget _historyView() => _history.isEmpty
      ? const Center(child: Text('Completed to-dos will appear here after the day ends.'))
      : ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: _history.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final todo = _history[i];
            return Card(child: ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text('${todo['title']}', style: const TextStyle(decoration: TextDecoration.lineThrough)),
              subtitle: Text('Completed ${todo['completed_at'] ?? 'previously'}'),
              trailing: TextButton.icon(icon: const Icon(Icons.undo), label: const Text('Restore'), onPressed: () async {
                await context.read<DatabaseService>().db!.update('todos', {'completed': 0, 'completed_at': null, 'archived': 0}, where: 'id = ?', whereArgs: [todo['id']]);
                await _load();
              }),
            ));
          },
        );

  Widget _todoTile(Map<String, Object?> todo, int depth) {
    final done = (todo['completed'] as int? ?? 0) == 1;
    final due = '${todo['due_date'] ?? ''}';
    final overdue =
        due.isNotEmpty && due.compareTo(_date(DateTime.now())) < 0 && !done;
    final children = _children(todo['id']);
    RenderBox? targetBox;
    return Padding(
        padding: EdgeInsets.only(left: depth * 20.0),
        child: Card(
            child: Column(children: [
          DragTarget<int>(
            onWillAcceptWithDetails: (details) => details.data != todo['id'],
            onMove: (details) {
              final id = todo['id'] as int;
              final zone = _classifyDropZone(targetBox, details.offset);
              if (_dropZones[id] != zone && mounted) {
                setState(() => _dropZones[id] = zone);
              }
            },
            onLeave: (_) {
              final id = todo['id'] as int;
              if (_dropZones.remove(id) != null && mounted) setState(() {});
            },
            onAcceptWithDetails: (details) {
              final id = details.data;
              final box = targetBox;
              final local = box?.globalToLocal(details.offset);
              final siblings = _children(todo['parent_id']);
              final index = siblings.indexWhere((t) => t['id'] == todo['id']);
              final zone = _classifyDropZone(box, details.offset);
              if (zone == 'child') {
                _moveTodo(id, todo['id'], _children(todo['id']).length);
              } else if (zone == 'out') {
                _moveTodo(id, todo['parent_id'], index);
              } else {
                final after = box != null &&
                    local != null &&
                    local.dy > box.size.height / 2;
                _moveTodo(id, todo['parent_id'], index + (after ? 1 : 0));
              }
              _dropZones.remove(todo['id']);
              if (mounted) setState(() {});
            },
            builder: (ctx, candidates, rejected) {
              targetBox = ctx.findRenderObject() as RenderBox?;
              return ListTile(
                leading: Row(mainAxisSize: MainAxisSize.min, children: [
                  Draggable<int>(
                    data: todo['id'] as int,
                    feedback: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text('${todo['title']}'),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.drag_indicator),
                    ),
                  ),
                  Checkbox(value: done, onChanged: (_) => _toggle(todo)),
                ]),
                title: Text('${todo['title']}',
                    style: TextStyle(
                        decoration: done ? TextDecoration.lineThrough : null)),
                subtitle: candidates.isEmpty
                    ? (due.isEmpty
                        ? null
                        : Text('Due $due',
                            style: TextStyle(
                                color: overdue
                                    ? Theme.of(context).colorScheme.error
                                    : null)))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (due.isNotEmpty)
                            Text('Due $due',
                                style: TextStyle(
                                    color: overdue
                                        ? Theme.of(context).colorScheme.error
                                        : null)),
                          _dropZoneGuide(_dropZones[todo['id']]),
                        ],
                      ),
                onTap: () => _edit(todo: todo),
                trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'subtask')
                        _edit(parentId: todo['id']);
                      else if (v == 'edit')
                        _edit(todo: todo);
                      else if (v == 'indent')
                        _moveRelative(todo, indent: true);
                      else if (v == 'outdent')
                        _moveRelative(todo, indent: false);
                      else
                        _delete(todo);
                    },
                    itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'subtask',
                              child: ListTile(
                                  leading: Icon(Icons.subdirectory_arrow_right),
                                  title: Text('Add subtask'))),
                          const PopupMenuItem(
                              value: 'indent',
                              child: ListTile(
                                  leading: Icon(Icons.format_indent_increase),
                                  title: Text('Nest under previous to-do'))),
                          if (todo['parent_id'] != null)
                            const PopupMenuItem(
                                value: 'outdent',
                                child: ListTile(
                                    leading: Icon(Icons.format_indent_decrease),
                                    title: Text('Move up one level'))),
                          const PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                  leading: Icon(Icons.edit_outlined),
                                  title: Text('Edit'))),
                          const PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                  leading: Icon(Icons.delete_outline),
                                  title: Text('Delete'))),
                        ]),
                tileColor: candidates.isEmpty
                    ? null
                    : switch (_dropZones[todo['id']]) {
                        'out' =>
                          Theme.of(context).colorScheme.secondaryContainer,
                        'child' =>
                          Theme.of(context).colorScheme.tertiaryContainer,
                        _ => Theme.of(context).colorScheme.primaryContainer,
                      },
              );
            },
          ),
          if (children.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                child: Row(children: [
                  Expanded(
                      child: LinearProgressIndicator(
                          value: children
                                  .where((c) => c['completed'] == 1)
                                  .length /
                              children.length)),
                  const SizedBox(width: 8),
                  Text(
                      '${children.where((c) => c['completed'] == 1).length}/${children.length} subtasks',
                      style: Theme.of(context).textTheme.labelSmall)
                ])),
          for (final child in children) _todoTile(child, depth + 1),
        ])));
  }
}
