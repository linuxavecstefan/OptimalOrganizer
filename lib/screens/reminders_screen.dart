import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/database_service.dart';
import '../widgets/database_unavailable.dart';
import 'calendar_screen.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<Map<String, Object?>> _reminders = [];
  List<Map<String, Object?>> _upcomingEvents = [];
  List<Map<String, Object?>> _todosDue = [];
  bool _loading = true;

  String _date(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _dateTime(DateTime d) => DateFormat('yyyy-MM-dd HH:mm').format(d);

  Future<void> _load() async {
    final db = context.read<DatabaseService>().db;
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final now = DateTime.now();
    final today = _date(now);
    final inThreeDays = _date(now.add(const Duration(days: 3)));
    final reminderRows =
        await db.query('reminders', orderBy: 'remind_at ASC, id ASC');
    final upcoming = await db.query('events',
        where: 'date(start_time) BETWEEN ? AND ?',
        whereArgs: [today, inThreeDays],
        orderBy: 'start_time',
        limit: 5);
    final todosDue = await db.query('todos',
        where:
            'archived = 0 AND completed = 0 AND due_date IS NOT NULL AND due_date <= ?',
        whereArgs: [today],
        orderBy: 'due_date ASC',
        limit: 5);
    if (mounted) {
      setState(() {
        _reminders = reminderRows;
        _upcomingEvents = upcoming;
        _todosDue = todosDue;
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _edit([Map<String, Object?>? reminder]) async {
    final title = TextEditingController(text: '${reminder?['title'] ?? ''}');
    final note = TextEditingController(text: '${reminder?['note'] ?? ''}');
    DateTime? remind = DateTime.tryParse('${reminder?['remind_at'] ?? ''}');
    remind ??= DateTime.now().add(const Duration(hours: 1));
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text(reminder == null ? 'Add reminder' : 'Edit reminder'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: title,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Title')),
                TextField(
                    controller: note,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Note')),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: Text('Remind at ${_dateTime(remind!)}',
                          overflow: TextOverflow.ellipsis)),
                  TextButton(
                      onPressed: () async {
                        final d = await showDatePicker(
                            context: ctx,
                            initialDate: remind!,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100));
                        if (d == null) return;
                        final t = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay.fromDateTime(remind!));
                        if (t == null) return;
                        setStateDialog(() => remind = DateTime(
                            d.year, d.month, d.day, t.hour, t.minute));
                      },
                      child: const Text('Set time'))
                ])
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true || title.text.trim().isEmpty) {
      title.dispose();
      note.dispose();
      return;
    }
    final db = context.read<DatabaseService>().db!;
    final remindStr = '${_date(remind!)}T${DateFormat('HH:mm').format(remind!)}';
    final values = {
      'title': title.text.trim(),
      'note': note.text.trim(),
      'remind_at': remindStr,
    };
    if (reminder == null) {
      await db.insert('reminders', values);
    } else {
      await db.update('reminders', values,
          where: 'id = ?', whereArgs: [reminder['id']]);
    }
    title.dispose();
    note.dispose();
    await _load();
  }

  Future<void> _toggle(Map<String, Object?> r, bool done) async {
    final db = context.read<DatabaseService>().db!;
    await db.update('reminders', {'completed': done ? 1 : 0},
        where: 'id = ?', whereArgs: [r['id']]);
    await _load();
  }

  Future<void> _delete(Map<String, Object?> r) async {
    final db = context.read<DatabaseService>().db!;
    await db.delete('reminders', where: 'id = ?', whereArgs: [r['id']]);
    await _load();
  }

  Future<void> _retry() async {
    await context.read<DatabaseService>().init();
    if (mounted) {
      setState(() => _loading = true);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.read<DatabaseService>().db;
    if (db == null) return DatabaseUnavailable(onRetry: _retry);
    final now = DateTime.now();
    final isEmpty =
        _reminders.isEmpty && _upcomingEvents.isEmpty && _todosDue.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders & Notifications'), actions: [
        IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh)),
        IconButton(
            tooltip: 'View calendar',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const CalendarScreen())),
            icon: const Icon(Icons.calendar_month)),
      ]),
      floatingActionButton: FloatingActionButton(
          onPressed: () => _edit(), child: const Icon(Icons.add_alarm)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isEmpty
              ? const Center(
                  child: Text(
                      'No reminders yet. Add one for upcoming events/todos.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _reminders.length +
                      _upcomingEvents.length +
                      _todosDue.length,
                  itemBuilder: (context, i) {
                    if (i < _reminders.length) {
                      return _reminderTile(_reminders[i], now);
                    }
                    if (i < _reminders.length + _upcomingEvents.length) {
                      return _eventTile(
                          _upcomingEvents[i - _reminders.length], context);
                    }
                    return _todoTile(
                        _todosDue[i - _reminders.length - _upcomingEvents.length]);
                  }),
    );
  }

  Widget _reminderTile(Map<String, Object?> r, DateTime now) {
    final done = (r['completed'] as int?) == 1;
    final note = '${r['note'] ?? ''}';
    final remindAtStr = '${r['remind_at'] ?? ''}'.replaceFirst('T', ' ');
    DateTime? when;
    try {
      when = DateTime.parse('${r['remind_at'] ?? ''}');
    } catch (_) {}
    final past = when != null && when.isBefore(now);
    final subtitleParts = <String>[
      if (note.isNotEmpty) note,
      remindAtStr,
      if (past && !done) 'PAST DUE',
    ];
    return Card(
      child: ListTile(
        leading:
            Checkbox(value: done, onChanged: (v) => _toggle(r, v ?? false)),
        title: Text('${r['title']}',
            style: TextStyle(
                decoration: done ? TextDecoration.lineThrough : null)),
        subtitle: Text(subtitleParts.join('\n')),
        isThreeLine: subtitleParts.length > 1,
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') _edit(r);
            if (v == 'delete') _delete(r);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  Widget _eventTile(Map<String, Object?> e, BuildContext context) {
    final title = '${e['title']}';
    final dt = DateTime.tryParse('${e['start_time']}');
    final allDay = e['all_day'] == 1;
    final when = allDay
        ? 'All day'
        : dt == null
            ? ''
            : TimeOfDay.fromDateTime(dt).format(context);
    return ListTile(
      leading: Icon(allDay ? Icons.event_available : Icons.schedule),
      title: Text(title),
      subtitle: Text(when),
      trailing: IconButton(
        tooltip: 'Delete event',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _deleteEvent(e['id'] as int),
      ),
    );
  }

  Widget _todoTile(Map<String, Object?> t) {
    final title = '${t['title']}';
    final due = '${t['due_date'] ?? ''}';
    return ListTile(
      leading: const Icon(Icons.warning_amber),
      title: Text(title),
      subtitle: Text('Due: $due'),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'edit') _editTodo(t);
          if (v == 'delete') _deleteTodo(t);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  Future<void> _deleteEvent(int id) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Delete event?'),
              content: const Text('Delete this event?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete'))
              ],
            ));
    if (yes == true) {
      await context
          .read<DatabaseService>()
          .db!
          .delete('events', where: 'id = ?', whereArgs: [id]);
      await _load();
    }
  }

  Future<void> _editTodo(Map<String, Object?> todo) async {
    final title = TextEditingController(text: '${todo['title'] ?? ''}');
    DateTime? due = DateTime.tryParse('${todo['due_date'] ?? ''}');
    final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
              builder: (ctx, setStateDialog) => AlertDialog(
                title: const Text('Edit to-do'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                          controller: title,
                          autofocus: true,
                          decoration:
                              const InputDecoration(labelText: 'Title')),
                      const SizedBox(height: 8),
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
                              if (d == null) return;
                              setStateDialog(() => due = d);
                            },
                            child: const Text('Set due date')),
                      ]),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Save')),
                ],
              ),
            ));
    if (saved == true && title.text.trim().isNotEmpty) {
      await context.read<DatabaseService>().db!.update(
          'todos',
          {
            'title': title.text.trim(),
            'due_date': due == null ? null : _date(due!),
          },
          where: 'id = ?',
          whereArgs: [todo['id']]);
      await _load();
    }
    title.dispose();
  }

  Future<void> _deleteTodo(Map<String, Object?> todo) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Delete to-do?'),
              content: Text('Delete "${todo['title']}"?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete'))
              ],
            ));
    if (yes == true) {
      await context
          .read<DatabaseService>()
          .db!
          .delete('todos', where: 'id = ?', whereArgs: [todo['id']]);
      await _load();
    }
  }
}
