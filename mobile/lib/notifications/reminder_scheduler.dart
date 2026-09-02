import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_service.dart';

/// 每天 08:00 - 22:00，每 2 小时一轮复习提醒。
class ReminderScheduler {
  static const List<int> slots = [8, 10, 12, 14, 16, 18, 20, 22];
  static const int _baseId = 1000;

  static Future<void> schedule() async {
    await NotificationService.init();
    final plugin = NotificationService.plugin;
    await plugin.cancelAll();
    for (final hour in slots) {
      await _scheduleAt(plugin, hour);
    }
  }

  static Future<void> cancel() async {
    await NotificationService.init();
    await NotificationService.plugin.cancelAll();
  }

  static Future<void> _scheduleAt(FlutterLocalNotificationsPlugin plugin, int hour) async {
    const title = '单词桌宠复习提醒';
    const body = '该复习啦～打开 App 看看今天有哪些单词到期';
    final when = _nextInstanceOfHour(hour);
    final id = _baseId + hour;

    try {
      await plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        NotificationService.details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      try {
        await plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          NotificationService.details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      } catch (__) {
        // 忽略单个时段调度失败，不影响其他时段
      }
    }
  }

  static tz.TZDateTime _nextInstanceOfHour(int hour) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
