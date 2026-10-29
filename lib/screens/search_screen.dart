import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  List<Map<String, Object?>> _results = [];
  bool _searched = false, _busy = false;
  static const _tables = {
    'notes': ['title', 'content'],
    'todos': ['title'],
    'habits': ['name', 'description'],
    'projects': ['name', 'description'],
    'tasks': ['title', 'description'],
    'events': ['title', 'description'],
    'captures': ['content'],
    'journal_entries': ['content']
  };
  Future<void> _search(String value) async {
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _searched = true;
    });
    final db = context.read<DatabaseService>().db;
    final found = <Map<String, Object?>>[];
    if (db != null)
      for (final entry in _tables.entries) {
        final where = entry.value.map((c) => '"$c" LIKE ?').join(' OR ');
        final rows = await db.query(entry.key,
            where: where,
            whereArgs: List.filled(entry.value.length, '%$q%'),
            limit: 50,
            orderBy: 'id DESC');
        for (final row in rows) {
          found.add({...row, '_table': entry.key});
        }
      }
    if (mounted)
      setState(() {
        _results = found;
        _busy = false;
      });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: _search,
                decoration: InputDecoration(
                    hintText: 'Search your organizer',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                        onPressed: () {
                          _query.clear();
                          _search('');
                        },
                        icon: const Icon(Icons.clear)),
                    border: const OutlineInputBorder()))),
        Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : !_searched
                    ? const Center(
                        child: Text(
                            'Search notes, tasks, projects, events, captures and journal entries.'))
                    : _results.isEmpty
                        ? const Center(child: Text('No matches found.'))
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (_, i) {
                              final row = _results[i];
                              final table = '${row['_table']}';
                              final text = row['title'] ??
                                  row['name'] ??
                                  row['content'] ??
                                  'Untitled';
                              final detail =
                                  row['description'] ?? row['content'] ?? '';
                              return ListTile(
                                  leading: const Icon(Icons.search),
                                  title: Text('$text'),
                                  subtitle: Text(
                                      '$table${detail.toString().isEmpty || detail == text ? '' : ' · $detail'}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis));
                            }))
      ]));
}
