import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final _entry = TextEditingController();
  final _focus = FocusNode();
  List<Map<String, Object?>> _captures = [];
  bool _saving = false;
  Future<void> _load() async {
    final rows = await context
            .read<DatabaseService>()
            .db
            ?.query('captures', orderBy: 'created_at DESC', limit: 30) ??
        [];
    if (mounted) setState(() => _captures = rows);
  }

  Future<void> _save() async {
    final content = _entry.text.trim();
    if (content.isEmpty || _saving) return;
    final db = context.read<DatabaseService>().db;
    if (db == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Database is not available; nothing was captured.')));
      return;
    }
    setState(() => _saving = true);
    await db.insert('captures', {'content': content, 'category': 'inbox'});
    if (!mounted) return;
    _entry.clear();
    await _load();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Captured. You can sort it out later.')));
    _focus.requestFocus();
  }

  Future<void> _delete(Map<String, Object?> item) async {
    await context
        .read<DatabaseService>()
        .db
        ?.delete('captures', where: 'id = ?', whereArgs: [item['id']]);
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _entry.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Quick Capture')),
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            child: Text('Get it out of your head.',
                style: Theme.of(context).textTheme.headlineSmall)),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child:
                Text('Capture a thought now. Organize it when you’re ready.')),
        Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                  child: TextField(
                      controller: _entry,
                      focusNode: _focus,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _save(),
                      decoration: const InputDecoration(
                          hintText: 'A task, idea, reminder, anything…',
                          border: OutlineInputBorder()))),
              const SizedBox(width: 10),
              FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Capture'))
            ])),
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Recent captures',
                style: Theme.of(context).textTheme.titleMedium)),
        Expanded(
            child: _captures.isEmpty
                ? const Center(child: Text('Your captures will show up here.'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    itemCount: _captures.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (_, i) {
                      final item = _captures[i];
                      final dt = DateTime.tryParse('${item['created_at']}');
                      return Card(
                          child: ListTile(
                              leading: CircleAvatar(child: Text('${i + 1}')),
                              title: Text('${item['content']}'),
                              subtitle: Text(dt == null
                                  ? ''
                                  : DateFormat('MMM d · h:mm a')
                                      .format(dt.toLocal())),
                              trailing: IconButton(
                                  tooltip: 'Delete capture',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _delete(item))));
                    })),
      ]));
}
