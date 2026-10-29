import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/database_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  List<Map<String, Object?>> _events = [];
  bool _loading = true;
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  List<Map<String, Object?>> _onDay(DateTime day) => _events.where((e) {
        final dt = DateTime.tryParse('${e['start_time']}');
        return dt != null && _sameDay(dt, day);
      }).toList()
        ..sort((a, b) => '${a['start_time']}'.compareTo('${b['start_time']}'));

  Future<void> _load() async {
    final result = await context
            .read<DatabaseService>()
            .db
            ?.query('events', orderBy: 'start_time ASC') ??
        [];
    if (mounted)
      setState(() {
        _events = result;
        _loading = false;
      });
  }

  Future<void> _addEvent() async {
    final title = TextEditingController();
    final description = TextEditingController();
    var day = _selected;
    var time = const TimeOfDay(hour: 9, minute: 0);
    var allDay = false;
    final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                    title: const Text('Add event'),
                    content: SizedBox(
                        width: 440,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              TextField(
                                  controller: title,
                                  autofocus: true,
                                  decoration: const InputDecoration(
                                      labelText: 'Event title')),
                              TextField(
                                  controller: description,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                      labelText: 'Description (optional)')),
                              const SizedBox(height: 12),
                              Row(children: [
                                Expanded(
                                    child: OutlinedButton.icon(
                                        onPressed: () async {
                                          final d = await showDatePicker(
                                              context: ctx,
                                              initialDate: day,
                                              firstDate: DateTime(2000),
                                              lastDate: DateTime(2100));
                                          if (d != null) update(() => day = d);
                                        },
                                        icon: const Icon(Icons.calendar_today),
                                        label: Text(
                                            '${day.month}/${day.day}/${day.year}'))),
                                const SizedBox(width: 8),
                                if (!allDay)
                                  OutlinedButton.icon(
                                      onPressed: () async {
                                        final t = await showTimePicker(
                                            context: ctx, initialTime: time);
                                        if (t != null) update(() => time = t);
                                      },
                                      icon: const Icon(Icons.schedule),
                                      label: Text(time.format(ctx)))
                              ]),
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: allDay,
                                  onChanged: (v) =>
                                      update(() => allDay = v ?? false),
                                  title: const Text('All day')),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Save'))
                    ])));
    final name = title.text.trim();
    final desc = description.text.trim();
    title.dispose();
    description.dispose();
    if (saved != true || name.isEmpty) return;
    final start = DateTime(day.year, day.month, day.day, allDay ? 0 : time.hour,
        allDay ? 0 : time.minute);
    await context.read<DatabaseService>().db!.insert('events', {
      'title': name,
      'description': desc,
      'start_time': start.toIso8601String(),
      'end_time':
          allDay ? null : start.add(const Duration(hours: 1)).toIso8601String(),
      'all_day': allDay ? 1 : 0
    });
    await _load();
  }

  Future<void> _delete(Map<String, Object?> event) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Delete event?'),
                content: Text('Delete “${event['title']}”?'),
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
          .delete('events', where: 'id = ?', whereArgs: [event['id']]);
      await _load();
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final dayEvents = _onDay(_selected);
    return Scaffold(
        appBar: AppBar(title: const Text('Calendar & Events'), actions: [
          IconButton(
              tooltip: 'Today',
              onPressed: () => setState(() {
                    _focused = DateTime.now();
                    _selected = _focused;
                  }),
              icon: const Icon(Icons.today)),
          IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh))
        ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _addEvent,
            icon: const Icon(Icons.add),
            label: const Text('Add event')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(builder: (context, constraints) {
                final calendar = TableCalendar<Map<String, Object?>>(
                    firstDay: DateTime.utc(2000, 1, 1),
                    lastDay: DateTime.utc(2100, 12, 31),
                    focusedDay: _focused,
                    selectedDayPredicate: (d) => _sameDay(d, _selected),
                    eventLoader: _onDay,
                    startingDayOfWeek: StartingDayOfWeek.sunday,
                    calendarFormat: CalendarFormat.month,
                    onDaySelected: (selected, focused) => setState(() {
                          _selected = selected;
                          _focused = focused;
                        }),
                    onPageChanged: (focused) => _focused = focused,
                    calendarStyle: CalendarStyle(
                        markerDecoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle),
                        selectedDecoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle),
                        todayDecoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Theme.of(context).colorScheme.primary)),
                        todayTextStyle: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer)));
                final list = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Text(
                              'Events · ${MaterialLocalizations.of(context).formatMediumDate(_selected)}',
                              style: Theme.of(context).textTheme.titleMedium)),
                      Expanded(
                          child: dayEvents.isEmpty
                              ? const Center(
                                  child: Text('No events on this day.'))
                              : ListView.builder(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 0, 12, 88),
                                  itemCount: dayEvents.length,
                                  itemBuilder: (_, i) {
                                    final event = dayEvents[i];
                                    final dt = DateTime.tryParse(
                                        '${event['start_time']}');
                                    final allDay = event['all_day'] == 1;
                                    return Card(
                                        child: ListTile(
                                            leading: Icon(allDay
                                                ? Icons.event_available
                                                : Icons.schedule),
                                            title: Text('${event['title']}'),
                                            subtitle: Text(
                                                '${allDay ? 'All day' : (dt == null ? '' : TimeOfDay.fromDateTime(dt).format(context))}${('${event['description'] ?? ''}').isEmpty ? '' : ' · ${event['description']}'}'),
                                            trailing: IconButton(
                                                tooltip: 'Delete event',
                                                icon: const Icon(
                                                    Icons.delete_outline),
                                                onPressed: () =>
                                                    _delete(event))));
                                  }))
                    ]);
                if (constraints.maxWidth > 820)
                  return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: calendar),
                        const VerticalDivider(width: 1),
                        Expanded(flex: 2, child: list)
                      ]);
                return Column(children: [
                  calendar,
                  const Divider(height: 1),
                  Expanded(child: list)
                ]);
              }));
  }
}
