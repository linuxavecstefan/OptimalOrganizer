# Instructions for Artificial Intelligence Programmer

## Resume goal

Continue the OptimalOrganizer Flutter/Dart app using the Python app as the behavioral reference. The user reported that some features still do not work, but has not yet identified which ones. Start by asking what they tried and what happened, then reproduce and fix those issues. Do not assume the app is complete because it builds or analyzes cleanly.

## Project locations

- Flutter app: `/home/stef/Desktop/NewOptimalOrganizerOrganizer/optimalorganizer/`
- Python reference app: `/home/stef/Desktop/NewOptimalOrganizerOrganizer/optimalorganizer/`
- Python feature screens: `optimalorganizer/screens/` (dashboard, habits, calendar, timer, quick_capture, projects, journal)
- Python SQLite behavior: `optimalorganizer/database.py`

The Dart entry point is `lib/main.dart`. `lib/app.dart` contains the navigation shell. `lib/services/database_service.dart` initializes the SQLite database; `OPTIMALORGANIZER_DB_DIR` can select its location. The app has additional Dart modules beyond Python: notes, todos, flashcards, mind map, Kanban, Gantt, search, and backup/restore.

## Work already done

- Replaced the original “Coming soon” Dart screens with SQLite-backed screens.
- Added shared generic CRUD UI in `lib/screens/data_screen.dart` for several modules.
- Reworked the core Python-parity screens: dashboard, habit tracker, month calendar/events, quick capture, projects/task detail, journal prompts/history, and focus timer.
- Added phone-sized navigation and theme controls in `lib/app.dart`.
- Added search and JSON backup/restore.
- Created a top-level `OptimalOrganizer` shell launcher. It starts the release app from `build/linux/x64/release/bundle/`.
- `OptimalOrganizer.bin` is only a copied ELF binary. It is dynamically linked and does not work by itself because Flutter’s plugins and assets must remain in the bundle. Keep the whole bundle intact and launch through `OptimalOrganizer` or the existing desktop entry.

## Latest verification state

- `dart analyze lib` completed with no Dart source errors. It still reports style/lint infos, including some async-context warnings.
- `flutter build linux --release` succeeded after the recent screen changes.
- The app window has not been manually exercised in a graphical session. Running it from this shell only reached GTK and failed because the shell had no display; this did not verify the UI.
- The existing `test/widget_test.dart` is the default stale counter test and references `MyApp`, which does not exist. It was not run. Do not spend time treating that as an app feature failure; update or add tests only when the user asks to verify/test or when directly needed for a fix.

## Important next steps

1. Get the user’s concrete failure cases (screen, action, expected result, actual result, any visible error).
2. Reproduce against the real app and database before changing behavior. Test both a fresh database and, if relevant, a database created by the Python app.
3. Check Flutter runtime output and SQLite exceptions. The analyzer/build passing does not catch widget lifecycle, layout, plugin, SQL migration, or interaction problems.
4. Compare behavior directly with the corresponding Python screen and database methods before implementing a fix.
5. After a fix, run `dart format lib` and `HOME=/tmp dart analyze lib`. Rebuild with `flutter build linux --release` when the Linux app bundle needs updating. Re-copying the raw ELF to `OptimalOrganizer.bin` is not necessary for normal use; update the bundle, which the top-level launcher runs.

## Areas to inspect carefully

- `lib/screens/calendar_screen.dart`: month navigation, event markers, selected-day filtering, all-day events, and date/time conversion.
- `lib/screens/habits_screen.dart`: full-history streak calculation and same-day check-in toggling.
- `lib/screens/dashboard_screen.dart`: today counts and streaks; make sure “done today” is distinct from a streak that continued through yesterday.
- `lib/screens/projects_screen.dart`: project-to-task relation, task status changes, recurrence behavior, and due dates.
- `lib/screens/timer_screen.dart`: pause/resume/reset semantics and session persistence.
- `lib/screens/import_export_screen.dart`: import order and foreign-key constraints when restoring a backup.
- `lib/services/database_service.dart`: schema migration compatibility with the Python SQLite database.
- `lib/screens/data_screen.dart`: generic CRUD does not mean every advanced module has Python feature parity; mind map, Gantt, Kanban, notes, and flashcards need dedicated behavior if the user’s reported issue concerns them.

## Build/runtime details

Linux release bundle: `build/linux/x64/release/bundle/`.

Top-level launcher: `./OptimalOrganizer` (shell script). It resolves its own folder and execs the bundle binary. Keep it executable. The Desktop/application-menu `.desktop` entries may point directly at the bundle binary.

The Flutter tool may need write access to `/home/stef/flutter/bin/cache` for its cache lockfile. The project itself is under Desktop, outside the usual workspace write roots; request access to the Dart project folder if writes are blocked.
