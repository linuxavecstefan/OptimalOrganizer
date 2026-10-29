import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../services/database_service.dart';

class GanttScreen extends StatefulWidget {
  const GanttScreen({super.key});
  @override
  State<GanttScreen> createState() => _GanttScreenState();
}

class _GanttScreenState extends State<GanttScreen> {
  static const _weeksShown = 26;
  static const _weekWidth = 76.0;
  List<Map<String, Object?>> _tasks = [];
  List<Map<String, Object?>> _projects = [];
  DateTime _start = DateTime.now();
  bool _loading = true;

  DateTime _monday(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
  String _date(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  Future<void> _load() async {
    final db = context.read<DatabaseService>().db;
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final tasks =
        await db.query('tasks', orderBy: 'project_id, due_date, created_at');
    final projects = await db.query('projects', orderBy: 'name COLLATE NOCASE');
    if (!mounted) return;
    setState(() {
      _tasks = tasks;
      _projects = projects;
      _start = _monday(DateTime.now());
      _loading = false;
    });
  }

  Future<void> _addTask() async {
    final db = context.read<DatabaseService>().db;
    if (db == null) return;
    if (_projects.isEmpty) {
      await db.insert('projects', {'name': 'Inbox'});
      await _load();
    }
    final title = TextEditingController();
    int? project = _projects.isEmpty ? null : _projects.first['id'] as int;
    DateTime? due;
    String recurrence = 'none';
    DateTime? recurrenceEnd;
    final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: const Text('Add timeline task'),
                  content: SizedBox(
                      width: 420,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(
                            controller: title,
                            autofocus: true,
                            decoration:
                                const InputDecoration(labelText: 'Task title')),
                        DropdownButtonFormField<int>(
                            value: project,
                            decoration:
                                const InputDecoration(labelText: 'Project'),
                            items: [
                              for (final p in _projects)
                                DropdownMenuItem(
                                    value: p['id'] as int,
                                    child: Text('${p['name']}'))
                            ],
                            onChanged: (v) => update(() => project = v)),
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
                              child: const Text('Choose'))
                        ]),
                        DropdownButtonFormField<String>(
                            value: recurrence,
                            decoration:
                                const InputDecoration(labelText: 'Recurrence'),
                            items: const [
                              DropdownMenuItem(value: 'none', child: Text('None')),
                              DropdownMenuItem(value: 'daily', child: Text('Daily')),
                              DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                              DropdownMenuItem(value: 'monthly', child: Text('Monthly'))
                            ],
                            onChanged: (v) =>
                                update(() => recurrence = v ?? 'none')),
                        if (recurrence != 'none')
                          Row(children: [
                            Expanded(
                                child: Text(recurrenceEnd == null
                                    ? 'Repeats with no end date'
                                    : 'Repeats until ${_date(recurrenceEnd!)}')),
                            TextButton(
                                onPressed: () async {
                                  final d = await showDatePicker(
                                      context: ctx,
                                      initialDate: recurrenceEnd ??
                                          (due ?? DateTime.now()),
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100));
                                  if (d != null) {
                                    update(() => recurrenceEnd = d);
                                  }
                                },
                                child: const Text('End date')),
                            if (recurrenceEnd != null)
                              IconButton(
                                  tooltip: 'Clear end date',
                                  icon: const Icon(Icons.clear),
                                  onPressed: () =>
                                      update(() => recurrenceEnd = null)),
                          ])
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Add'))
                  ],
                )));
    final text = title.text.trim();
    title.dispose();
    if (saved != true || text.isEmpty || project == null) return;
    await db.insert('tasks', {
      'project_id': project,
      'title': text,
      'status': 'todo',
      'due_date': due == null ? null : _date(due!),
      'recurrence': recurrence,
      'recurrence_end_date':
          recurrenceEnd == null ? null : _date(recurrenceEnd!)
    });
    await _load();
  }

  Future<void> _setStatus(Map<String, Object?> task, String status) async {
    final db = context.read<DatabaseService>().db;
    if (db == null) return;
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

  String _projectName(Object? id) =>
      _projects
          .where((p) => p['id'] == id)
          .map((p) => '${p['name']}')
          .firstOrNull ??
      'Project';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Project Timeline'), actions: [
          IconButton(
              tooltip: 'Previous 26 weeks',
              onPressed: () => setState(
                  () => _start = _start.subtract(const Duration(days: 182))),
              icon: const Icon(Icons.chevron_left)),
          IconButton(
              tooltip: 'Today',
              onPressed: () => setState(() => _start = _monday(DateTime.now())),
              icon: const Icon(Icons.today)),
          IconButton(
              tooltip: 'Next 26 weeks',
              onPressed: () => setState(
                  () => _start = _start.add(const Duration(days: 182))),
              icon: const Icon(Icons.chevron_right)),
          IconButton(
              onPressed: _load,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh))
        ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _addTask,
            icon: const Icon(Icons.add),
            label: const Text('Add task')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _tasks.isEmpty
                ? const Center(
                    child: Text(
                        'Add tasks to a project to see them on the timeline.'))
                : LayoutBuilder(builder: (context, constraints) {
                    final totalWidth = _weeksShown * _weekWidth;
                    final grouped = <int, List<Map<String, Object?>>>{};
                    for (final task in _tasks) {
                      (grouped[task['project_id'] as int] ??= []).add(task);
                    }
                    return Scrollbar(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: totalWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _header(totalWidth),
                              Expanded(
                                child: ListView(
                                  padding: const EdgeInsets.only(bottom: 88),
                                  children: [
                                    for (final entry in grouped.entries) ...[
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.fromLTRB(
                                            12, 12, 12, 8),
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceVariant,
                                        child: Text(_projectName(entry.key),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall),
                                      ),
                                      for (final task in entry.value)
                                        _taskRow(task, totalWidth),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
      );

  Widget _header(double width) {
    final now = DateTime.now();
    return SizedBox(
        height: 78,
        width: width,
        child: Stack(children: [
          for (var i = 0; i < _weeksShown; i++)
            Positioned(
                left: i * _weekWidth,
                top: 0,
                bottom: 0,
                width: _weekWidth,
                child: Container(
                    decoration: BoxDecoration(
                        border: Border(
                            left: BorderSide(
                                color: Theme.of(context).dividerColor))),
                    padding: const EdgeInsets.only(left: 6, top: 8),
                    child: Text(
                        DateFormat('MMM d')
                            .format(_start.add(Duration(days: i * 7))),
                        style: Theme.of(context).textTheme.labelSmall))),
          Positioned(
              left: _weekWidth *
                  (now.difference(_start).inDays / 7)
                      .clamp(0, _weeksShown)
                      .toDouble(),
              top: 32,
              bottom: 0,
              child: Container(
                  width: 2, color: Theme.of(context).colorScheme.error)),
        ]));
  }

  Widget _taskRow(Map<String, Object?> task, double width) {
    final created =
        DateTime.tryParse('${task['created_at'] ?? ''}') ?? DateTime.now();
    final dueValue = DateTime.tryParse('${task['due_date'] ?? ''}');
    final start =
        dueValue == null && created.isBefore(_start) ? _start : created;
    final due = dueValue ?? start.add(const Duration(days: 6));
    final totalDays = _weeksShown * 7;
    var startDay = start.difference(_start).inDays;
    var endDay = due.difference(_start).inDays;
    if (endDay < startDay) endDay = startDay;
    final left = (startDay / 7 * _weekWidth).clamp(0.0, width);
    final right = (endDay / 7 * _weekWidth).clamp(0.0, width);
    final barWidth =
        (right - left).clamp(14.0, width - left > 14 ? width - left : 14.0);
    final color = task['status'] == 'done'
        ? Colors.green
        : task['status'] == 'in_progress'
            ? Colors.orange
            : Theme.of(context).colorScheme.primary;
    return SizedBox(
        height: 58,
        width: width,
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          for (var i = 0; i < _weeksShown; i++)
            Positioned(
                left: i * _weekWidth,
                top: 0,
                bottom: 0,
                child: Container(
                    width: 1,
                    color: Theme.of(context).dividerColor.withOpacity(.35))),
          Positioned(
            left: 8,
            top: 5,
            child: SizedBox(
              width: 300,
              child: Row(children: [
                Expanded(
                    child: Text('${task['title']}',
                        overflow: TextOverflow.ellipsis)),
                PopupMenuButton<String>(
                  tooltip: 'Task status',
                  onSelected: (v) => _setStatus(task, v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'todo', child: Text('To do')),
                    PopupMenuItem(
                        value: 'in_progress', child: Text('In progress')),
                    PopupMenuItem(value: 'done', child: Text('Done')),
                  ],
                ),
              ]),
            ),
          ),
          if (startDay < totalDays && endDay >= 0)
            Positioned(
                left: left,
                top: 34,
                width: barWidth,
                height: 16,
                child: Tooltip(
                    message:
                        '${task['title']} · ${_date(created)} to ${_date(due)}',
                    child: Container(
                        decoration: BoxDecoration(
                            color: color.withOpacity(.8),
                            borderRadius: BorderRadius.circular(8))))),
          Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Divider(
                  height: 1,
                  color: Theme.of(context).dividerColor.withOpacity(.4))),
        ]));
  }
}