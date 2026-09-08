import 'dart:math';

import '../models/word.dart';

/// 滚动练习会话：首轮复习后，把模糊/不认识的词反复重测，直到全部自评“认识”。
///
/// 只做内存中的队列调度：评分 >= 8（认识）的词离开队列，其余留到下一轮；
/// 每一轮开始时重新洗牌。滚动轮的评分不写入 SM-2、也不产生复习事件，
/// 只决定“是否继续滚动”，遗忘曲线只由首轮评分驱动。
class RollingSession {
  final Random _random;

  List<Word> _round;
  final List<Word> _nextRound = [];

  /// 当前是第几轮（从 1 开始）。
  int round = 1;

  /// 本轮开始时的词数。
  int roundTotal = 0;

  /// 本轮已作答的词数。
  int roundDone = 0;

  /// 进入滚动练习的总词数。
  final int totalWords;

  RollingSession(List<Word> forgottenWords, {Random? random})
      : _random = random ?? Random(),
        _round = List.of(forgottenWords),
        totalWords = forgottenWords.length {
    if (_round.isEmpty) {
      throw ArgumentError('滚动练习至少需要一个词');
    }
    _round.shuffle(_random);
    roundTotal = _round.length;
  }

  bool get finished => _round.isEmpty && _nextRound.isEmpty;

  Word? get current => _round.isEmpty ? null : _round.first;

  /// 还没通过“认识”的词数（含本轮剩余与下一轮）。
  int get remaining => _round.length + _nextRound.length;

  /// 提交一次自评：rating >= 8 视为认识并移出队列，否则留到下一轮。
  /// 返回练习是否全部结束。
  bool grade(int rating) {
    if (finished) return true;
    final word = _round.removeAt(0);
    roundDone += 1;
    if (rating < 8) _nextRound.add(word);

    if (_round.isEmpty && _nextRound.isNotEmpty) {
      _round = _nextRound.toList()..shuffle(_random);
      _nextRound.clear();
      round += 1;
      roundTotal = _round.length;
      roundDone = 0;
    }
    return finished;
  }

  /// 跳过当前词：视作本轮没答上来，下一轮再来。
  void skip() => grade(0);
}
