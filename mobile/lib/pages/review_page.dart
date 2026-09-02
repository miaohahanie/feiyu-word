import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/settings_repository.dart';
import '../data/word_repository.dart';
import '../models/word.dart';
import '../sync/sync_service.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  List<Word> _queue = [];
  Word? _current;
  bool _revealed = false;
  bool _loading = true;

  int _finished = 0;
  int _total = 0;
  int _todayCount = 0;
  Map<int, int> _ratingCounts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final repo = context.read<WordRepository>();
    final bookId = state.selectedBookId;
    if (bookId == null) {
      setState(() => _loading = false);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = await repo.getDueWords(bookId, now);
    final queue = due.take(20).toList();
    await _refreshToday();
    if (mounted) {
      setState(() {
        _queue = queue;
        _current = queue.isEmpty ? null : queue.first;
        _total = queue.length;
        _finished = 0;
        _loading = false;
      });
    }
  }

  Future<void> _refreshToday() async {
    final repo = context.read<WordRepository>();
    final count = await repo.countTodayEvents();
    final counts = await repo.ratingCountsToday();
    if (mounted) {
      setState(() {
        _todayCount = count;
        _ratingCounts = counts;
      });
    }
  }

  void _next() {
    setState(() {
      _finished += 1;
      _queue = _queue.skip(1).toList();
      _current = _queue.isEmpty ? null : _queue.first;
      _revealed = false;
    });
    _refreshToday();
  }

  Future<void> _rate(int rating) async {
    final state = context.read<AppState>();
    final settings = context.read<SettingsRepository>();
    final repo = context.read<WordRepository>();
    final word = _current;
    if (word == null || state.selectedBookId == null) return;
    final deviceId = await settings.getString('sync.deviceId') ?? '';

    final service = SyncService(
      pairing: state.pairing,
      repository: repo,
      settings: settings,
      deviceId: deviceId,
      bookId: state.selectedBookId!,
    );
    await service.review(word, rating);
    _next();
  }

  Future<void> _skip() async {
    final repo = context.read<WordRepository>();
    final word = _current;
    if (word == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    word.nextReview = now + 30 * 60 * 1000;
    word.updatedAt = now;
    await repo.updateWord(word);
    _next();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_total > 0 ? '复习（${_finished + (_queue.isNotEmpty ? 1 : 0)}/$_total）' : '复习'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _current == null
              ? _buildSummary()
              : _buildCard(),
    );
  }

  Widget _buildSummary() {
    return Center(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.celebration, size: 64, color: Colors.amber),
          const SizedBox(height: 12),
          const Text('今天的复习全部完成～', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Text('今日已复习 $_todayCount 词', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          for (final e in _ratingCounts.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${_ratingLabel(e.key)}：${e.value} 次',
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回首页'),
          ),
        ],
      ),
    );
  }

  String _ratingLabel(int rating) {
    if (rating <= 1) return '不认识（1）';
    if (rating <= 4) return '模糊（4）';
    return '认识（8）';
  }

  Widget _buildCard() {
    final word = _current!;
    final example = word.examples.isNotEmpty ? word.examples.first : null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(word.word,
                        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                    if (word.phonetic.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(word.phonetic, style: const TextStyle(fontSize: 18, color: Colors.grey)),
                    ],
                    if (example != null) ...[
                      const SizedBox(height: 12),
                      Text(example.text, textAlign: TextAlign.center),
                      if (example.translation.isNotEmpty)
                        Text(example.translation,
                            textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                    ],
                    const SizedBox(height: 24),
                    if (_revealed)
                      Text(word.meaning,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
                    else
                      FilledButton(
                        onPressed: () => setState(() => _revealed = true),
                        child: const Text('显示答案'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rate(1),
                  child: const Text('不认识'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rate(4),
                  child: const Text('模糊'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => _rate(8),
                  child: const Text('认识'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _skip,
            child: const Text('跳过（30 分钟后）'),
          ),
        ],
      ),
    );
  }
}
