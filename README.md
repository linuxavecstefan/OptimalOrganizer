# OptimalOrganizer

OptimalOrganizer is an offline, ADHD-friendly personal organizer built with
Flutter and Dart. It keeps habits, todos, projects, notes, journal entries,
flashcards, mind maps, Kanban boards, Gantt charts, reminders and focus timers
in a single local SQLite database. No account and no network connection are
required.

## Features

- Dashboard with streaks, focus statistics and quick capture
- Habits with daily logging and DST-safe streak tracking
- Todos with due dates, priorities and archive
- Projects, notes and journal entries
- Flashcards with categories and study mode
- Mind maps with draggable nodes and connections
- Kanban boards and Gantt charts with recurring tasks
- Reminders that surface calendar events and due todos
- Focus timer with productivity history
- JSON/YAML/CSV/Markdown/OPML import and export, plus USB sync folders

## Linux build and launch

The release bundle is already built. Start the app with:

```sh
./OptimalOrganizer
```

To rebuild the Linux release (including the bundled SQLite runtime):

```sh
./build_linux.sh
```

The launcher writes its log to `~/.local/state/optimalorganizer/launcher.log`.

## Data

All data is stored locally. On first launch OptimalOrganizer creates an empty
database at:

```
~/.optimalorganizer/optimalorganizer.db
```

The Sync screen can switch to another data folder or export a portable backup.
