import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_state.dart';
import '../data/settings_repository.dart';
import '../data/word_repository.dart';
import '../models/word.dart';
import '../review/rolling_session.dart';
import '../sync/sync_service.dart';

enum _Phase { loading, firstPass, rolling, done }

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key, this.rollingWords});

  /// 非空时跳过首轮复习，直接对这批词做滚动练习（首页“滚动练习”入口 / 易错词一键滚动）。
  final List<Word>? rollingWords;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  _Phase _phase = _Phase.loading;

  // 首轮复习（评分计入遗忘曲线）
  List<Word> _queue = [];
  Word? _current;
  bool _revealed = false;
  int _finished = 0;
  int _total = 0;

  // 首轮中模糊/不认识的词，进入滚动练习
  final List<Word> _forgotten = [];
  RollingSession? _rolling;
  bool _rollStoppedEarly = false;

  // 独立滚动模式的“无词可练”状态
  bool _standaloneEmpty = false;

  // 评分请求处理中：防止 async 期间连点按钮对同一词重复计分
  bool _submitting = false;

  int _todayCount = 0;
  Map<int, int> _ratingCounts = {};

  @override
  void initState() {
    super.initState();
    _load();
    _applyKeepScreenOn();
  }

  Future<void> _applyKeepScreenOn() async {
    try {
      final settings = context.read<SettingsRepository>();
      final keepOn = await settings.getBool('review.keepScreenOn') ?? false;
      if (keepOn) await WakelockPlus.enable();
    } catch (_) {
      /* 常亮失败不影响复习 */
    }
  }

  @override
  void dispose() {
    // 无论开关状态如何都尝试恢复（enable 只在开关打开时被调用过）
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final repo = context.read<WordRepository>();
    await _refreshToday();

    // 独立滚动模式：直接对传入的词滚动练习，不计遗忘曲线
    final preset = widget.rollingWords;
    if (preset != null) {
      if (!mounted) return;
      setState(() {
        if (preset.isEmpty) {
          _phase = _Phase.done;
          _standaloneEmpty = true;
        } else {
          _phase = _Phase.rolling;
          _rolling = RollingSession(List.of(preset));
        }
      });
      return;
    }

    final bookId = state.selectedBookId;
    if (bookId == null) {
      setState(() => _phase = _Phase.done);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = await repo.getDueWords(bookId, now);
    final queue = due.take(20).toList();
    if (mounted) {
      setState(() {
        _phase = _Phase.firstPass;
        _queue = queue;
        _current = queue.isEmpty ? null : queue.first;
        _total = queue.length;
        _finished = 0;
      });
    }
  }

  bool get _loading => _phase == _Phase.loading;

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

  void _advanceFirstPass() {
    setState(() {
      _finished += 1;
      _queue = _queue.skip(1).toList();
      _current = _queue.isEmpty ? null : _queue.first;
      _revealed = false;
    });
    if (_queue.isEmpty) {
      _startRolling();
    } else {
      _refreshToday();
    }
  }

  /// 首轮结束后：模糊/不认识的词进入滚动练习，直到全部“认识”。
  /// 滚动轮评分不写入 SM-2 / 复习事件，只决定是否继续滚动。
  void _startRolling() {
    if (_forgotten.isEmpty) {
      setState(() => _phase = _Phase.done);
      return;
    }
    setState(() {
      _phase = _Phase.rolling;
      _rolling = RollingSession(_forgotten);
      _revealed = false;
    });
  }

  Future<void> _rate(int rating) async {
    if (_submitting) return;
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
    // 评分只做内存运算，立即切卡；落库在后台完成（本地 SQLite，耗时毫秒级）
    final event = service.applyReviewLocally(word, rating);
    if (rating <= 4) _forgotten.add(word);
    _advanceFirstPass();
    service.persistReview(word, event).catchError((Object e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败（不影响本次复习）：$e')),
        );
      }
    });
  }

  Future<void> _skip() async {
    if (_submitting) return;
    final repo = context.read<WordRepository>();
    final word = _current;
    if (word == null) return;
    setState(() => _submitting = true);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      word.nextReview = now + 30 * 60 * 1000;
      word.updatedAt = now;
      await repo.updateWord(word);
      _advanceFirstPass();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _gradeRoll(int rating) {
    final session = _rolling;
    if (session == null) return;
    session.grade(rating);
    setState(() {
      _revealed = false;
      if (session.finished) _phase = _Phase.done;
    });
  }

  void _stopRollingEarly() {
    setState(() {
      _rollStoppedEarly = true;
      _phase = _Phase.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rolling = _rolling;
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_phase) {
          _Phase.rolling when rolling != null =>
            '滚动练习 第${rolling.round}轮（${rolling.roundDone}/${rolling.roundTotal}）',
          _Phase.firstPass when _total > 0 =>
            '复习（${_finished + (_queue.isNotEmpty ? 1 : 0)}/$_total）',
          _ => '复习',
        }),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : switch (_phase) {
              _Phase.rolling when rolling != null => _buildCard(rolling: true),
              _Phase.firstPass when _current != null => _buildCard(),
              _ => _buildSummary(),
            },
    );
  }

  Widget _buildSummary() {
    final rolling = _rolling;
    if (_standaloneEmpty) {
      return Center(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.sentiment_satisfied_alt, size: 64, color: Colors.teal),
            const SizedBox(height: 12),
            const Text(
              '今天没有需要巩固的词～',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '复习完如有模糊/不认识的词，会出现在这里',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
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
    return Center(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            rolling == null ? Icons.celebration : Icons.task_alt,
            size: 64,
            color: Colors.amber,
          ),
          const SizedBox(height: 12),
          Text(
            rolling == null
                ? '今天的复习全部完成～'
                : _rollStoppedEarly
                    ? '滚动练习已结束'
                    : '滚动练习完成，全部记住啦！',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          if (rolling != null) ...[
            Text(
              _rollStoppedEarly
                  ? '已手动结束，还有 ${rolling.remaining} 个词未通过'
                  : '${rolling.totalWords} 个模糊词经过 ${rolling.round} 轮全部认识',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              '滚动练习只巩固记忆，不计入遗忘曲线',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),
          ],
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

  Widget _buildCard({bool rolling = false}) {
    final word = rolling ? _rolling!.current! : _current!;
    final example = word.examples.isNotEmpty ? word.examples.first : null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (rolling) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '滚动练习 · 还剩 ${_rolling!.remaining} 个词未通过',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOut,
              transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
              child: Card(
                key: ValueKey('${rolling ? 'r' : 'f'}-${word.word}-$_finished'),
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
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting
                      ? null
                      : () => rolling
                          ? _gradeRoll(1)
                          : _rate(1),
                  child: const Text('不认识'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting
                      ? null
                      : () => rolling
                          ? _gradeRoll(4)
                          : _rate(4),
                  child: const Text('模糊'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting
                      ? null
                      : () => rolling
                          ? _gradeRoll(8)
                          : _rate(8),
                  child: const Text('认识'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _submitting
                ? null
                : () => rolling ? _gradeRoll(0) : _skip(),
            child: Text(rolling ? '跳过（下一轮再来）' : '跳过（30 分钟后）'),
          ),
          if (rolling) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: _stopRollingEarly,
              child: const Text('结束滚动练习', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ],
      ),
    );
  }
}
