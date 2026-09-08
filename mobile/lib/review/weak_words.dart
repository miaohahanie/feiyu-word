import '../models/word.dart';

/// 易错词判定：lapses ≥ 2，或最近两次自评都 ≤ 4（模糊/不认识）。
/// 只依赖本地数据（lapses/history 由 SM-2 与服务端同步维护）。
bool isWeakWord(Word w) {
  if (w.lapses >= 2) return true;
  if (w.history.length >= 2) {
    final last2 = w.history.sublist(w.history.length - 2);
    if (last2.every((h) => h.rating <= 4)) return true;
  }
  return false;
}
