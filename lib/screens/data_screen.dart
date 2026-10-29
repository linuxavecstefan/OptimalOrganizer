import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';

class DataField {
  final String key, label;
  final bool multiline;
  const DataField(this.key, this.label, {this.multiline = false});
}

/// Reusable offline CRUD view for the organizer's SQLite-backed modules.
class DataScreen extends StatefulWidget {
  final String title, table, displayColumn;
  final List<DataField> fields;
  final String orderBy;
  final bool checkable;
  const DataScreen(
      {super.key,
      required this.title,
      required this.table,
      required this.displayColumn,
      required this.fields,
      this.orderBy = 'id DESC',
      this.checkable = false});
  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  List<Map<String, Object?>> rows = [];
  Set<int> _checkedHabits = {};
  bool loading = true;
  DatabaseService get service => context.read<DatabaseService>();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = service.db;
    if (db == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final result = await db.query(widget.table, orderBy: widget.orderBy);
    Set<int> checked = {};
    if (widget.table == 'habits') {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final logs = await db
          .query('habit_log', where: 'completed_date = ?', whereArgs: [today]);
      checked = logs.map((r) => r['habit_id'] as int).toSet();
    }
    if (mounted) {
      setState(() {
        rows = result;
        _checkedHabits = checked;
        loading = false;
      });
    }
  }

  Future<void> _edit([Map<String, Object?>? row]) async {
    final ctrls = {
      for (final f in widget.fields)
        f.key: TextEditingController(text: row?[f.key]?.toString() ?? '')
    };
    final valid = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(row == null
                  ? 'Add ${widget.title.toLowerCase()}'
                  : 'Edit ${widget.title.toLowerCase()}'),
              content: SizedBox(
                  width: 460,
                  child: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final f in widget.fields)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                              controller: ctrls[f.key],
                              maxLines: f.multiline ? 4 : 1,
                              autofocus: widget.fields.first == f,
                              decoration: InputDecoration(
                                  labelText: f.label,
                                  border: const OutlineInputBorder())))
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
    if (valid != true) {
      for (final c in ctrls.values) {
        c.dispose();
      }
      return;
    }
    final Map<String, Object?> values = {
      for (final f in widget.fields) f.key: ctrls[f.key]!.text.trim()
    };
    for (final c in ctrls.values) {
      c.dispose();
    }
    if (values.values.every((v) => v == null || v.toString().isEmpty)) return;
    final db = service.db!;
    if (row == null) {
      if (widget.table == 'tasks') {
        final projects = await db.query('projects', limit: 1, orderBy: 'id');
        Object? projectId;
        if (projects.isEmpty) {
          projectId = await db.insert('projects', {'name': 'Inbox'});
        } else {
          projectId = projects.first['id'];
        }
        values['project_id'] = projectId;
      }
      if (widget.table == 'timer_sessions') {
        values['duration'] = int.tryParse('${values['duration']}') ?? 25;
      }
      if (widget.table == 'tasks') {
        values['priority'] = int.tryParse('${values['priority']}') ?? 0;
      }
      if (widget.table == 'journal_entries') {
        values['mood'] = int.tryParse('${values['mood']}');
      }
      await db.insert(widget.table, values);
    } else {
      await db.update(widget.table, values,
          where: 'id = ?', whereArgs: [row['id']]);
    }
    await _load();
  }

  Future<void> _delete(Map<String, Object?> row) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Delete item?'),
                content: Text(
                    '“${row[widget.displayColumn] ?? 'Item'}” will be removed.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'))
                ]));
    if (yes == true) {
      await service.db!
          .delete(widget.table, where: 'id = ?', whereArgs: [row['id']]);
      await _load();
    }
  }

  Future<void> _toggle(Map<String, Object?> row) async {
    final done = (row['completed'] as int? ?? 0) == 1;
    await service.db!.update(
        'todos',
        {
          'completed': done ? 0 : 1,
          'completed_at': done ? null : DateTime.now().toIso8601String()
        },
        where: 'id = ?',
        whereArgs: [row['id']]);
    await _load();
  }

  Future<void> _checkHabit(Map<String, Object?> row) async {
    final id = row['id'] as int;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (_checkedHabits.contains(id)) {
      await service.db!.delete('habit_log',
          where: 'habit_id = ? AND completed_date = ?', whereArgs: [id, today]);
    } else {
      await service.db!
          .insert('habit_log', {'habit_id': id, 'completed_date': today});
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh))
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _edit,
          icon: const Icon(Icons.add),
          label: const Text('Add')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.inbox_outlined,
                      size: 48, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Nothing here yet',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Text('Add an item to get started.')
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final r = rows[i];
                    final title = '${r[widget.displayColumn] ?? 'Untitled'}';
                    final subtitle = widget.fields
                        .where((f) =>
                            f.key != widget.displayColumn &&
                            (r[f.key]?.toString().isNotEmpty ?? false))
                        .map((f) => '${f.label}: ${r[f.key]}')
                        .join('  ·  ');
                    final done =
                        widget.checkable && (r['completed'] as int? ?? 0) == 1;
                    return Card(
                        child: ListTile(
                            leading: widget.checkable
                                ? Checkbox(
                                    value: done, onChanged: (_) => _toggle(r))
                                : CircleAvatar(child: Text('${i + 1}')),
                            title: Text(title,
                                style: TextStyle(
                                    decoration: done
                                        ? TextDecoration.lineThrough
                                        : null)),
                            subtitle: subtitle.isEmpty
                                ? null
                                : Text(subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                            onTap: () => _edit(r),
                            trailing:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              if (widget.table == 'habits')
                                IconButton(
                                    tooltip: _checkedHabits.contains(r['id'])
                                        ? 'Undo today’s check-in'
                                        : 'Mark done today',
                                    icon: Icon(_checkedHabits.contains(r['id'])
                                        ? Icons.check_circle
                                        : Icons.radio_button_unchecked),
                                    onPressed: () => _checkHabit(r)),
                              IconButton(
                                  tooltip: 'Delete',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _delete(r)),
                            ])));
                  }));
}
