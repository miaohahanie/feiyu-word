/**
 * 自适应记忆曲线（SM-2 风格，等效于需求文档中的 FSRS/SM-2 调度）
 *
 * 0~10 自评分映射到 SM-2 的 quality：
 *   0~1  -> q=1（完全不会）
 *   2~3  -> q=2（模糊）
 *   4~5  -> q=3（勉强）
 *   6~7  -> q=4（记得）
 *   8~10 -> q=5（轻松）
 *
 * q < 3 视为"遗忘"：重置复习次数，短时间内再次出现（10 分钟 / 4 小时）。
 * q >= 3 进入正常的 SM-2 间隔增长：1 天 -> 6 天 -> interval * ease。
 */
const DAY_MS = 24 * 60 * 60 * 1000;
const MIN_MS = 60 * 1000;

function mapRatingToQuality(rating) {
  const r = Math.max(0, Math.min(10, Math.round(Number(rating) || 0)));
  if (r <= 1) return 1;      // 完全不会
  if (r <= 3) return 2;      // 模糊
  if (r <= 5) return 3;      // 勉强
  if (r <= 7) return 4;      // 记得
  return 5;                  // 轻松
}

function newWordBase(nextReview) {
  return {
    reps: 0,
    ease: 2.5,
    interval: 0,
    lapses: 0,
    lastRating: null,
    nextReview: nextReview || Date.now(),
    history: []
  };
}

function rateWord(word, rating) {
  const q = mapRatingToQuality(rating);
  const r = Math.max(0, Math.min(10, Math.round(Number(rating) || 0)));

  // 默认值兜底
  if (typeof word.ease !== 'number' || word.ease < 1.3) word.ease = 2.5;
  if (typeof word.reps !== 'number') word.reps = 0;
  if (typeof word.interval !== 'number') word.interval = 0;
  if (typeof word.lapses !== 'number') word.lapses = 0;
  if (!Array.isArray(word.history)) word.history = [];

  if (q < 3) {
    // 遗忘：重置次数，短时间后再出现
    word.reps = 0;
    word.lapses += 1;
    word.interval = 0;
    const delay = r <= 1 ? 10 * MIN_MS : 4 * 60 * MIN_MS;
    word.nextReview = Date.now() + delay;
  } else {
    word.reps += 1;
    // 前几次复习采用当天短间隔（2h → 4h → 8h），提高 8:00~22:00 的复习密度；
    // 之后进入 1 天 → 6 天 → interval * ease 的长间隔阶段。
    if (word.reps === 1) {
      word.interval = 0;
      word.nextReview = Date.now() + 2 * 60 * 60 * 1000;
    } else if (word.reps === 2) {
      word.interval = 0;
      word.nextReview = Date.now() + 4 * 60 * 60 * 1000;
    } else if (word.reps === 3) {
      word.interval = 0;
      word.nextReview = Date.now() + 8 * 60 * 60 * 1000;
    } else if (word.reps === 4) {
      word.interval = 1;
      word.nextReview = Date.now() + DAY_MS;
    } else if (word.reps === 5) {
      word.interval = 6;
      word.nextReview = Date.now() + 6 * DAY_MS;
    } else {
      word.interval = Math.max(1, Math.round(word.interval * word.ease));
      word.nextReview = Date.now() + word.interval * DAY_MS;
    }
    // EF 更新：q=5 每次 +0.1，q=3 每次 -0.14，下限 1.3
    const efDelta = 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02);
    word.ease = Math.max(1.3, word.ease + efDelta);
  }

  word.lastRating = r;
  word.history.push({ date: new Date().toISOString(), rating: r });
  // history 截断到最近 200 条，防止长期使用后无限膨胀
  if (word.history.length > 200) word.history = word.history.slice(-200);

  // "已掌握"：连续 3 次自评 >= 8 且当前间隔 >= 21 天
  const recentHigh = word.history.slice(-3).filter((h) => h.rating >= 8).length;
  if (recentHigh >= 3 && word.interval >= 21) {
    word.mastered = true;
  } else if (r <= 2) {
    word.mastered = false;
  }

  return word;
}

function isDue(word, now) {
  return !word.nextReview || word.nextReview <= (now || Date.now());
}

function dueWords(words, now) {
  return words
    .filter((w) => !w.mastered && isDue(w, now))
    .sort((a, b) => (a.nextReview || 0) - (b.nextReview || 0));
}

function todayStr(d) {
  const date = d || new Date();
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function updateDailyStats(stats, key, patch) {
  if (!stats.days) stats.days = {};
  const day = todayStr();
  if (!stats.days[day]) stats.days[day] = { added: 0, reviewed: 0, ratings: [] };
  const d = stats.days[day];
  if (patch.added) d.added += patch.added;
  if (patch.reviewed) d.reviewed += patch.reviewed;
  if (patch.rating !== undefined) d.ratings.push(patch.rating);
  return stats;
}

function computeStreak(stats) {
  const days = stats && stats.days ? Object.keys(stats.days) : [];
  if (!days.length) return 0;
  const set = new Set(days);
  let streak = 0;
  const cursor = new Date();
  // 如果今天还没复习，从昨天开始算，不打断连续记录
  if (!set.has(todayStr(cursor))) cursor.setDate(cursor.getDate() - 1);
  while (set.has(todayStr(cursor))) {
    streak += 1;
    cursor.setDate(cursor.getDate() - 1);
  }
  return streak;
}

function computeTodayStats(stats) {
  const day = todayStr();
  const d = (stats && stats.days && stats.days[day]) || { added: 0, reviewed: 0, ratings: [] };
  const avg = d.ratings.length ? d.ratings.reduce((a, b) => a + b, 0) / d.ratings.length : null;
  return {
    added: d.added || 0,
    reviewed: d.reviewed || 0,
    avgRating: avg === null ? null : Math.round(avg * 10) / 10
  };
}

window.Scheduler = {
  DAY_MS,
  MIN_MS,
  mapRatingToQuality,
  newWordBase,
  rateWord,
  isDue,
  dueWords,
  todayStr,
  updateDailyStats,
  computeStreak,
  computeTodayStats
};
