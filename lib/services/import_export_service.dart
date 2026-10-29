import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

class ImportExportService {
  static const tables = [
    'habits',
    'habit_log',
    'events',
    'captures',
    'projects',
    'tasks',
    'journal_entries',
    'timer_sessions',
    'notes',
    'mindmaps',
    'mindmap_nodes',
    'mindmap_connections',
    'attachments',
    'task_sessions',
    'flashcards',
    'reminders',
    'todos',
    'user_stats',
    'achievements',
    'user_achievements',
    'productivity_log',
  ];

  static const _restoreOrder = [
    'habits',
    'events',
    'captures',
    'projects',
    'notes',
    'mindmaps',
    'mindmap_nodes',
    'tasks',
    'journal_entries',
    'timer_sessions',
    'habit_log',
    'todos',
    'mindmap_connections',
    'attachments',
    'task_sessions',
    'flashcards',
    'reminders',
    'user_stats',
    'achievements',
    'user_achievements',
    'productivity_log',
  ];

  static const _columns = <String, Set<String>>{
    'habits': {
      'id',
      'name',
      'description',
      'color',
      'sort_order',
      'created_at'
    },
    'habit_log': {'id', 'habit_id', 'completed_date', 'completed_at', 'note'},
    'events': {
      'id',
      'title',
      'description',
      'start_time',
      'end_time',
      'all_day',
      'recurrence',
      'event_type',
      'color',
      'created_at'
    },
    'captures': {'id', 'content', 'category', 'created_at'},
    'projects': {'id', 'name', 'description', 'color', 'created_at'},
    'tasks': {
      'id',
      'project_id',
      'title',
      'description',
      'status',
      'priority',
      'due_date',
      'recurrence',
      'recurrence_end_date',
      'created_at'
    },
    'journal_entries': {
      'id',
      'content',
      'prompt',
      'mood',
      'tags',
      'created_at'
    },
    'timer_sessions': {'id', 'duration', 'type', 'task', 'completed_at'},
    'notes': {
      'id',
      'parent_id',
      'title',
      'content',
      'tags',
      'sort_order',
      'color',
      'is_code',
      'syntax',
      'gantt_project_id',
      'created_at',
      'updated_at'
    },
    'mindmaps': {'id', 'name', 'created_at'},
    'mindmap_nodes': {
      'id',
      'map_id',
      'title',
      'content',
      'x',
      'y',
      'color',
      'parent_id',
      'created_at'
    },
    'mindmap_connections': {
      'id',
      'from_node_id',
      'to_node_id',
      'label',
      'created_at'
    },
    'attachments': {
      'id',
      'note_id',
      'filename',
      'original_name',
      'mime_type',
      'size',
      'created_at'
    },
    'task_sessions': {'id', 'task_id', 'start_time', 'end_time'},
    'flashcards': {
      'id',
      'note_id',
      'question',
      'answer',
      'category',
      'ease_factor',
      'interval',
      'repetitions',
      'next_review',
      'last_reviewed',
      'created_at'
    },
    'reminders': {
      'id',
      'title',
      'note',
      'remind_at',
      'completed',
      'created_at'
    },
    'todos': {
      'id',
      'parent_id',
      'title',
      'due_date',
      'completed',
      'completed_at',
      'archived',
      'sort_order',
      'color',
      'created_at'
    },
    'user_stats': {
      'id',
      'total_points',
      'level',
      'habits_completed',
      'todos_completed',
      'streak_bonus',
      'updated_at'
    },
    'achievements': {
      'id',
      'name',
      'description',
      'icon',
      'points_required',
      'created_at'
    },
    'user_achievements': {'id', 'achievement_id', 'unlocked_at'},
    'productivity_log': {
      'id',
      'log_date',
      'habits_completed',
      'todos_completed',
      'points_earned',
      'focus_minutes'
    },
  };

  static dynamic _normalize(dynamic value) {
    if (value is YamlMap) {
      return value.map((key, value) => MapEntry('$key', _normalize(value)));
    }
    if (value is YamlList) return value.map(_normalize).toList();
    if (value is Map) {
      return value.map((key, value) => MapEntry('$key', _normalize(value)));
    }
    if (value is List) return value.map(_normalize).toList();
    if (value is DateTime) return value.toIso8601String();
    return value;
  }

  static Future<Map<String, dynamic>> exportAll(
      Database db, String dataDir) async {
    final data = <String, dynamic>{
      'format': 'OptimalOrganizer JSON',
      'version': 2,
      'exported_at': DateTime.now().toIso8601String(),
    };
    for (final table in tables) {
      final rows = await db.query(table);
      data[table] = rows.map((row) => _exportRow(table, row)).toList();
    }
    // Go and Python use the logical "journal" and "habit_logs" names.
    data['journal'] = data['journal_entries'];
    data['habit_logs'] = data['habit_log'];
    final sessions = data['timer_sessions'] as List<Map<String, dynamic>>;
    data['timer_stats'] = {
      'sessions': sessions.length,
      'total_minutes':
          sessions.fold<int>(0, (sum, row) => sum + _number(row['duration'])),
    };
    data['achievement_definitions'] = data['achievements'];
    final definitions = data['achievements'] as List<Map<String, dynamic>>;
    final unlocked = await db.query('user_achievements');
    final byId = {for (final row in definitions) row['id']: row};
    data['achievements'] = [
      for (final row in unlocked)
        if (byId[row['achievement_id']] != null)
          {
            ...byId[row['achievement_id']]!,
            'unlocked_at': row['unlocked_at'],
          }
    ];
    final files = <Map<String, String>>[];
    for (final raw in data['attachments'] as List) {
      final filename = p.basename('${raw['filename'] ?? ''}');
      if (filename.isEmpty || filename == '.') {
        throw const FormatException('An attachment has an invalid filename.');
      }
      final file = File(p.join(dataDir, 'attachments', filename));
      if (!await file.exists()) {
        throw FileSystemException('An attachment file is missing.', file.path);
      }
      files.add({
        'filename': filename,
        'data_base64': base64Encode(await file.readAsBytes())
      });
    }
    data['attachment_files'] = files;
    return data;
  }

  static Map<String, dynamic> _exportRow(
      String table, Map<String, Object?> row) {
    final result = Map<String, dynamic>.from(row);
    if (table == 'notes' || table == 'journal_entries') {
      result['tags'] = _decodeTags(row['tags']);
    }
    if (table == 'events') result['all_day'] = row['all_day'] == 1;
    if (table == 'todos') result['completed'] = row['completed'] == 1;
    return result;
  }

  static List<String> _decodeTags(Object? value) {
    try {
      final tags = jsonDecode('$value');
      if (tags is List) return tags.map((e) => '$e').toList();
    } catch (_) {}
    return value == null || '$value'.isEmpty ? [] : ['$value'];
  }

  static dynamic decodeBackup(String content, {required bool yaml}) {
    final clean = content.replaceFirst('\ufeff', '');
    return _normalize(yaml ? loadYaml(clean) : jsonDecode(clean));
  }

  static String encodeYaml(Object? value) {
    final out = StringBuffer();
    String scalar(Object? item) {
      if (item == null) return 'null';
      if (item is bool || item is num) return '$item';
      return jsonEncode('$item');
    }

    void write(Object? item, int indent) {
      final spaces = ' ' * indent;
      if (item is Map) {
        if (item.isEmpty) {
          out.writeln('${spaces}{}');
          return;
        }
        for (final entry in item.entries) {
          final key = '${entry.key}';
          final child = entry.value;
          if ((child is Map || child is List) && child.isNotEmpty) {
            out.writeln('$spaces$key:');
            write(child, indent + 2);
          } else if (child is Map) {
            out.writeln('$spaces$key: {}');
          } else if (child is List) {
            out.writeln('$spaces$key: []');
          } else {
            out.writeln('$spaces$key: ${scalar(child)}');
          }
        }
        return;
      }
      if (item is List) {
        if (item.isEmpty) {
          out.writeln('${spaces}[]');
          return;
        }
        for (final child in item) {
          if (child is Map || child is List) {
            out.writeln('${spaces}-');
            write(child, indent + 2);
          } else {
            out.writeln('$spaces- ${scalar(child)}');
          }
        }
        return;
      }
      out.writeln('$spaces${scalar(item)}');
    }

    write(value, 0);
    return out.toString();
  }

  static Future<int> restoreAll(
      Database db, String dataDir, dynamic decoded) async {
    if (decoded is! Map)
      throw const FormatException('Backup must contain an object.');
    final data = Map<String, dynamic>.from(decoded);
    for (final key in [
      'habits',
      'events',
      'captures',
      'projects',
      'notes',
      'mindmap_nodes',
      'tasks'
    ]) {
      if (!data.containsKey(key) || data[key] is! List) {
        throw FormatException('This backup is missing its $key section.');
      }
    }
    final attachmentBytes = <String, List<int>>{};
    for (final raw in (data['attachment_files'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final filename = '${raw['filename'] ?? ''}';
      if (filename.isEmpty || p.basename(filename) != filename) {
        throw FormatException('Invalid attachment filename: $filename');
      }
      attachmentBytes[filename] = base64Decode('${raw['data_base64'] ?? ''}');
    }
    final strictAttachmentFiles = data.containsKey('attachment_files');
    final validAttachmentNames = <String>{};
    for (final raw in (data['attachments'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final filename = '${raw['filename'] ?? ''}';
      if (filename.isNotEmpty && !attachmentBytes.containsKey(filename)) {
        if (p.basename(filename) != filename) {
          throw FormatException('Invalid attachment reference: $filename');
        }
        final existing =
            File(p.join(dataDir, 'attachments', p.basename(filename)));
        if (!await existing.exists()) {
          if (strictAttachmentFiles) {
            throw FormatException(
                'Backup is missing attachment file $filename.');
          }
          continue;
        }
        attachmentBytes[filename] = await existing.readAsBytes();
      }
      if (filename.isNotEmpty && attachmentBytes.containsKey(filename)) {
        validAttachmentNames.add(filename);
      }
    }

    final records = <String, List<Map<String, dynamic>>>{};
    final hasNamedMindmaps =
        data['mindmaps'] is List && (data['mindmaps'] as List).isNotEmpty;
    final logicalAchievementRows = (data['achievements'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    for (final table in tables) {
      var rawRows = data[table];
      if (table == 'journal_entries' && rawRows == null)
        rawRows = data['journal'];
      if (table == 'habit_log' && rawRows == null) rawRows = data['habit_logs'];
      if (table == 'achievements' && data['achievement_definitions'] is List) {
        rawRows = data['achievement_definitions'];
      }
      if (rawRows is List) {
        records[table] = rawRows.whereType<Map>().map((row) {
          final filtered = <String, dynamic>{};
          for (final key in _columns[table]!) {
            if (row.containsKey(key)) filtered[key] = row[key];
          }
          // Python and Go backups predate named maps; restore their nodes into
          // the preserved default map.
          if (table == 'mindmap_nodes' && !hasNamedMindmaps) {
            filtered['map_id'] = 1;
          }
          if ((table == 'notes' || table == 'journal_entries') &&
              filtered['tags'] is List) {
            filtered['tags'] = jsonEncode(filtered['tags']);
          }
          if (table == 'events' && filtered['all_day'] is bool) {
            filtered['all_day'] = filtered['all_day'] == true ? 1 : 0;
          }
          if (table == 'todos' && filtered['completed'] is bool) {
            filtered['completed'] = filtered['completed'] == true ? 1 : 0;
          }
          return filtered;
        }).toList();
      } else {
        records[table] = [];
      }
    }
    if (!hasNamedMindmaps) {
      records['mindmaps'] = [
        {'id': 1, 'name': 'Mind Map'}
      ];
    }
    records['attachments'] = records['attachments']!
        .where(
            (row) => validAttachmentNames.contains('${row['filename'] ?? ''}'))
        .toList();
    // Go and Python store unlocked achievements in the logical "achievements"
    // section, while this app keeps definitions and unlocks in separate tables.
    if (records['user_achievements']!.isEmpty &&
        (data['achievement_definitions'] == null) &&
        logicalAchievementRows.any(
            (a) => a.containsKey('unlocked_at') || a.containsKey('unlocked'))) {
      records['achievements'] = logicalAchievementRows.map((row) {
        final copy = Map<String, dynamic>.from(row)
          ..remove('unlocked_at')
          ..remove('unlocked');
        if (copy['description'] == null)
          copy['description'] = copy.remove('desc') ?? '';
        if (copy['points_required'] == null)
          copy['points_required'] = copy.remove('pts') ?? 0;
        if (_number(copy['id']) < 1) copy.remove('id');
        return {
          for (final key in _columns['achievements']!)
            if (copy.containsKey(key)) key: copy[key]
        };
      }).toList();
      records['user_achievements'] = [
        for (final row in logicalAchievementRows)
          if (row['id'] != null &&
              (row['unlocked_at'] != null || row['unlocked'] == true))
            {
              'achievement_id': row['id'],
              'unlocked_at':
                  row['unlocked_at'] ?? DateTime.now().toIso8601String()
            }
      ];
    }

    var count = 0;
    await db.transaction((txn) async {
      for (final table in _restoreOrder.reversed) {
        await txn.delete(table);
      }
      for (final table in _restoreOrder) {
        final rows = records[table]!
          ..sort((a, b) => _number(a['id']).compareTo(_number(b['id'])));
        for (final row in rows) {
          if (table == 'notes' &&
              row['parent_id'] != null &&
              !await _exists(txn, 'notes', row['parent_id']))
            row['parent_id'] = null;
          if (table == 'mindmap_nodes' &&
              row['parent_id'] != null &&
              !await _exists(txn, 'mindmap_nodes', row['parent_id']))
            row['parent_id'] = null;
          if (table == 'todos' &&
              row['parent_id'] != null &&
              !await _exists(txn, 'todos', row['parent_id']))
            row['parent_id'] = null;
          if (table == 'tasks' &&
              row['project_id'] != null &&
              !await _exists(txn, 'projects', row['project_id'])) continue;
          if (table == 'habit_log' &&
              !await _exists(txn, 'habits', row['habit_id'])) continue;
          if (table == 'attachments' &&
              !await _exists(txn, 'notes', row['note_id'])) continue;
          if (table == 'flashcards' &&
              row['note_id'] != null &&
              !await _exists(txn, 'notes', row['note_id']))
            row['note_id'] = null;
          if (table == 'task_sessions' &&
              !await _exists(txn, 'tasks', row['task_id'])) continue;
          await txn.insert(table, row,
              conflictAlgorithm: ConflictAlgorithm.abort);
          count++;
        }
      }
    });
    final attachmentDir = Directory(p.join(dataDir, 'attachments'));
    await attachmentDir.create(recursive: true);
    // Write the restored files first so a failure cannot leave the previous
    // attachments deleted with nothing to replace them.
    for (final entry in attachmentBytes.entries) {
      await File(p.join(attachmentDir.path, entry.key))
          .writeAsBytes(entry.value, flush: true);
    }
    for (final file in attachmentDir.listSync()) {
      if (file is File && !attachmentBytes.containsKey(p.basename(file.path))) {
        await file.delete();
      }
    }
    await writeNotesToDisk(db, dataDir);
    return count;
  }

  static int _number(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static Future<bool> _exists(Transaction txn, String table, Object? id) async {
    final rows = await txn.query(table,
        columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isNotEmpty;
  }

  static Future<String> exportNotesMarkdown(Database db) async {
    final notes = await db.query('notes', orderBy: 'sort_order, id');
    final out = StringBuffer();
    void write(Object? parent, int depth) {
      for (final note in notes.where((n) => n['parent_id'] == parent)) {
        out.writeln('${'#' * (depth + 1)} ${note['title']}\n');
        final body = '${note['content'] ?? ''}'.trim();
        if (body.isNotEmpty) out.writeln('$body\n');
        write(note['id'], depth + 1);
      }
    }

    write(null, 0);
    return out.toString();
  }

  static Future<String> exportNotesText(Database db) async {
    final notes = await db.query('notes', orderBy: 'sort_order, id');
    final out = StringBuffer();
    void write(Object? parent, int depth) {
      for (final note in notes.where((n) => n['parent_id'] == parent)) {
        final indent = '  ' * depth;
        final title = '${note['title']}';
        out.writeln('$indent$title\n$indent${'-' * title.length}\n');
        final body = '${note['content'] ?? ''}'.trim();
        if (body.isNotEmpty) out.writeln('$body\n');
        write(note['id'], depth + 1);
      }
    }

    write(null, 0);
    return out.toString();
  }

  static Future<int> importMarkdown(Database db, String text) async {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final stack = <int?>[null];
    var added = 0;
    var i = 0;
    while (i < lines.length) {
      final heading = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(lines[i]);
      if (heading == null) {
        i++;
        continue;
      }
      final level = heading.group(1)!.length;
      final title = heading.group(2)!.trim();
      while (stack.length > level) {
        stack.removeLast();
      }
      while (stack.length < level) {
        stack.add(null);
      }
      final parent = level > 1 ? stack[level - 1] : null;
      final siblings = await db.query('notes',
          columns: ['id'], where: 'parent_id IS ?', whereArgs: [parent]);
      final id = await db.insert('notes', {
        'title': title,
        'content': '',
        'tags': '[]',
        'parent_id': parent,
        'sort_order': siblings.length
      });
      stack.length = level;
      stack.add(id);
      added++;
      i++;
      final content = <String>[];
      while (i < lines.length && !RegExp(r'^#{1,6}\s').hasMatch(lines[i]))
        content.add(lines[i++]);
      final body = content.join('\n').trim();
      if (body.isNotEmpty)
        await db.update('notes', {'content': body},
            where: 'id = ?', whereArgs: [id]);
    }
    return added;
  }

  static Future<String> exportCsv(Database db, String table) async {
    final List<String> headers;
    final List<List<Object?>> rows;
    switch (table) {
      case 'habits':
        headers = ['name', 'description', 'color', 'created_at'];
        rows = (await db.query(table, orderBy: 'sort_order, id'))
            .map((r) => headers.map((h) => r[h]).toList())
            .toList();
      case 'events':
        headers = [
          'title',
          'description',
          'start_time',
          'end_time',
          'all_day',
          'recurrence',
          'event_type',
          'color'
        ];
        rows = (await db.query(table))
            .map((r) => headers.map((h) => r[h]).toList())
            .toList();
      case 'captures':
        headers = ['content', 'category', 'created_at'];
        rows = (await db.query(table, orderBy: 'created_at'))
            .map((r) => headers.map((h) => r[h]).toList())
            .toList();
      case 'tasks':
        headers = [
          'project',
          'title',
          'description',
          'status',
          'priority',
          'due_date',
          'recurrence',
          'recurrence_end_date'
        ];
        final records = await db.rawQuery(
            'SELECT p.name AS project, t.title, t.description, t.status, t.priority, t.due_date, t.recurrence, t.recurrence_end_date FROM tasks t LEFT JOIN projects p ON p.id=t.project_id ORDER BY t.created_at');
        rows = records.map((r) => headers.map((h) => r[h]).toList()).toList();
      default:
        throw FormatException('CSV is not supported for $table.');
    }
    return const ListToCsvConverter().convert([headers, ...rows]);
  }

  static Future<int> importCsv(Database db, String table, String text) async {
    final parsed =
        const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
            .convert(text);
    if (parsed.isEmpty) throw const FormatException('CSV file is empty.');
    final headers = parsed.first
        .map((e) => '$e'.replaceFirst('\ufeff', '').trim())
        .toList();
    final index = {for (var i = 0; i < headers.length; i++) headers[i]: i};
    String get(List<dynamic> row, String key) {
      final i = index[key];
      return i == null || i >= row.length ? '' : '${row[i]}'.trim();
    }

    var count = 0;
    await db.transaction((txn) async {
      for (var i = 1; i < parsed.length; i++) {
        final row = parsed[i];
        if (row.every((e) => '$e'.trim().isEmpty)) continue;
        switch (table) {
          case 'habits':
            final name = get(row, 'name');
            if (name.isEmpty)
              throw FormatException(
                  'CSV row ${i + 1}: habit name is required.');
            final exists = await txn.query('habits',
                columns: ['id'],
                where: 'name = ?',
                whereArgs: [name],
                limit: 1);
            if (exists.isEmpty)
              await txn.insert('habits', {
                'name': name,
                'description': get(row, 'description'),
                'color':
                    get(row, 'color').isEmpty ? '#00ff88' : get(row, 'color'),
                'sort_order': await _count(txn, 'habits')
              });
          case 'events':
            final start = get(row, 'start_time');
            if (DateTime.tryParse(start) == null)
              throw FormatException(
                  'CSV row ${i + 1}: start_time must be a date or timestamp.');
            await txn.insert('events', {
              'title': get(row, 'title').isEmpty ? 'Event' : get(row, 'title'),
              'description': get(row, 'description'),
              'start_time': start,
              'end_time':
                  get(row, 'end_time').isEmpty ? null : get(row, 'end_time'),
              'all_day': ['1', 'true', 'yes']
                      .contains(get(row, 'all_day').toLowerCase())
                  ? 1
                  : 0,
              'recurrence': get(row, 'recurrence').isEmpty
                  ? 'none'
                  : get(row, 'recurrence'),
              'event_type': get(row, 'event_type').isEmpty
                  ? 'general'
                  : get(row, 'event_type'),
              'color': get(row, 'color').isEmpty ? '#ff8800' : get(row, 'color')
            });
          case 'captures':
            final content = get(row, 'content');
            if (content.isEmpty)
              throw FormatException('CSV row ${i + 1}: content is required.');
            await txn.insert('captures', {
              'content': content,
              'category':
                  get(row, 'category').isEmpty ? 'inbox' : get(row, 'category'),
              'created_at': get(row, 'created_at').isEmpty
                  ? DateTime.now().toIso8601String()
                  : get(row, 'created_at')
            });
          case 'tasks':
            final title = get(row, 'title');
            final project = get(row, 'project');
            if (title.isEmpty || project.isEmpty)
              throw FormatException(
                  'CSV row ${i + 1}: title and project are required.');
            var projects = await txn.query('projects',
                columns: ['id'],
                where: 'name = ?',
                whereArgs: [project],
                limit: 1);
            final projectId = projects.isEmpty
                ? await txn.insert('projects', {'name': project})
                : projects.first['id'] as int;
            final priority = int.tryParse(
                get(row, 'priority').isEmpty ? '0' : get(row, 'priority'));
            if (priority == null)
              throw FormatException(
                  'CSV row ${i + 1}: priority must be a number.');
            final oldDone = get(row, 'done').toLowerCase() == 'true' ||
                get(row, 'done') == '1';
            await txn.insert('tasks', {
              'project_id': projectId,
              'title': title,
              'description': get(row, 'description'),
              'status': get(row, 'status').isEmpty
                  ? (oldDone ? 'done' : 'todo')
                  : get(row, 'status'),
              'priority': priority,
              'due_date':
                  get(row, 'due_date').isEmpty ? null : get(row, 'due_date'),
              'recurrence': get(row, 'recurrence').isEmpty
                  ? 'none'
                  : get(row, 'recurrence'),
              'recurrence_end_date': get(row, 'recurrence_end_date').isEmpty
                  ? null
                  : get(row, 'recurrence_end_date')
            });
          default:
            throw FormatException('CSV import is not supported for $table.');
        }
        count++;
      }
    });
    return count;
  }

  static Future<int> _count(Transaction txn, String table) async =>
      (await txn.rawQuery('SELECT COUNT(*) AS n FROM $table')).first['n']
          as int;

  static Future<String> exportOpml(Database db) async {
    final nodes = await db.query('mindmap_nodes', orderBy: 'id');
    final builder = XmlBuilder();
    builder.processing('xml', {'version': '1.0', 'encoding': 'UTF-8'});
    builder.element('opml', attributes: {'version': '2.0'}, nest: () {
      builder.element('head',
          nest: () => builder.element('title', nest: 'OptimalOrganizer Mind Map'));
      builder.element('body', nest: () {
        void write(Object? parent) {
          for (final node in nodes.where((n) => n['parent_id'] == parent)) {
            builder.element('outline',
                attributes: {
                  'text': '${node['title']}',
                  if ('${node['content'] ?? ''}'.isNotEmpty)
                    '_note': '${node['content']}'
                },
                nest: () => write(node['id']));
          }
        }

        write(null);
      });
    });
    return builder.buildDocument().toXmlString(pretty: true);
  }

  static Future<int> importOpml(Database db, String text) async {
    final document = XmlDocument.parse(text);
    final body = document.findAllElements('body').firstOrNull;
    if (body == null) throw const FormatException('OPML file has no body.');
    var count = 0;
    Future<void> write(XmlElement parent, int? parentId, int depth) async {
      final outlines = parent.children
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'outline');
      var position = 0;
      for (final node in outlines) {
        final title = node.getAttribute('text') ??
            node.getAttribute('title') ??
            'Untitled';
        final id = await db.insert('mindmap_nodes', {
          'title': title,
          'content': node.getAttribute('_note') ?? '',
          'parent_id': parentId,
          'x': depth * 240.0,
          'y': position * 110.0
        });
        count++;
        position++;
        await write(node, id, depth + 1);
      }
    }

    await write(body, null, 0);
    return count;
  }

  static Future<int> importOpmlAsNotes(Database db, String text) async {
    final document = XmlDocument.parse(text);
    final body = document.findAllElements('body').firstOrNull;
    if (body == null) throw const FormatException('OPML file has no body.');
    var count = 0;
    Future<void> write(XmlElement parent, int? parentId) async {
      final outlines = parent.children
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'outline');
      for (final node in outlines) {
        final title = node.getAttribute('text') ??
            node.getAttribute('title') ??
            'Untitled';
        final siblings = await db.query('notes',
            columns: ['id'], where: 'parent_id IS ?', whereArgs: [parentId]);
        final id = await db.insert('notes', {
          'title': title,
          'content': node.getAttribute('_note') ?? '',
          'tags': '[]',
          'parent_id': parentId,
          'sort_order': siblings.length,
        });
        count++;
        await write(node, id);
      }
    }

    await write(body, null);
    return count;
  }

  static Future<int> writeNotesToDisk(Database db, String dataDir) async {
    final dir = Directory(p.join(dataDir, 'notes'));
    await dir.create(recursive: true);
    final rows = await db.query('notes', orderBy: 'id');
    String notePath(Map<String, Object?> row) {
      final id = row['id'] as int;
      final slug = '${row['title']}'
          .replaceAll(RegExp(r'[^a-zA-Z0-9\- ]'), '')
          .trim()
          .replaceAll(' ', '-');
      final safeSlug = slug.isEmpty
          ? 'note'
          : slug.substring(0, slug.length > 60 ? 60 : slug.length);
      return p.join(dir.path, '${id.toString().padLeft(5, '0')}-$safeSlug.md');
    }

    final expectedPaths = rows.map(notePath).toSet();
    for (final entity in dir.listSync()) {
      if (entity is File &&
          RegExp(r'^\d+-.*\.md$').hasMatch(p.basename(entity.path))) {
        final match = RegExp(r'^(\d+)-').firstMatch(p.basename(entity.path));
        final id = match == null ? null : int.tryParse(match.group(1)!);
        if (id != null && !expectedPaths.contains(entity.path)) {
          await entity.delete();
        }
      }
    }
    for (final row in rows) {
      final id = row['id'] as int;
      final path = notePath(row);
      final tags = _decodeTags(row['tags']);
      final parent =
          row['parent_id'] == null ? '' : 'parent_id: ${row['parent_id']}\n';
      final content =
          '---\nid: $id\ntitle: ${row['title']}\ntags: ${jsonEncode(tags)}\ncolor: ${row['color'] ?? '#00d4ff'}\n$parent' +
              'created_at: ${row['created_at'] ?? DateTime.now().toIso8601String()}\nupdated_at: ${row['updated_at'] ?? DateTime.now().toIso8601String()}\n---\n\n${row['content'] ?? ''}';
      await File(path).writeAsString(content, flush: true);
    }
    return rows.length;
  }

  static Future<int> syncNotesFromDisk(Database db, String dataDir) async {
    final dir = Directory(p.join(dataDir, 'notes'));
    if (!await dir.exists()) return 0;
    var count = 0;
    for (final entity in dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))) {
      final content = await entity.readAsString();
      final match =
          RegExp(r'^---\s*\n([\s\S]*?)\n---\s*\n([\s\S]*)$', multiLine: true)
              .firstMatch(content);
      if (match == null) continue;
      final fields = <String, String>{};
      for (final line in match.group(1)!.split('\n')) {
        final split = line.indexOf(':');
        if (split > 0)
          fields[line.substring(0, split).trim()] =
              line.substring(split + 1).trim();
      }
      final id = int.tryParse(fields['id'] ?? '');
      final title =
          fields['title']?.replaceAll(RegExp(r'''^['"]|['"]$'''), '') ?? '';
      if (id == null || title.isEmpty) continue;
      Object? tags = '[]';
      try {
        tags = jsonEncode(jsonDecode(fields['tags'] ?? '[]'));
      } catch (_) {}
      final parent = int.tryParse(fields['parent_id'] ?? '');
      final values = {
        'title': title,
        'content': match.group(2)!.trim(),
        'tags': tags,
        'parent_id': parent,
        'color': fields['color'] ?? '#00d4ff'
      };
      final exists = await db.query('notes',
          columns: ['id'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (exists.isEmpty) {
        await db.insert('notes', {
          'id': id,
          ...values,
          'sort_order': 0,
          'created_at': fields['created_at'] ?? DateTime.now().toIso8601String()
        });
      } else {
        await db.update('notes', values, where: 'id = ?', whereArgs: [id]);
      }
      count++;
    }
    return count;
  }
}
