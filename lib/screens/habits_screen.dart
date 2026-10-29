import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../widgets/database_unavailable.dart';

class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key});
  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen> {
  List<Map<String, Object?>> _habits = [];
  Set<int> _doneToday = {};
  Map<int, Set<String>> _history = {};
  bool _loading = true;

  Future<void> _load() async {
    final db = context.read<DatabaseService>().db;
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final habits = await db.query('habits', orderBy: 'sort_order, id');
    final today = DateTime.now();
    final logs = await db.query('habit_log', orderBy: 'completed_date');
    final byId = <int, Set<String>>{};
    for (final log in logs) {
      (byId[log['habit_id'] as int] ??= {})
          .add(log['completed_date'] as String);
    }
    if (!mounted) return;
    setState(() {
      _habits = habits;
      _history = byId;
      _doneToday = {
        for (final e in byId.entries)
          if (e.value.contains(_date(today))) e.key
      };
      _loading = false;
    });
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int _streak(Set<String> days, {bool longest = false}) {
    if (days.isEmpty) return 0;
    final sorted = days.map(DateTime.parse).toList()..sort();
    if (longest) {
      var best = 1, run = 1;
      for (var i = 1; i < sorted.length; i++) {
        if (_dayGap(sorted[i], sorted[i - 1]) == 1) {
          run++;
        } else {
          run = 1;
        }
        if (run > best) best = run;
      }
      return best;
    }
    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    if (!days.contains(_date(cursor)))
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    var count = 0;
    while (days.contains(_date(cursor))) {
      count++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return count;
  }

  int _dayGap(DateTime a, DateTime b) => DateTime.utc(a.year, a.month, a.day)
      .difference(DateTime.utc(b.year, b.month, b.day))
      .inDays;

  Future<void> _edit([Map<String, Object?>? habit]) async {
    final name = TextEditingController(text: habit?['name']?.toString() ?? '');
    final description =
        TextEditingController(text: habit?['description']?.toString() ?? '');
    final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(habit == null ? 'Create a habit' : 'Edit habit'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Habit name')),
                const SizedBox(height: 12),
                TextField(
                    controller: description,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Description (optional)'))
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save'))
              ],
            ));
    final n = name.text.trim();
    final d = description.text.trim();
    name.dispose();
    description.dispose();
    if (save != true || n.isEmpty) return;
    final db = context.read<DatabaseService>().db!;
    try {
      if (habit == null) {
        await db.insert('habits', {
          'name': n,
          'description': d,
          'sort_order': _habits.length,
        });
      } else {
        await db.update('habits', {'name': n, 'description': d},
            where: 'id = ?', whereArgs: [habit['id']]);
      }
      await _load();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('A habit with that name already exists.')));
    }
  }

  Future<void> _toggle(Map<String, Object?> habit) async {
    final id = habit['id'] as int;
    final today = _date(DateTime.now());
    final db = context.read<DatabaseService>().db!;
    if (_doneToday.contains(id)) {
      await db.delete('habit_log',
          where: 'habit_id = ? AND completed_date = ?', whereArgs: [id, today]);
    } else {
      await db.insert('habit_log', {'habit_id': id, 'completed_date': today});
    }
    await _load();
  }

  Future<void> _delete(Map<String, Object?> habit) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Delete habit?'),
                content:
                    Text('Delete “${habit['name']}” and its check-in history?'),
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
          .delete('habits', where: 'id = ?', whereArgs: [habit['id']]);
      await _load();
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final updated = [..._habits];
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    final db = context.read<DatabaseService>().db!;
    await db.transaction((txn) async {
      for (var i = 0; i < updated.length; i++) {
        await txn.update('habits', {'sort_order': i},
            where: 'id = ?', whereArgs: [updated[i]['id']]);
      }
    });
    if (mounted) setState(() => _habits = updated);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Habit Tracker'), actions: [
          IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh))
        ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Add habit')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : context.read<DatabaseService>().db == null
                ? DatabaseUnavailable(
                    message:
                        context.read<DatabaseService>().initializationError,
                    onRetry: () async {
                      await context.read<DatabaseService>().init();
                      await _load();
                    })
                : _habits.isEmpty
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.check_circle_outline, size: 52),
                        const SizedBox(height: 12),
                        Text('Build a little momentum',
                            style: Theme.of(context).textTheme.titleLarge),
                        const Text('Add a habit, then check it off each day.')
                      ]))
                    : ReorderableListView.builder(
                        onReorder: _reorder,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 92),
                        itemCount: _habits.length,
                        buildDefaultDragHandles: false,
                        itemBuilder: (ctx, i) {
                          final habit = _habits[i];
                          final id = habit['id'] as int;
                          final days = _history[id] ?? {};
                          final done = _doneToday.contains(id);
                          final streak = _streak(days);
                          final best = _streak(days, longest: true);
                          return Card(
                              key: ValueKey('habit-${habit['id']}'),
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(children: [
                                          ReorderableDragStartListener(
                                              index: i,
                                              child: const Padding(
                                                padding: EdgeInsets.all(8),
                                                child:
                                                    Icon(Icons.drag_indicator),
                                              )),
                                          Checkbox(
                                              value: done,
                                              onChanged: (_) => _toggle(habit)),
                                          Expanded(
                                              child: InkWell(
                                                  onTap: () => _edit(habit),
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text('${habit['name']}',
                                                            style: Theme.of(
                                                                    context)
                                                                .textTheme
                                                                .titleMedium
                                                                ?.copyWith(
                                                                    decoration: done
                                                                        ? TextDecoration
                                                                            .lineThrough
                                                                        : null)),
                                                        if ((habit['description'] ??
                                                                '')
                                                            .toString()
                                                            .isNotEmpty)
                                                          Text(
                                                              '${habit['description']}',
                                                              style: Theme.of(
                                                                      context)
                                                                  .textTheme
                                                                  .bodySmall)
                                                      ]))),
                                          Text('🔥 $streak',
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                  fontWeight: FontWeight.bold)),
                                          PopupMenuButton<String>(
                                              onSelected: (v) => v == 'edit'
                                                  ? _edit(habit)
                                                  : _delete(habit),
                                              itemBuilder: (_) => const [
                                                    PopupMenuItem(
                                                        value: 'edit',
                                                        child: Text('Edit')),
                                                    PopupMenuItem(
                                                        value: 'delete',
                                                        child: Text('Delete'))
                                                  ])
                                        ]),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 52, top: 4),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Current streak $streak days  ·  Best $best days  ·  ${List.generate(14, (d) => _date(DateTime.now().subtract(Duration(days: d)))).where(days.contains).length}/14 in the last 14 days',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                                const SizedBox(height: 9),
                                                Row(children: [
                                                  for (var d = 13; d >= 0; d--)
                                                    Expanded(
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 2),
                                                        child: Tooltip(
                                                          message: _date(DateTime
                                                                  .now()
                                                              .subtract(
                                                                  Duration(
                                                                      days:
                                                                          d))),
                                                          child: Container(
                                                            height: 9,
                                                            decoration:
                                                                BoxDecoration(
                                                              color: days.contains(_date(DateTime
                                                                          .now()
                                                                      .subtract(Duration(
                                                                          days:
                                                                              d))))
                                                                  ? Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .primary
                                                                  : Theme.of(
                                                                          context)
                                                                      .colorScheme
                                                                      .surface,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ]),
                                              ]),
                                        ),
                                      ])));
                        }),
      );
}
