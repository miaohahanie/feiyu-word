import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../data/settings_repository.dart';
import '../data/word_repository.dart';
import 'notification_service.dart';
import 'reminder_scheduler.dart';

/// WorkManager 后台入口：每轮提醒时动态计算“本轮有几个词到期”，
/// 并在固定通知的同 ID 上覆盖出动态内容；触发后自行续排下一天。
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    var hour = 0;
    try {
      final raw = inputData?['hour'];
      hour = raw is String ? (int.tryParse(raw) ?? 0) : 0;
    } catch (_) {}
    try {
      await NotificationService.init();
      final settings = SettingsRepository();
      final enabled = await settings.getBool('reminders.enabled') ?? true;
      var count = 0;
      if (enabled) {
        final bookId = await settings.getString('app.selectedBookId');
        if (bookId != null && bookId.isNotEmpty) {
          final repo = WordRepository();
          count = await repo.countDueWords(bookId, DateTime.now().millisecondsSinceEpoch);
        }
        // 0 个词到期时保持固定文案即可，不覆盖出“0 个词”的动态内容
        if (count > 0 && ReminderScheduler.slots.contains(hour)) {
          await NotificationService.showNow(
            '单词桌宠复习提醒',
            '本轮有 $count 个词到期，打开 App 复习一下吧',
            id: ReminderScheduler.notificationIdFor(hour),
          );
        }
      }
    } catch (_) {
      // 后台失败时保留固定提醒兜底
    }
    // 无论成败都续排下一天，否则动态内容只在安装当天生效
    if (ReminderScheduler.slots.contains(hour)) {
      try {
        await ReminderScheduler.scheduleSlotWork(hour);
      } catch (_) {}
    }
    return true;
  });
}
