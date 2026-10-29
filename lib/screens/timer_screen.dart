import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});
  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  int _seconds = 25 * 60, _initialSeconds = 25 * 60;
  String _type = 'focus';
  bool _running = false;
  Timer? _ticker;
  final _task = TextEditingController();
  final _custom = TextEditingController(text: '25');
  int _todaySessions = 0, _todayMinutes = 0;
  @override
  void dispose() {
    _ticker?.cancel();
    _task.dispose();
    _custom.dispose();
    super.dispose();
  }

  String get _clock =>
      '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';
  void _set(int mins, String type) {
    _ticker?.cancel();
    setState(() {
      _type = type;
      _seconds = _initialSeconds = mins * 60;
      _running = false;
    });
  }

  void _start() {
    if (_running || _seconds <= 0) return;
    setState(() => _running = true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (_seconds <= 1) {
        t.cancel();
        setState(() {
          _seconds = 0;
          _running = false;
        });
        await context.read<DatabaseService>().db?.insert('timer_sessions', {
          'duration': (_initialSeconds / 60).round(),
          'type': _type.contains('break') ? 'break' : _type,
          'task': _task.text.trim()
        });
        await _loadStats();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(_type == 'focus'
                  ? 'Focus session complete. Take a break!'
                  : 'Break complete.')));
      } else {
        setState(() => _seconds--);
      }
    });
  }

  Future<void> _loadStats() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final rows = await context.read<DatabaseService>().db?.rawQuery(
            "SELECT COUNT(*) AS sessions, "
            "COALESCE(SUM(CASE WHEN type = 'focus' THEN duration ELSE 0 END), 0) AS minutes "
            "FROM timer_sessions WHERE date(completed_at, 'localtime') = ?",
            [today]) ??
        [];
    if (mounted && rows.isNotEmpty)
      setState(() {
        _todaySessions = (rows.first['sessions'] as int?) ?? 0;
        _todayMinutes = (rows.first['minutes'] as int?) ?? 0;
      });
  }

  void _stop() {
    _ticker?.cancel();
    setState(() => _running = false);
  }

  void _reset() {
    _stop();
    setState(() => _seconds = _initialSeconds);
  }

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Focus Timer')),
        body: Center(
            child: SingleChildScrollView(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 650),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        SegmentedButton<String>(
                            segments: const [
                              ButtonSegment<String>(
                                  value: 'focus',
                                  label: Text('Focus · 25m'),
                                  icon: Icon(Icons.center_focus_strong)),
                              ButtonSegment<String>(
                                  value: 'short break',
                                  label: Text('Short break · 5m'),
                                  icon: Icon(Icons.coffee)),
                              ButtonSegment<String>(
                                  value: 'long break',
                                  label: Text('Long break · 15m'),
                                  icon: Icon(Icons.self_improvement))
                            ],
                            selected: {
                              _type
                            },
                            onSelectionChanged: (v) {
                              final x = v.first;
                              _set(
                                  x == 'focus'
                                      ? 25
                                      : x == 'short break'
                                          ? 5
                                          : 15,
                                  x);
                            }),
                        const SizedBox(height: 34),
                        Text(
                            'Today: $_todaySessions sessions · $_todayMinutes minutes focused',
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 12),
                        SizedBox(
                            width: 240,
                            height: 240,
                            child: Stack(fit: StackFit.expand, children: [
                              CircularProgressIndicator(
                                  value: _initialSeconds == 0
                                      ? 0
                                      : _seconds / _initialSeconds,
                                  strokeWidth: 12),
                              Center(
                                  child: Text(_clock,
                                      style: Theme.of(context)
                                          .textTheme
                                          .displayLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.w700)))
                            ])),
                        const SizedBox(height: 24),
                        TextField(
                            controller: _task,
                            decoration: const InputDecoration(
                                labelText: 'What are you working on?',
                                prefixIcon: Icon(Icons.edit_note),
                                border: OutlineInputBorder())),
                        const SizedBox(height: 16),
                        Wrap(spacing: 10, children: [
                          FilledButton.icon(
                              onPressed: _running ? null : _start,
                              icon: Icon(_running
                                  ? Icons.hourglass_top
                                  : Icons.play_arrow),
                              label: Text(_running ? 'Running' : 'Start')),
                          OutlinedButton.icon(
                              onPressed: _running ? _stop : null,
                              icon: const Icon(Icons.pause),
                              label: const Text('Pause')),
                          TextButton.icon(
                              onPressed: _reset,
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Reset'))
                        ]),
                        const SizedBox(height: 24),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Custom focus (minutes)'),
                          const SizedBox(width: 12),
                          SizedBox(
                              width: 76,
                              child: TextField(
                                  controller: _custom,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder()))),
                          IconButton(
                              tooltip: 'Set custom timer',
                              onPressed: () {
                                final n = int.tryParse(_custom.text);
                                if (n != null && n > 0 && n <= 240)
                                  _set(n, 'focus');
                              },
                              icon: const Icon(Icons.check))
                        ]),
                      ]),
                    )))),
      );
}
