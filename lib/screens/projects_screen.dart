import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Map<String, Object?>> _projects = [];
  Map<int, List<Map<String, Object?>>> _tasks = {};
  Future<void> _load() async {
    final db = context.read<DatabaseService>().db;
    if (db == null) return;
    final projects = await db.query('projects', orderBy: 'name COLLATE NOCASE');
    final tasks =
        await db.query('tasks', orderBy: 'priority DESC, created_at ASC');
    final byProject = <int, List<Map<String, Object?>>>{};
    for (final task in tasks) {
      (byProject[task['project_id'] as int] ??= []).add(task);
    }
    if (mounted)
      setState(() {
        _projects = projects;
        _tasks = byProject;
      });
  }

  Future<void> _editProject([Map<String, Object?>? project]) async {
    final name =
        TextEditingController(text: project?['name']?.toString() ?? '');
    final desc =
        TextEditingController(text: project?['description']?.toString() ?? '');
    final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(project == null ? 'New project' : 'Edit project'),
                content: SizedBox(
                    width: 420,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          autofocus: true,
                          decoration:
                              const InputDecoration(labelText: 'Project name')),
                      TextField(
                          controller: desc,
                          maxLines: 3,
                          decoration:
                              const InputDecoration(labelText: 'Description'))
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Save'))
                ]));
    final n = name.text.trim();
    final d = desc.text.trim();
    name.dispose();
    desc.dispose();
    if (save != true || n.isEmpty) return;
    final db = context.read<DatabaseService>().db!;
    if (project == null)
      await db.insert('projects', {'name': n, 'description': d});
    else
      await db.update('projects', {'name': n, 'description': d},
          where: 'id = ?', whereArgs: [project['id']]);
    await _load();
  }

  Future<void> _deleteProject(Map<String, Object?> project) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Delete project?'),
                content: Text('Delete “${project['name']}” and all its tasks?'),
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
          .delete('projects', where: 'id = ?', whereArgs: [project['id']]);
      await _load();
    }
  }

  Future<void> _openProject(Map<String, Object?> project) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(project: project)));
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Projects'), actions: [
        IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh))
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _editProject(),
          icon: const Icon(Icons.add),
          label: const Text('New project')),
      body: _projects.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.folder_open, size: 52),
              const SizedBox(height: 12),
              Text('Give your work a home',
                  style: Theme.of(context).textTheme.titleLarge),
              const Text('Create a project, then add tasks and track progress.')
            ]))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: _projects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = _projects[i];
                final tasks = _tasks[p['id'] as int] ?? [];
                final complete =
                    tasks.where((t) => t['status'] == 'done').length;
                final active = tasks.length - complete;
                final progress = tasks.isEmpty ? 0.0 : complete / tasks.length;
                return Card(
                    child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openProject(p),
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    const Icon(Icons.folder_outlined),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Text('${p['name']}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium)),
                                    PopupMenuButton<String>(
                                        onSelected: (v) => v == 'edit'
                                            ? _editProject(p)
                                            : _deleteProject(p),
                                        itemBuilder: (_) => const [
                                              PopupMenuItem(
                                                  value: 'edit',
                                                  child: Text('Edit')),
                                              PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text('Delete'))
                                            ])
                                  ]),
                                  if ((p['description'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(left: 36),
                                        child: Text('${p['description']}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis)),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                        child: LinearProgressIndicator(
                                            value: progress)),
                                    const SizedBox(width: 12),
                                    Text('$complete/${tasks.length} done')
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(
                                      '$active active task${active == 1 ? '' : 's'}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall)
                                ]))));
              }));
}

class ProjectDetailScreen extends StatefulWidget {
  final Map<String, Object?> project;
  const ProjectDetailScreen({super.key, required this.project});
  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  List<Map<String, Object?>> _tasks = [];
  Future<void> _load() async {
    final rows = await context.read<DatabaseService>().db?.query('tasks',
            where: 'project_id = ?',
            whereArgs: [widget.project['id']],
            orderBy: 'priority DESC, created_at ASC') ??
        [];
    if (mounted) setState(() => _tasks = rows);
  }

  Future<void> _addTask() async {
    final title = TextEditingController();
    final description = TextEditingController();
    int priority = 0;
    String recurrence = 'none';
    DateTime? due;
    final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                    title: const Text('Add task'),
                    content: SizedBox(
                        width: 440,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              TextField(
                                  controller: title,
                                  autofocus: true,
                                  decoration:
                                      const InputDecoration(labelText: 'Task')),
                              TextField(
                                  controller: description,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                      labelText: 'Details')),
                              DropdownButtonFormField<int>(
                                  value: priority,
                                  decoration: const InputDecoration(
                                      labelText: 'Priority'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 0, child: Text('Normal')),
                                    DropdownMenuItem(
                                        value: 1, child: Text('High')),
                                    DropdownMenuItem(
                                        value: 2, child: Text('Urgent'))
                                  ],
                                  onChanged: (v) =>
                                      update(() => priority = v ?? 0)),
                              DropdownButtonFormField<String>(
                                  value: recurrence,
                                  decoration: const InputDecoration(
                                      labelText: 'Repeat'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'none',
                                        child: Text('Does not repeat')),
                                    DropdownMenuItem(
                                        value: 'daily', child: Text('Daily')),
                                    DropdownMenuItem(
                                        value: 'weekly', child: Text('Weekly')),
                                    DropdownMenuItem(
                                        value: 'monthly',
                                        child: Text('Monthly'))
                                  ],
                                  onChanged: (v) =>
                                      update(() => recurrence = v ?? 'none')),
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                      onPressed: () async {
                                        final d = await showDatePicker(
                                            context: ctx,
                                            initialDate: due ?? DateTime.now(),
                                            firstDate: DateTime.now().subtract(
                                                const Duration(days: 365)),
                                            lastDate: DateTime.now().add(
                                                const Duration(days: 3650)));
                                        if (d != null) update(() => due = d);
                                      },
                                      icon: const Icon(Icons.calendar_today),
                                      label: Text(due == null
                                          ? 'Set due date'
                                          : DateFormat.yMMMd().format(due!))))
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Add task'))
                    ])));
    final t = title.text.trim();
    final d = description.text.trim();
    title.dispose();
    description.dispose();
    if (saved != true || t.isEmpty) return;
    await context.read<DatabaseService>().db!.insert('tasks', {
      'project_id': widget.project['id'],
      'title': t,
      'description': d,
      'priority': priority,
      'recurrence': recurrence,
      'due_date': due == null ? null : DateFormat('yyyy-MM-dd').format(due!)
    });
    await _load();
  }

  Future<void> _setStatus(Map<String, Object?> task, String status) async {
    final db = context.read<DatabaseService>().db!;
    final repeat = '${task['recurrence'] ?? 'none'}';
    if (status == 'done' && repeat != 'none') {
      final due =
          DateTime.tryParse('${task['due_date'] ?? ''}') ?? DateTime.now();
      DateTime next;
      if (repeat == 'daily') {
        next = due.add(const Duration(days: 1));
      } else if (repeat == 'weekly') {
        next = due.add(const Duration(days: 7));
      } else {
        next = DateTime(due.year, due.month + 1, due.day > 28 ? 28 : due.day);
      }
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
            'due_date': DateFormat('yyyy-MM-dd').format(next),
            'recurrence': repeat,
            'recurrence_end_date': task['recurrence_end_date']
          });
        }
      });
    } else {
      await db.update('tasks', {'status': status},
          where: 'id = ?', whereArgs: [task['id']]);
    }
    await _load();
  }

  Future<void> _deleteTask(Map<String, Object?> task) async {
    await context
        .read<DatabaseService>()
        .db!
        .delete('tasks', where: 'id = ?', whereArgs: [task['id']]);
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('${widget.project['name']}'), actions: [
        IconButton(
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh))
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _addTask,
          icon: const Icon(Icons.add),
          label: const Text('Add task')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if ((widget.project['description'] ?? '').toString().isNotEmpty)
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${widget.project['description']}')),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
                '${_tasks.where((t) => t['status'] == 'done').length} of ${_tasks.length} tasks complete',
                style: Theme.of(context).textTheme.titleSmall)),
        Expanded(
            child: _tasks.isEmpty
                ? const Center(child: Text('No tasks yet. Add the first one.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
                    itemCount: _tasks.length,
                    itemBuilder: (_, i) {
                      final task = _tasks[i];
                      final status = '${task['status'] ?? 'todo'}';
                      final due = task['due_date'] == null
                          ? ''
                          : ' · Due ${task['due_date']}';
                      return Card(
                          child: ListTile(
                              leading: IconButton(
                                  tooltip:
                                      'Mark ${status == 'done' ? 'active' : 'done'}',
                                  onPressed: () => _setStatus(
                                      task, status == 'done' ? 'todo' : 'done'),
                                  icon: Icon(status == 'done'
                                      ? Icons.check_circle
                                      : status == 'in_progress'
                                          ? Icons.pending
                                          : Icons.radio_button_unchecked)),
                              title: Text('${task['title']}',
                                  style: TextStyle(
                                      decoration: status == 'done'
                                          ? TextDecoration.lineThrough
                                          : null)),
                              subtitle:
                                  Text('${task['description'] ?? ''}$due'),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    PopupMenuButton<String>(
                                        tooltip: 'Change status',
                                        onSelected: (v) => _setStatus(task, v),
                                        itemBuilder: (_) => const [
                                              PopupMenuItem(
                                                  value: 'todo',
                                                  child: Text('To do')),
                                              PopupMenuItem(
                                                  value: 'in_progress',
                                                  child: Text('In progress')),
                                              PopupMenuItem(
                                                  value: 'done',
                                                  child: Text('Done'))
                                            ]),
                                    IconButton(
                                        tooltip: 'Delete task',
                                        onPressed: () => _deleteTask(task),
                                        icon: const Icon(Icons.delete_outline))
                                  ])));
                    }))
      ]));
}
