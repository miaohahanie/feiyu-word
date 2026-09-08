import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/word_repository.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  int _days = 7;
  bool _loading = true;

  Map<String, int> _daily = {};
  Map<int, int> _ratings = {};
  Map<String, double> _rolling = {'sessions': 0, 'avgRounds': 0, 'words': 0};
  int _streak = 0;
  int _totalReviews = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<WordRepository>();
    final daily = await repo.dailyReviewCounts(_days);
    final ratings = await repo.ratingDistribution(_days);
    final rolling = await repo.rollingStats(_days);
    final streak = _computeStreak(daily: await repo.dailyReviewCounts(60));
    if (!mounted) return;
    setState(() {
      _daily = daily;
      _ratings = ratings;
      _rolling = rolling;
      _streak = streak;
      _totalReviews = daily.values.fold(0, (a, b) => a + b);
      _loading = false;
    });
  }

  int _computeStreak({required Map<String, int> daily}) {
    bool has(DateTime d) {
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return (daily[key] ?? 0) > 0;
    }

    var cursor = DateTime.now();
    // 今天还没复习不打断连续记录，从昨天起算
    if (!has(cursor)) cursor = cursor.subtract(const Duration(days: 1));
    var streak = 0;
    while (has(cursor)) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  String _ratingLabel(int rating) {
    if (rating <= 1) return '不认识';
    if (rating <= 4) return '模糊';
    return '认识';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学习报告')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('最近 7 天')),
                    ButtonSegment(value: 30, label: Text('最近 30 天')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (s) {
                    setState(() => _days = s.first);
                    _load();
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.local_fire_department,
                        color: Colors.deepOrange,
                        title: '连续打卡',
                        value: '$_streak 天',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.edit_note,
                        color: Colors.teal,
                        title: '复习次数',
                        value: '$_totalReviews 次',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('每日复习量', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 140,
                          child: CustomPaint(
                            size: const Size(double.infinity, 140),
                            painter: _BarsPainter(_barValues()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('评分分布', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _DistributionItem(
                              color: Colors.redAccent,
                              label: _ratingLabel(1),
                              count: _bucketCount((r) => r <= 1),
                            ),
                            _DistributionItem(
                              color: Colors.orange,
                              label: _ratingLabel(4),
                              count: _bucketCount((r) => r >= 2 && r <= 4),
                            ),
                            _DistributionItem(
                              color: Colors.green,
                              label: _ratingLabel(8),
                              count: _bucketCount((r) => r >= 5),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('滚动练习', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          _rolling['sessions']! < 1
                              ? '还没有滚动练习记录'
                              : '共 ${_rolling['sessions']!.round()} 次 · 平均 ${_rolling['avgRounds']!.toStringAsFixed(1)} 轮全部认识 · 巩固 ${_rolling['words']!.round()} 词次',
                          style: const TextStyle(fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '滚动练习只巩固记忆，不计入遗忘曲线',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  List<double> _barValues() {
    // 按时间正序（最旧在左），缺失的日期补 0
    final values = <double>[];
    final now = DateTime.now();
    for (var i = _days - 1; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      values.add((_daily[key] ?? 0).toDouble());
    }
    return values;
  }

  int _bucketCount(bool Function(int rating) test) {
    var n = 0;
    _ratings.forEach((rating, count) {
      if (test(rating)) n += count;
    });
    return n;
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;

  const _StatCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DistributionItem extends StatelessWidget {
  final Color color;
  final String label;
  final int count;

  const _DistributionItem({required this.color, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$count',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}

/// 简易柱状图：value[0] 最旧在左。
class _BarsPainter extends CustomPainter {
  final List<double> values;
  _BarsPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.fold(0.0, (a, b) => b > a ? b : a);
    final paint = Paint()..color = const Color(0xFF7C9A92);
    final slot = size.width / values.length;
    final barWidth = slot * 0.6;
    for (var i = 0; i < values.length; i++) {
      final h = maxV <= 0 ? 0.0 : values[i] / maxV * (size.height - 20);
      if (h <= 0) {
        // 当天没复习：画一个 2px 的基线标记
        canvas.drawRect(
          Rect.fromLTWH(i * slot + (slot - barWidth) / 2, size.height - 2, barWidth, 2),
          paint..color = const Color(0xFFCCCCCC),
        );
        paint.color = const Color(0xFF7C9A92);
        continue;
      }
      final rect = Rect.fromLTWH(
        i * slot + (slot - barWidth) / 2,
        size.height - h - 2,
        barWidth,
        h,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter oldDelegate) => oldDelegate.values != values;
}
