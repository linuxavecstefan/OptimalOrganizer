import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/habits_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/journal_screen.dart';
import 'screens/timer_screen.dart';
import 'screens/capture_screen.dart';
import 'screens/todos_screen.dart';
import 'screens/flashcards_screen.dart';
import 'screens/mindmap_screen.dart';
import 'screens/gantt_screen.dart';
import 'screens/kanban_screen.dart';
import 'screens/search_screen.dart';
import 'screens/import_export_screen.dart';
import 'screens/reminders_screen.dart';
import 'services/theme_service.dart';
import 'services/database_service.dart';
import 'widgets/database_unavailable.dart';

class OptimalOrganizerApp extends StatelessWidget {
  const OptimalOrganizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Provider.of<ThemeService>(context);
    return MaterialApp(
      title: 'OptimalOrganizer',
      theme: ThemeData(
          colorSchemeSeed: const Color(0xff6750a4), useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xff80cbc4),
          brightness: Brightness.dark,
          useMaterial3: true),
      themeMode: theme.mode,
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final _screens = const [
    DashboardScreen(),
    HabitsScreen(),
    CalendarScreen(),
    ProjectsScreen(),
    NotesScreen(),
    JournalScreen(),
    TimerScreen(),
    CaptureScreen(),
    TodosScreen(),
    FlashcardsScreen(),
    MindmapScreen(),
    KanbanScreen(),
    GanttScreen(),
    RemindersScreen(),
    SearchScreen(),
    ImportExportScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final destinations = const [
      NavigationRailDestination(
          icon: Icon(Icons.dashboard), label: Text('Dashboard')),
      NavigationRailDestination(
          icon: Icon(Icons.check_circle), label: Text('Habits')),
      NavigationRailDestination(
          icon: Icon(Icons.calendar_today), label: Text('Calendar')),
      NavigationRailDestination(
          icon: Icon(Icons.folder), label: Text('Projects')),
      NavigationRailDestination(icon: Icon(Icons.note), label: Text('Notes')),
      NavigationRailDestination(icon: Icon(Icons.book), label: Text('Journal')),
      NavigationRailDestination(icon: Icon(Icons.timer), label: Text('Timer')),
      NavigationRailDestination(
          icon: Icon(Icons.add_box), label: Text('Capture')),
      NavigationRailDestination(
          icon: Icon(Icons.task_alt), label: Text('Todos')),
      NavigationRailDestination(
          icon: Icon(Icons.style), label: Text('Flashcards')),
      NavigationRailDestination(
          icon: Icon(Icons.account_tree), label: Text('Mindmap')),
      NavigationRailDestination(
          icon: Icon(Icons.view_kanban), label: Text('Kanban')),
      NavigationRailDestination(
          icon: Icon(Icons.timeline), label: Text('Gantt')),
      NavigationRailDestination(
          icon: Icon(Icons.alarm), label: Text('Reminders')),
      NavigationRailDestination(
          icon: Icon(Icons.search), label: Text('Search')),
      NavigationRailDestination(
          icon: Icon(Icons.import_export), label: Text('Sync')),
    ];
    final theme = context.read<ThemeService>();
    final database = context.watch<DatabaseService>();
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 700) {
        return Scaffold(
          body: _currentScreen(database),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index < 5 ? _index : 0,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final d in destinations.take(5))
                NavigationDestination(
                    icon: d.icon, label: (d.label as Text).data!)
            ],
            // The overflow menu exposes the less frequently used modules on phones.
          ),
          floatingActionButton: PopupMenuButton<int>(
              tooltip: 'More sections',
              icon: const Icon(Icons.apps),
              onSelected: (i) {
                if (i == -1) {
                  _showDisconnectDialog();
                  return;
                }
                setState(() => _index = i);
              },
              itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: -1,
                        child: Text('Disconnect')),
                    for (var i = 5; i < destinations.length; i++)
                      PopupMenuItem(
                          value: i,
                          child: Text((destinations[i].label as Text).data!)),
                  ]),
          floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
        );
      }
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            extended: constraints.maxWidth > 1100,
            destinations: destinations,
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
              child: Column(children: [
            Align(
                alignment: Alignment.centerRight,
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  IconButton(
                      tooltip: 'Reminders',
                      onPressed: () => setState(() => _index = 13),
                      icon: const Icon(Icons.alarm)),
                  IconButton(
                      tooltip: 'Search',
                      onPressed: () => setState(() => _index = 14),
                      icon: const Icon(Icons.search)),
                  IconButton(
                      tooltip: 'Toggle theme',
                      onPressed: theme.toggle,
                      icon: const Icon(Icons.brightness_6)),
                  IconButton(
                      tooltip: 'About',
                      onPressed: () => _showAboutDialog(context),
                      icon: const Icon(Icons.info_outline)),
                  const SizedBox(width: 8),
                ])),
            Expanded(child: _currentScreen(database)),
          ])),
        ]),
      );
    });
  }

  Widget _currentScreen(DatabaseService database) {
    final ready = database.db != null;
    // The Sync screen must stay reachable so a failed database can be fixed by
    // switching to another data folder.
    if (!ready && _index != 15) {
      return DatabaseUnavailable(
        message: database.initializationError,
        onRetry: () async {
          await database.init();
        },
      );
    }
    return KeyedSubtree(
      key: ValueKey('screen-$_index-$ready'),
      child: _screens[_index],
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About OptimalOrganizer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'OptimalOrganizer is an offline, ADHD-friendly personal organizer designed for high-performance living.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Version 1.0.0',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Copyright (c) 2026 Alex'),
              const SizedBox(height: 16),
              const Text(
                'License: MIT',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED OF THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect'),
        content: const Text(
            'This will reset the current data session. Are you sure you want to disconnect?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Disconnect')),
        ],
      ),
    ).then((value) async {
      if (value != true || !mounted) return;
      final db = context.read<DatabaseService>();
      try {
        await db.resetDataDirectory();
        if (!mounted) return;
        setState(() => _index = 0);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Disconnected. Reconnected to the default data folder.')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Disconnect failed: $e')));
      }
    });
  }
}