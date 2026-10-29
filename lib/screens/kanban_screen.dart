import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/database_service.dart';

class KanbanScreen extends StatefulWidget {
  const KanbanScreen({super.key});
  @override
  State<KanbanScreen> createState() => _KanbanScreenState();
}

class _KanbanScreenState extends State<KanbanScreen> {
  static const _statuses = ['todo', 'in_progress', 'done'];
  List<Map<String, Object?>> _tasks = [];
  List<Map<String, Object?>> _projects = [];
  bool _loading = true;

  Future<void> _load() async {
    final db = context.read<DatabaseService>().db;
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final tasks =
        await db.query('tasks', orderBy: 'priority DESC, due_date, created_at');
    final projects = await db.query('projects', orderBy: 'name COLLATE NOCASE');
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _projects = projects;
      _loading = false;
    });
  }

  Future<void> _edit([Map<String, Object?>? task]) async {
    final title = TextEditingController(text: '${task?['title'] ?? ''}');
    final description =
        TextEditingController(text: '${task?['description'] ?? ''}');
    final projects = _projects;
    int? projectId = task?['project_id'] as int? ??
        (projects.isEmpty ? null : projects.first['id'] as int);
    int priority = task?['priority'] as int? ?? 0;
    String status = '${task?['status'] ?? 'todo'}';
    DateTime? due = DateTime.tryParse('${task?['due_date'] ?? ''}');
    final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: Text(task == null ? 'New task' : 'Edit task'),
                  content: SizedBox(
                      width: 460,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                            controller: title,
                            autofocus: true,
                            decoration:
                                const InputDecoration(labelText: 'Task title')),
                        TextField(
                            controller: description,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                                labelText: 'Description')),
                        DropdownButtonFormField<int>(
                            value: projectId,
                            decoration:
                                const InputDecoration(labelText: 'Project'),
                            items: [
                              for (final p in projects)
                                DropdownMenuItem(
                                    value: p['id'] as int,
                                    child: Text('${p['name']}'))
                            ],
                            onChanged: (v) => update(() => projectId = v)),
                        DropdownButtonFormField<String>(
                            value: status,
                            decoration:
                                const InputDecoration(labelText: 'Status'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'todo', child: Text('To do')),
                              DropdownMenuItem(
                                  value: 'in_progress',
                                  child: Text('In progress')),
                              DropdownMenuItem(
                                  value: 'done', child: Text('Done'))
                            ],
                            onChanged: (v) =>
                                update(() => status = v ?? 'todo')),
                        DropdownButtonFormField<int>(
                            value: priority,
                            decoration:
                                const InputDecoration(labelText: 'Priority'),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('Normal')),
                              DropdownMenuItem(value: 1, child: Text('High')),
                              DropdownMenuItem(value: 2, child: Text('Urgent'))
                            ],
                            onChanged: (v) => update(() => priority = v ?? 0)),
                        Row(children: [
                          Expanded(
                              child: Text(due == null
                                  ? 'No due date'
                                  : 'Due ${_date(due!)}')),
                          TextButton(
                              onPressed: () async {
                                final d = await showDatePicker(
                                    context: ctx,
                                    initialDate: due ?? DateTime.now(),
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100));
                                if (d != null) update(() => due = d);
                              },
                              child: const Text('Choose')),
                          if (due != null)
                            IconButton(
                                onPressed: () => update(() => due = null),
                                icon: const Icon(Icons.clear))
                        ]),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Save'))
                  ],
                )));
    final t = title.text.trim();
    final d = description.text.trim();
    title.dispose();
    description.dispose();
    if (saved != true || t.isEmpty) return;
    final db = context.read<DatabaseService>().db!;
    if (task == null) {
      if (projectId == null) {
        projectId = await db.insert('projects',
            {'name': 'Inbox', 'description': 'Tasks without a project'});
      }
      await db.insert('tasks', {
        'project_id': projectId,
        'title': t,
        'description': d,
        'status': status,
        'priority': priority,
        'due_date': due == null ? null : _date(due!)
      });
    } else {
      await db.update(
          'tasks',
          {
            'title': t,
            'description': d,
            'project_id': projectId,
            'status': status,
            'priority': priority,
            'due_date': due == null ? null : _date(due!)
          },
          where: 'id = ?',
          whereArgs: [task['id']]);
    }
    await _load();
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _projectName(Object? id) =>
      _projects
          .where((p) => p['id'] == id)
          .map((p) => '${p['name']}')
          .firstOrNull ??
      'Unknown project';

  Future<void> _move(Map<String, Object?> task, String status) async {
    if (task['status'] == status) return;
    final db = context.read<DatabaseService>().db!;
    final recurrence = '${task['recurrence'] ?? 'none'}';
    if (status == 'done' && recurrence != 'none') {
      final due =
          DateTime.tryParse('${task['due_date'] ?? ''}') ?? DateTime.now();
      final next = recurrence == 'daily'
          ? due.add(const Duration(days: 1))
          : recurrence == 'weekly'
              ? due.add(const Duration(days: 7))
              : DateTime(due.year, due.month + 1, due.day > 28 ? 28 : due.day);
      final end = DateTime.tryParse('${task['recurrence_end_date'] ?? ''}');
      await db.transaction((txn) async {
        await txn.update('tasks', {'status': 'done'},
            where: 'id = ?', whereArgs: [task['id']]);
        if (end == null || !next.isAfter(end)) {
          await txn.insert('tasks', {
            'project_id': task['project_id'],
            'title': task['title'],
            'description': task['description'],
            'priority': task['priority'],
            'due_date': _date(next),
            'recurrence': recurrence,
            'recurrence_end_date': task['recurrence_end_date'],
          });
        }
      });
    } else {
      await db.update('tasks', {'status': status},
          where: 'id = ?', whereArgs: [task['id']]);
    }
    await _load();
  }

  Future<void> _delete(Map<String, Object?> task) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Delete task?'),
                content: Text('“${task['title']}” will be removed.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'))
                ]));
    if (yes == true) {
      await context
          .read<DatabaseService>()
          .db!
          .delete('tasks', where: 'id = ?', whereArgs: [task['id']]);
      await _load();
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Kanban Board'), actions: [
          IconButton(
              onPressed: _load,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh))
        ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('New task')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(builder: (context, constraints) {
                final horizontal = constraints.maxWidth < 680;
                final columns = [
                  for (final status in _statuses) _column(status)
                ];
                return horizontal
                    ? PageView(children: columns)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                            for (final column in columns)
                              Expanded(child: column)
                          ]);
              }),
      );

  Widget _column(String status) {
    final tasks = _tasks.where((t) => t['status'] == status).toList();
    final label = switch (status) {
      'todo' => 'To do',
      'in_progress' => 'In progress',
      _ => 'Done'
    };
    final color = switch (status) {
      'todo' => Colors.blue,
      'in_progress' => Colors.orange,
      _ => Colors.green
    };
    return DragTarget<Map<String, Object?>>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (detail) => _move(detail.data, status),
      builder: (context, candidates, rejected) => Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: candidates.isNotEmpty
                ? color.withOpacity(.08)
                : Theme.of(context).colorScheme.surfaceVariant,
            borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(label,
                        style: Theme.of(context).textTheme.titleMedium)),
                Badge(label: Text('${tasks.length}'))
              ])),
          Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Text(
                          candidates.isNotEmpty ? 'Drop task here' : 'No tasks',
                          style: Theme.of(context).textTheme.bodySmall))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 80),
                      children: [for (final task in tasks) _taskCard(task)])),
        ]),
      ),
    );
  }

  Widget _taskCard(Map<String, Object?> task) =>
      Draggable<Map<String, Object?>>(
        data: task,
        feedback: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: 280, child: _cardContents(task))),
        childWhenDragging: Opacity(opacity: .3, child: _cardContents(task)),
        child: _cardContents(task),
      );

  Widget _cardContents(Map<String, Object?> task) => Card(
      child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _edit(task),
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text('${task['title']}',
                              style: Theme.of(context).textTheme.titleSmall)),
                      PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit')
                              _edit(task);
                            else if (v == 'delete')
                              _delete(task);
                            else
                              _move(task, v);
                          },
                          itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 'todo',
                                    child: Text('Move to To do')),
                                const PopupMenuItem(
                                    value: 'in_progress',
                                    child: Text('Move to In progress')),
                                const PopupMenuItem(
                                    value: 'done', child: Text('Move to Done')),
                                const PopupMenuDivider(),
                                const PopupMenuItem(
                                    value: 'edit', child: Text('Edit')),
                                const PopupMenuItem(
                                    value: 'delete', child: Text('Delete'))
                              ])
                    ]),
                    if ('${task['description'] ?? ''}'.isNotEmpty)
                      Text('${task['description']}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      Chip(
                          avatar: const Icon(Icons.folder_outlined, size: 16),
                          label: Text(_projectName(task['project_id']),
                              overflow: TextOverflow.ellipsis)),
                      if ((task['priority'] as int? ?? 0) > 0)
                        Chip(
                            avatar: const Icon(Icons.flag_outlined, size: 16),
                            label: Text(
                                task['priority'] == 2 ? 'Urgent' : 'High')),
                      if (task['due_date'] != null)
                        Chip(
                            avatar: const Icon(Icons.event_outlined, size: 16),
                            label: Text('${task['due_date']}'))
                    ]),
                  ]))));
}
