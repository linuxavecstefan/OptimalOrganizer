import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';

const _prompts = [
  "What's on your mind right now?",
  "What went well today?",
  "What could have gone better?",
  "What are you grateful for?",
  "What's one thing you want to accomplish tomorrow?",
  "How are you feeling right now?",
  "What's something you learned today?",
  "What's a win from today, no matter how small?"
];

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _content = TextEditingController();
  String _prompt = _prompts.first;
  int? _mood;
  List<Map<String, Object?>> _recent = [];
  Future<void> _load() async {
    final rows = await context
            .read<DatabaseService>()
            .db
            ?.query('journal_entries', orderBy: 'created_at DESC', limit: 10) ??
        [];
    if (mounted) setState(() => _recent = rows);
  }

  void _newPrompt() {
    final choices = _prompts.where((p) => p != _prompt).toList();
    setState(() => _prompt = choices[Random().nextInt(choices.length)]);
  }

  Future<void> _save() async {
    final text = _content.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Write a little before saving.')));
      return;
    }
    final db = context.read<DatabaseService>().db;
    if (db == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Database is not available; entry was not saved.')));
      return;
    }
    await db.insert(
        'journal_entries', {'content': text, 'prompt': _prompt, 'mood': _mood});
    if (!mounted) return;
    _content.clear();
    setState(() => _mood = null);
    await _load();
    if (!mounted) return;
    _newPrompt();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Journal entry saved.')));
  }

  Future<void> _viewPast() async {
    final entries = await context
            .read<DatabaseService>()
            .db
            ?.query('journal_entries', orderBy: 'created_at DESC', limit: 50) ??
        [];
    if (!mounted) return;
    showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Past journal entries'),
                content: SizedBox(
                    width: 600,
                    child: entries.isEmpty
                        ? const Center(child: Text('No entries yet.'))
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: entries.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (_, i) {
                              final e = entries[i];
                              final dt =
                                  DateTime.tryParse('${e['created_at']}');
                              final mood = e['mood'];
                              return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        [
                                          if (dt != null)
                                            DateFormat('MMM d, yyyy · h:mm a')
                                                .format(dt.toLocal()),
                                          if (mood != null) 'Mood $mood/10'
                                        ].join('  ·  '),
                                        style: Theme.of(ctx)
                                            .textTheme
                                            .labelMedium),
                                    if ((e['prompt'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 3),
                                          child: Text('${e['prompt']}',
                                              style: Theme.of(ctx)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                      fontStyle:
                                                          FontStyle.italic))),
                                    Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child:
                                            SelectableText('${e['content']}'))
                                  ]);
                            })),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'))
                ]));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Journal'), actions: [
        IconButton(
            tooltip: 'Past entries',
            onPressed: _viewPast,
            icon: const Icon(Icons.history))
      ]),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.lightbulb_outline),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text('A prompt for you',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge),
                                    const SizedBox(height: 4),
                                    Text(_prompt,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium)
                                  ])),
                              IconButton(
                                  tooltip: 'New prompt',
                                  onPressed: _newPrompt,
                                  icon: const Icon(Icons.shuffle))
                            ]))),
                const SizedBox(height: 12),
                TextField(
                    controller: _content,
                    minLines: 8,
                    maxLines: 18,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        hintText: 'Write whatever is on your mind…',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true)),
                const SizedBox(height: 14),
                Text('How are you feeling? (optional)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(spacing: 6, children: [
                  for (var score = 1; score <= 10; score++)
                    ChoiceChip(
                        label: Text('$score'),
                        selected: _mood == score,
                        onSelected: (_) => setState(
                            () => _mood = _mood == score ? null : score))
                ]),
                const SizedBox(height: 16),
                Wrap(spacing: 10, children: [
                  FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('Save entry')),
                  OutlinedButton.icon(
                      onPressed: _viewPast,
                      icon: const Icon(Icons.history),
                      label: const Text('View past entries'))
                ]),
                const SizedBox(height: 26),
                Text('Recent entries',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_recent.isEmpty)
                  const Text('Your saved entries will appear here.')
                else
                  ..._recent.take(5).map((e) {
                    final dt = DateTime.tryParse('${e['created_at']}');
                    return Card(
                        child: ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text('${e['content']}',
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text([
                        if (dt != null)
                          DateFormat('MMM d · h:mm a').format(dt.toLocal()),
                        if (e['mood'] != null) 'Mood ${e['mood']}/10',
                      ].join('  ·  ')),
                    ));
                  }),
              ]))));
}
