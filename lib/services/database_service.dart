import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens the SQLite native library on Linux. Must be a top-level function so it
/// can be sent to the background isolate used by sqflite_common_ffi.
DynamicLibrary _openSqliteLinux() {
  final executableDirectory = p.dirname(Platform.resolvedExecutable);
  final candidates = <String>[
    p.join(executableDirectory, 'lib', 'libsqlite3.so'),
    p.join(executableDirectory, 'lib', 'libsqlite3.so.0'),
    '/usr/lib/x86_64-linux-gnu/libsqlite3.so.0',
    '/lib/x86_64-linux-gnu/libsqlite3.so.0',
    '/usr/lib64/libsqlite3.so.0',
    'libsqlite3.so.0',
    'libsqlite3.so',
    'libsqlite3.so.1',
  ];
  Object? lastError;
  for (final candidate in candidates) {
    try {
      return DynamicLibrary.open(candidate);
    } catch (e) {
      lastError = e;
    }
  }
  throw StateError(
      'Could not load libsqlite3 on Linux. Tried: ${candidates.join(', ')}. '
      'Last error: $lastError');
}

/// Applies the SQLite library override for the current platform. Also passed to
/// the sqflite isolate so it loads the same library.
void configureSqliteFfi() {
  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, _openSqliteLinux);
  }
}

class DatabaseService extends ChangeNotifier {
  Database? _db;
  String? _initializationError;
  String? _dataDir;

  Database? get db => _db;
  String? get initializationError => _initializationError;
  String? get dataDirectory => _dataDir;

  Future<void> init() async {
    _initializationError = null;
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      sqfliteFfiInit();
      configureSqliteFfi();
      try {
        databaseFactory =
            createDatabaseFactoryFfi(ffiInit: configureSqliteFfi);
      } catch (e) {
        // ignore
      }
    }

    try {
      final dir = await _getDataDir();
      _dataDir = dir;
      await Directory(dir).create(recursive: true);
      final dbPath = p.join(dir, 'optimalorganizer.db');

      _db = await openDatabase(
        dbPath,
        version: 1,
        onCreate: (db, version) async {
          await _createTables(db);
        },
        onOpen: (db) async {
          await db.execute('PRAGMA journal_mode=WAL');
          await db.execute('PRAGMA foreign_keys=ON');
        },
      );
      await _createTables(_db!);
    } catch (e) {
      _initializationError = e.toString();
      debugPrint('DB init error: $e');
      final failed = _db;
      _db = null;
      if (failed != null) {
        try {
          await failed.close();
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<String> _getDataDir() async {
    final env = Platform.environment['OPTIMALORGANIZER_DB_DIR'];
    if (env != null && env.isNotEmpty) return env;

    try {
      final prefs = await SharedPreferences.getInstance();
      final preferred = prefs.getString('optimalorganizer_data_dir');
      if (preferred != null && preferred.isNotEmpty) return preferred;
    } catch (_) {}

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final homeDir = p.join(home, '.optimalorganizer');
    if (await Directory(homeDir).exists()) {
      final dbf = File(p.join(homeDir, 'optimalorganizer.db'));
      if (await dbf.exists()) return homeDir;
    }
    try {
      final exe = Platform.resolvedExecutable;
      final appDir = p.dirname(exe);
      if (await File(p.join(appDir, 'optimalorganizer.db')).exists() ||
          await Directory(p.join(appDir, 'notes')).exists()) {
        return appDir;
      }
      // Also look near bundle
      final bundleDir = p.dirname(p.dirname(appDir));
      for (final candidate in [p.join(bundleDir, 'data'), p.join(bundleDir, '..', 'data')]) {
        if (await File(p.join(candidate, 'optimalorganizer.db')).exists()) return candidate;
      }
    } catch (_) {}

    await Directory(homeDir).create(recursive: true);
    return homeDir;
  }

  Future<void> useDataDirectory(String path) async {
    if (path.trim().isEmpty) {
      await resetDataDirectory();
      return;
    }
    final selected = p.normalize(p.absolute(path));
    final databaseFile = File(p.join(selected, 'optimalorganizer.db'));
    if (!await databaseFile.exists()) {
      throw FileSystemException(
          'Select a folder that directly contains optimalorganizer.db', selected);
    }
    final header = await databaseFile
        .openRead(0, 16)
        .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    if (String.fromCharCodes(header) != 'SQLite format 3\u0000') {
      throw FileSystemException(
          'The selected file is not a readable SQLite database.',
          databaseFile.path);
    }
    // Probe-open the selected database before disturbing the live connection,
    // so a bad file cannot leave the app disconnected.
    Database? probe;
    try {
      probe = await openDatabase(databaseFile.path, readOnly: true);
      await probe.close();
      probe = null;
    } catch (e) {
      if (probe != null) {
        try {
          await probe.close();
        } catch (_) {}
      }
      throw FileSystemException(
          'Could not open the selected database: $e', databaseFile.path);
    }
    final handle = _db;
    _db = null;
    if (handle != null) await handle.close();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('optimalorganizer_data_dir', selected);
    _dataDir = selected;
    await init();
    if (_db == null) {
      throw StateError(
          _initializationError ?? 'Could not open the selected database.');
    }
  }

  /// Returns to the default data folder and reconnects, discarding the
  /// remembered custom location.
  Future<void> resetDataDirectory() async {
    final handle = _db;
    _db = null;
    if (handle != null) await handle.close();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('optimalorganizer_data_dir');
    } catch (_) {}
    _dataDir = null;
    await init();
  }

  Future<void> deleteAllOrganizerData() async {
    final dir = _dataDir ?? await _getDataDir();
    final handle = _db;
    _db = null;
    if (handle != null) await handle.close();
    for (final name in [
      'optimalorganizer.db',
      'optimalorganizer.db-wal',
      'optimalorganizer.db-shm'
    ]) {
      final file = File(p.join(dir, name));
      if (await file.exists()) await file.delete();
    }
    for (final name in ['notes', 'attachments']) {
      final managed = Directory(p.join(dir, name));
      if (await managed.exists()) await managed.delete(recursive: true);
    }
    await init();
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS habits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        description TEXT DEFAULT '',
        color TEXT DEFAULT '#00ff88',
        sort_order INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS habit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        habit_id INTEGER NOT NULL,
        completed_date TEXT NOT NULL,
        completed_at TEXT NOT NULL DEFAULT (datetime('now')),
        note TEXT DEFAULT '',
        FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE,
        UNIQUE(habit_id, completed_date)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT DEFAULT '',
        start_time TEXT NOT NULL,
        end_time TEXT,
        all_day INTEGER DEFAULT 0,
        recurrence TEXT DEFAULT 'none',
        event_type TEXT DEFAULT 'general',
        color TEXT DEFAULT '#ff8800',
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS captures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        category TEXT DEFAULT 'inbox',
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        color TEXT DEFAULT '#8888ff',
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        project_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT DEFAULT '',
        status TEXT DEFAULT 'todo',
        priority INTEGER DEFAULT 0,
        due_date TEXT,
        recurrence TEXT DEFAULT 'none',
        recurrence_end_date TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS journal_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        prompt TEXT DEFAULT '',
        mood INTEGER,
        tags TEXT DEFAULT '[]',
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS timer_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        duration INTEGER NOT NULL,
        type TEXT DEFAULT 'focus',
        task TEXT DEFAULT '',
        completed_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER,
        title TEXT NOT NULL,
        content TEXT DEFAULT '',
        tags TEXT DEFAULT '[]',
        sort_order INTEGER DEFAULT 0,
        color TEXT DEFAULT '#00d4ff',
        is_code INTEGER DEFAULT 0,
        syntax TEXT DEFAULT '',
        gantt_project_id INTEGER,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (parent_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS mindmap_nodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        map_id INTEGER NOT NULL DEFAULT 1,
        title TEXT NOT NULL,
        content TEXT DEFAULT '',
        x REAL DEFAULT 0,
        y REAL DEFAULT 0,
        color TEXT DEFAULT '#00d4ff',
        parent_id INTEGER,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS mindmaps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        note TEXT DEFAULT '',
        remind_at TEXT NOT NULL,
        completed INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS mindmap_connections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        from_node_id INTEGER NOT NULL,
        to_node_id INTEGER NOT NULL,
        label TEXT DEFAULT '',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (from_node_id) REFERENCES mindmap_nodes(id) ON DELETE CASCADE,
        FOREIGN KEY (to_node_id) REFERENCES mindmap_nodes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id INTEGER NOT NULL,
        filename TEXT NOT NULL,
        original_name TEXT NOT NULL,
        mime_type TEXT DEFAULT '',
        size INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        start_time TEXT NOT NULL DEFAULT (datetime('now')),
        end_time TEXT,
        FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS flashcards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        note_id INTEGER,
        question TEXT NOT NULL,
        answer TEXT NOT NULL,
        category TEXT DEFAULT 'general',
        ease_factor REAL DEFAULT 2.5,
        interval INTEGER DEFAULT 0,
        repetitions INTEGER DEFAULT 0,
        next_review TEXT NOT NULL DEFAULT (date('now')),
        last_reviewed TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS todos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_id INTEGER,
        title TEXT NOT NULL,
        due_date TEXT,
        completed INTEGER DEFAULT 0,
        completed_at TEXT,
        archived INTEGER DEFAULT 0,
        sort_order INTEGER DEFAULT 0,
        color TEXT DEFAULT '#00d4ff',
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (parent_id) REFERENCES todos(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_stats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        total_points INTEGER DEFAULT 0,
        level INTEGER DEFAULT 1,
        habits_completed INTEGER DEFAULT 0,
        todos_completed INTEGER DEFAULT 0,
        streak_bonus INTEGER DEFAULT 0,
        updated_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS achievements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT DEFAULT '',
        icon TEXT DEFAULT '🏆',
        points_required INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_achievements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        achievement_id INTEGER NOT NULL,
        unlocked_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (achievement_id) REFERENCES achievements(id) ON DELETE CASCADE,
        UNIQUE(achievement_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS productivity_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        log_date TEXT NOT NULL UNIQUE,
        habits_completed INTEGER DEFAULT 0,
        todos_completed INTEGER DEFAULT 0,
        points_earned INTEGER DEFAULT 0,
        focus_minutes INTEGER DEFAULT 0
      )
    ''');
    final alters = [
      'ALTER TABLE habits ADD COLUMN sort_order INTEGER DEFAULT 0',
      'ALTER TABLE notes ADD COLUMN sort_order INTEGER DEFAULT 0',
      'ALTER TABLE notes ADD COLUMN gantt_project_id INTEGER DEFAULT NULL',
      'ALTER TABLE notes ADD COLUMN color TEXT DEFAULT "#00d4ff"',
      'ALTER TABLE tasks ADD COLUMN recurrence TEXT DEFAULT "none"',
      'ALTER TABLE tasks ADD COLUMN recurrence_end_date TEXT DEFAULT NULL',
      'ALTER TABLE todos ADD COLUMN parent_id INTEGER DEFAULT NULL',
      'ALTER TABLE todos ADD COLUMN completed_at TEXT DEFAULT NULL',
      'ALTER TABLE todos ADD COLUMN color TEXT DEFAULT "#00d4ff"',
      'ALTER TABLE todos ADD COLUMN archived INTEGER DEFAULT 0',
      'ALTER TABLE mindmap_nodes ADD COLUMN map_id INTEGER DEFAULT 1',
      'ALTER TABLE flashcards ADD COLUMN category TEXT DEFAULT "general"',
    ];
    for (final a in alters) {
      try {
        await db.execute(a);
      } catch (_) {}
    }
    // Older databases had one implicit mind map. Give those nodes a named
    // container so upgrades preserve the existing canvas as the first map.
    // A brand-new database stays completely empty until the user creates a map.
    final legacy = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM mindmap_nodes');
    final legacyNodes = (legacy.first['c'] as int?) ?? 0;
    if ((legacyNodes ?? 0) > 0) {
      await db.execute(
          "INSERT OR IGNORE INTO mindmaps (id, name) VALUES (1, 'Mind Map')");
      await db
          .execute('UPDATE mindmap_nodes SET map_id = 1 WHERE map_id IS NULL');
    }
  }
}
