/**
 * 服务端（主进程）版 SM-2 调度算法。
 * 与 renderer/scheduler.js 保持同一套规则：
 *   - 手机端上传复习事件后，服务端用本实现重算，避免两端漂移。
 *   - 注意：这是为同步服务单独维护的 Node 实现，修改时必须同步 renderer/scheduler.js。
 */
'use strict';

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

/**
 * 应用一次复习评分。
 * @param {object} word 词条对象（与 renderer 数据结构一致）
 * @param {number} rating 0~10 自评分
 * @param {number} [now] 评分发生的毫秒时间戳（默认当前时间）
 * @param {string} [eventId] 复习事件唯一 ID；传入后写入 history 用于去重
 */
function rateWord(word, rating, now, eventId) {
  const q = mapRatingToQuality(rating);
  const r = Math.max(0, Math.min(10, Math.round(Number(rating) || 0)));
  const base = Number(now) || Date.now();

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
    word.nextReview = base + delay;
  } else {
    word.reps += 1;
    // 前几次复习采用当天短间隔（2h → 4h → 8h），与 renderer/scheduler.js、手机端保持一致
    if (word.reps === 1) {
      word.interval = 0;
      word.nextReview = base + 2 * 60 * 60 * 1000;
    } else if (word.reps === 2) {
      word.interval = 0;
      word.nextReview = base + 4 * 60 * 60 * 1000;
    } else if (word.reps === 3) {
      word.interval = 0;
      word.nextReview = base + 8 * 60 * 60 * 1000;
    } else if (word.reps === 4) {
      word.interval = 1;
      word.nextReview = base + DAY_MS;
    } else if (word.reps === 5) {
      word.interval = 6;
      word.nextReview = base + 6 * DAY_MS;
    } else {
      word.interval = Math.max(1, Math.round(word.interval * word.ease));
      word.nextReview = base + word.interval * DAY_MS;
    }
    const efDelta = 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02);
    word.ease = Math.max(1.3, word.ease + efDelta);
  }

  word.lastRating = r;
  word.history.push({
    id: eventId || null,
    date: new Date(base).toISOString(),
    rating: r
  });

  const recentHigh = word.history.slice(-3).filter((h) => Number(h.rating) >= 8).length;
  if (recentHigh >= 3 && word.interval >= 21) {
    word.mastered = true;
  } else if (r <= 2) {
    word.mastered = false;
  }

  return word;
}

module.exports = {
  DAY_MS,
  MIN_MS,
  mapRatingToQuality,
  rateWord
};
