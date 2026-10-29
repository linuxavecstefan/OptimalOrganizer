import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _habitsDone = 0,
      _habitsTotal = 0,
      _eventsToday = 0,
      _capturesToday = 0,
      _tasksTodo = 0;
  List<Map<String, Object?>> _habits = [], _upcoming = [];
  List<Map<String, Object?>> _reminders = [];
  List<Map<String, Object?>> _todosDue = [];
  Map<int, int> _streaks = {}, _best = {}, _last90 = {};
  Set<int> _doneToday = {};
  DateTime _now = DateTime.now();
  bool _loading = true;
  Timer? _clock;
  String _date(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  int _streak(Set<String> dates, {bool longest = false}) {
    if (dates.isEmpty) return 0;
    final ordered = dates.map(DateTime.parse).toList()..sort();
    if (longest) {
      var best = 1, run = 1;
      for (var i = 1; i < ordered.length; i++) {
        if (_dayGap(ordered[i], ordered[i - 1]) == 1) {
          run++;
        } else {
          run = 1;
        }
        if (run > best) best = run;
      }
      return best;
    }
    var d = DateTime.now();
    d = DateTime(d.year, d.month, d.day);
    if (!dates.contains(_date(d)))
      d = DateTime(d.year, d.month, d.day - 1);
    var n = 0;
    while (dates.contains(_date(d))) {
      n++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return n;
  }

  int _dayGap(DateTime a, DateTime b) => DateTime.utc(a.year, a.month, a.day)
      .difference(DateTime.utc(b.year, b.month, b.day))
      .inDays;

  Future<void> _load() async {
    final db = context.read<DatabaseService>().db;
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final now = DateTime.now();
    final today = _date(now);
    final inThreeDays = _date(now.add(const Duration(days: 3)));
    final habits = await db.query('habits', orderBy: 'name COLLATE NOCASE');
    final logs = await db.query('habit_log');
    final logged = <int, Set<String>>{};
    for (final row in logs) {
      (logged[row['habit_id'] as int] ??= {})
          .add(row['completed_date'] as String);
    }
    final events = await db.query('events',
        where: 'date(start_time) = ?',
        whereArgs: [today],
        orderBy: 'start_time');
    final upcoming = await db.query('events',
        where: 'date(start_time) BETWEEN ? AND ?',
        whereArgs: [today, inThreeDays],
        orderBy: 'start_time',
        limit: 5);
    final captures = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM captures WHERE date(created_at) = ?',
        [today]);
    final todos = await db
        .rawQuery("SELECT COUNT(*) AS n FROM tasks WHERE status = 'todo'");
    try {
      final reminders = await db.query('reminders',
          where: 'completed = 0', orderBy: 'remind_at ASC', limit: 5);
      if (mounted) setState(() => _reminders = reminders);
    } catch (_) {}
    try {
      final todosDue = await db.query('todos',
          where: "archived = 0 AND completed = 0 AND due_date IS NOT NULL AND due_date <= ?",
          whereArgs: [today],
          orderBy: 'due_date ASC',
          limit: 5);
      if (mounted) setState(() => _todosDue = todosDue);
    } catch (_) {
      try {
        final todosDue = await db.query('todos',
            where: "completed = 0 AND due_date IS NOT NULL AND due_date <= ?",
            whereArgs: [today],
            orderBy: 'due_date ASC',
            limit: 5);
        if (mounted) setState(() => _todosDue = todosDue);
      } catch (_) {}
    }
    final streaks = <int, int>{}, best = <int, int>{}, last90 = <int, int>{};
    for (final h in habits) {
      final id = h['id'] as int;
      final dates = logged[id] ?? {};
      streaks[id] = _streak(dates);
      best[id] = _streak(dates, longest: true);
      last90[id] = dates
          .where((d) =>
              DateTime.tryParse(d)
                  ?.isAfter(now.subtract(const Duration(days: 90))) ??
              false)
          .length;
    }
    if (!mounted) return;
    setState(() {
      _habits = habits;
      _upcoming = upcoming;
      _streaks = streaks;
      _best = best;
      _last90 = last90;
      _doneToday = {
        for (final h in habits)
          if ((logged[h['id'] as int] ?? {}).contains(today)) h['id'] as int
      };
      _habitsTotal = habits.length;
      _habitsDone = _doneToday.length;
      _eventsToday = events.length;
      _capturesToday = (captures.first['n'] as int?) ?? 0;
      _tasksTodo = (todos.first['n'] as int?) ?? 0;
      _now = now;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String get _greeting => _now.hour < 12
      ? 'Good morning!'
      : _now.hour < 17
          ? 'Good afternoon!'
          : _now.hour < 21
              ? 'Good evening!'
              : 'Still going?';
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('OptimalOrganizer'), actions: [
        IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: _load,
            icon: const Icon(Icons.refresh))
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    Text(_greeting,
                        style: Theme.of(context).textTheme.headlineMedium),
                    Text(DateFormat('EEEE, MMMM d').format(_now),
                        style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 18),
                    LayoutBuilder(builder: (context, c) {
                      final columns = c.maxWidth > 920
                          ? 4
                          : c.maxWidth > 500
                              ? 2
                              : 1;
                      return GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: columns,
                          childAspectRatio: columns == 1 ? 4.3 : 2.3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          children: [
                            _statCard(
                                'Habits',
                                '$_habitsDone / $_habitsTotal',
                                Icons.check_circle_outline,
                                _habitsTotal == 0
                                    ? 0
                                    : _habitsDone / _habitsTotal),
                            _statCard('Events today', '$_eventsToday',
                                Icons.event_outlined),
                            _statCard('Ideas captured', '$_capturesToday',
                                Icons.bolt_outlined),
                            _statCard(
                                'Tasks to do', '$_tasksTodo', Icons.task_alt),
                          ]);
                    }),
                    const SizedBox(height: 20),
                    if (_reminders.isNotEmpty) ...[
                      Text('Reminders & upcoming alerts',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Card(
                          child: Column(
                              children: _reminders
                                  .map((r) => ListTile(
                                      leading: const Icon(Icons.alarm),
                                      title: Text('${r['title']}'),
                                      subtitle: Text(
                                          '${r['remind_at']}'.replaceFirst('T', ' '))))
                                  .toList())),
                      const SizedBox(height: 16),
                    ],
                    if (_todosDue.isNotEmpty) ...[
                      Text('Todos due today/overdue',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Card(
                          child: Column(
                              children: _todosDue
                                  .map((t) => ListTile(
                                      leading: const Icon(Icons.warning_amber),
                                      title: Text('${t['title']}'),
                                      subtitle: Text('Due ${t['due_date']}')))
                                  .toList())),
                      const SizedBox(height: 16),
                    ],
                    Text('Habit streaks',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    if (_habits.isEmpty)
                      const Card(
                          child: ListTile(
                              leading: Icon(Icons.add_task),
                              title: Text('No habits yet'),
                              subtitle: Text(
                                  'Add a habit to start building a streak.')))
                    else
                      ..._habits.map((h) {
                        final id = h['id'] as int;
                        final streak = _streaks[id] ?? 0;
                        final complete = _doneToday.contains(id);
                        final all = _last90[id] ?? 0;
                        return Card(
                            child: ListTile(
                          leading: Icon(
                              complete
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: complete
                                  ? Theme.of(context).colorScheme.primary
                                  : null),
                          title: Text('${h['name']}'),
                          subtitle: Text(
                              '🔥 $streak day streak  ·  Best ${_best[id] ?? 0} days  ·  $all/90 days'),
                          trailing: Text('${(all / 90 * 100).round()}%'),
                        ));
                      }),
                    const SizedBox(height: 20),
                    Text('Upcoming events',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    if (_upcoming.isEmpty)
                      const Card(
                          child: ListTile(
                              leading: Icon(Icons.event_busy),
                              title: Text('Nothing coming up'),
                              subtitle:
                                  Text('Your next three days are clear.')))
                    else
                      ..._upcoming.map((e) {
                        final dt = DateTime.tryParse('${e['start_time']}');
                        return Card(
                            child: ListTile(
                                leading: const Icon(Icons.schedule),
                                title: Text('${e['title']}'),
                                subtitle: Text(dt == null
                                    ? ''
                                    : DateFormat('EEE · h:mm a')
                                        .format(dt.toLocal()))));
                      }),
                  ])));
  Widget _statCard(String title, String value, IconData icon,
          [double? progress]) =>
      Card(
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(icon,
                    size: 32, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Text(value,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(title),
                      if (progress != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: LinearProgressIndicator(value: progress))
                    ]))
              ])));
}
