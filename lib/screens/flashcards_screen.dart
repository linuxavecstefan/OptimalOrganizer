import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/database_service.dart';
import '../widgets/database_unavailable.dart';

class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({super.key});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  List<Map<String, Object?>> _cards = [];
  List<Map<String, Object?>> _due = [];
  int _reviewIndex = 0;
  bool _showAnswer = false;
  bool _reviewing = false;
  bool _loading = true;
  String _categoryFilter = 'all';

  Future<void> _load() async {
    final db = context.read<DatabaseService>().db;
    if (db == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final cards =
        await db.query('flashcards', orderBy: 'next_review, created_at');
    final today = _date(DateTime.now());
    final filtered = _categoryFilter != 'all';
    final due = await db.query('flashcards',
        where: filtered
            ? 'next_review <= ? AND category = ?'
            : 'next_review <= ?',
        whereArgs: filtered ? [today, _categoryFilter] : [today],
        orderBy: 'next_review, id');
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _due = due;
      _loading = false;
      if (_reviewIndex >= due.length) _reviewIndex = 0;
      if (due.isEmpty) _reviewing = false;
    });
  }

  void _setFilter(String value) {
    if (value == _categoryFilter) return;
    setState(() => _categoryFilter = value);
    _load();
  }

  void _startStudy() {
    if (_due.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No cards are due right now.')));
      return;
    }
    setState(() {
      _reviewing = true;
      _reviewIndex = 0;
      _showAnswer = false;
    });
  }

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _edit([Map<String, Object?>? card]) async {
    final question = TextEditingController(text: '${card?['question'] ?? ''}');
    final answer = TextEditingController(text: '${card?['answer'] ?? ''}');
    String category = '${card?['category'] ?? 'general'}';
    final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
              builder: (ctx, refresh) => AlertDialog(
                title: Text(card == null ? 'New flashcard' : 'Edit flashcard'),
                content: SizedBox(
                  width: 480,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: question,
                        autofocus: true,
                        minLines: 2,
                        maxLines: 4,
                        decoration:
                            const InputDecoration(labelText: 'Question')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: answer,
                        minLines: 2,
                        maxLines: 5,
                        decoration:
                            const InputDecoration(labelText: 'Answer')),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                        value: category,
                        decoration:
                            const InputDecoration(labelText: 'Category'),
                        items: const [
                          DropdownMenuItem(
                              value: 'general', child: Text('General')),
                          DropdownMenuItem(value: 'work', child: Text('Work')),
                          DropdownMenuItem(
                              value: 'personal', child: Text('Personal')),
                          DropdownMenuItem(value: 'study', child: Text('Study')),
                        ],
                        onChanged: (v) => refresh(() => category = v ?? 'general')),
                  ]),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Save')),
                ],
              ),
            ));
    final q = question.text.trim();
    final a = answer.text.trim();
    question.dispose();
    answer.dispose();
    if (saved != true || q.isEmpty || a.isEmpty) return;
    final db = context.read<DatabaseService>().db!;
    if (card == null) {
      await db.insert(
          'flashcards', {'question': q, 'answer': a, 'category': category});
    } else {
      await db.update('flashcards', {'question': q, 'answer': a, 'category': category},
          where: 'id = ?', whereArgs: [card['id']]);
    }
    await _load();
  }

  Future<void> _review(int quality) async {
    if (_due.isEmpty) return;
    final card = _due[_reviewIndex];
    final repetitions = (card['repetitions'] as int?) ?? 0;
    final previousInterval = (card['interval'] as int?) ?? 0;
    final ease = (card['ease_factor'] as num?)?.toDouble() ?? 2.5;
    late int interval;
    late int nextRepetitions;
    late double nextEase;
    if (quality >= 3) {
      interval = repetitions == 0
          ? 1
          : repetitions == 1
              ? 6
              : (previousInterval * ease).toInt();
      nextEase = (ease + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)))
          .clamp(1.3, 10.0);
      nextRepetitions = repetitions + 1;
    } else {
      interval = 1;
      nextEase = ease;
      nextRepetitions = 0;
    }
    final next = DateTime.now().add(Duration(days: interval));
    await context.read<DatabaseService>().db!.update(
        'flashcards',
        {
          'ease_factor': nextEase,
          'interval': interval,
          'repetitions': nextRepetitions,
          'next_review': _date(next),
          'last_reviewed': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [card['id']]);
    if (!mounted) return;
    if (_reviewIndex + 1 >= _due.length) {
      setState(() {
        _reviewing = false;
        _showAnswer = false;
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Review session complete.')));
      }
    } else {
      setState(() {
        _reviewIndex++;
        _showAnswer = false;
      });
    }
  }

  Future<void> _delete(Map<String, Object?> card) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Delete flashcard?'),
              content: Text('"${card['question']}" will be removed.'),
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
          .delete('flashcards', where: 'id = ?', whereArgs: [card['id']]);
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
    final db = context.read<DatabaseService>().db;
    if (db == null) {
      return DatabaseUnavailable(onRetry: () async {
        await context.read<DatabaseService>().init();
        await _load();
      });
    }
    return Scaffold(
        appBar: AppBar(title: const Text('Flashcards'), actions: [
          PopupMenuButton<String>(
              onSelected: _setFilter,
              tooltip: 'Filter by category',
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'all', child: Text('All')),
                PopupMenuItem(value: 'work', child: Text('Work')),
                PopupMenuItem(value: 'personal', child: Text('Personal')),
                PopupMenuItem(value: 'study', child: Text('Study')),
              ],
            ),
          IconButton(
              onPressed: _load,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh)),
        ]),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Add card')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _reviewing && _due.isNotEmpty
                ? _reviewView()
                : Column(children: [
                    Card(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          const Icon(Icons.today_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text('${_due.length} cards due today')),
                          if (_due.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilledButton.tonalIcon(
                                  onPressed: _startStudy,
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Study')),
                            ),
                          PopupMenuButton<String>(
                              onSelected: _setFilter,
                              tooltip: 'Filter',
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'all', child: Text('All')),
                                PopupMenuItem(value: 'work', child: Text('Work')),
                                PopupMenuItem(value: 'personal', child: Text('Personal')),
                                PopupMenuItem(value: 'study', child: Text('Study')),
                              ],
                              child: const Icon(Icons.filter_list)),
                        ]),
                      ),
                    ),
                    Expanded(
                      child: _cards.isEmpty
                          ? const Center(
                              child: Text(
                                  'Add a question and answer to make your first card.'))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 92),
                              itemCount: _cards.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 6),
                              itemBuilder: (_, i) {
                                final card = _cards[i];
                                final due = '${card['next_review'] ?? ''}';
                                final isDue =
                                    due.compareTo(_date(DateTime.now())) <= 0;
                                return Card(
                                  child: ListTile(
                                    leading: Icon(isDue
                                        ? Icons.notifications_active_outlined
                                        : Icons.style_outlined),
                                    title: Text('${card['question']}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(isDue
                                        ? 'Due today'
                                        : 'Next review: $due'),
                                    onTap: () => _edit(card),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (v) => v == 'edit'
                                          ? _edit(card)
                                          : _delete(card),
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'edit', child: Text('Edit')),
                                        PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete')),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ]),
      );
  }

  Widget _reviewView() {
    final card = _due[_reviewIndex];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Card ${_reviewIndex + 1} of ${_due.length}',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 16),
            Card(
              child: InkWell(
                onTap: () => setState(() => _showAnswer = !_showAnswer),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 240),
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  alignment: Alignment.center,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_showAnswer ? 'ANSWER' : 'QUESTION',
                            style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(height: 20),
                        Text(
                            '${_showAnswer ? card['answer'] : card['question']}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 20),
                        Text(_showAnswer
                            ? 'Tap to see the question'
                            : 'Tap to reveal the answer'),
                      ]),
                ),
              ),
            ),
            if (_showAnswer) ...[
              const SizedBox(height: 24),
              const Text('How well did you remember?'),
              const SizedBox(height: 10),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final grade in const [
                      (0, 'Again'),
                      (2, 'Hard'),
                      (3, 'Okay'),
                      (4, 'Good'),
                      (5, 'Easy')
                    ])
                      FilledButton.tonal(
                          onPressed: () => _review(grade.$1),
                          child: Text(grade.$2)),
                  ]),
            ],
            const SizedBox(height: 16),
            TextButton(
                onPressed: () => setState(() => _reviewing = false),
                child: const Text('End study session')),
          ]),
        ),
      ),
    );
  }
}