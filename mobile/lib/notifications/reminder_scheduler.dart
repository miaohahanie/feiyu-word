import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'notification_service.dart';

/// 每天 08:00 - 22:00，每 2 小时一轮复习提醒。
/// 固定本地通知确保时间到必提醒；WorkManager 任务晚 30 秒在同 ID 上覆盖出
/// “本轮 N 个词到期”的动态内容，并自行续排下一天，避免一天后动态内容失效。
class ReminderScheduler {
  static const List<int> slots = [8, 10, 12, 14, 16, 18, 20, 22];
  static const int _baseId = 1000;
  static const String _taskName = 'reminderCheck';

  /// 某时段通知的固定 ID：动态内容与固定提醒共用，后到者覆盖先到者
  static int notificationIdFor(int hour) => _baseId + hour;

  static Future<void> schedule() async {
    await NotificationService.init();
    final plugin = NotificationService.plugin;
    await plugin.cancelAll();
    try {
      await Workmanager().cancelAll();
    } catch (_) {
      /* ignore */
    }
    for (final hour in slots) {
      await _scheduleAt(plugin, hour);
      await _scheduleWork(hour);
    }
  }

  static Future<void> cancel() async {
    await NotificationService.init();
    await NotificationService.plugin.cancelAll();
    try {
      await Workmanager().cancelAll();
    } catch (_) {
      /* ignore */
    }
  }

  /// worker 触发后调用：续排该时段下一天的动态提醒
  static Future<void> scheduleSlotWork(int hour) => _scheduleWork(hour);

  static Future<void> _scheduleAt(FlutterLocalNotificationsPlugin plugin, int hour) async {
    const title = '单词桌宠复习提醒';
    const body = '该复习啦～打开 App 看看今天有哪些单词到期';
    final when = _nextInstanceOfHour(hour);
    final id = notificationIdFor(hour);

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

  static Future<void> _scheduleWork(int hour) async {
    try {
      final now = DateTime.now();
      var next = DateTime(now.year, now.month, now.day, hour);
      if (!next.isAfter(now)) {
        next = next.add(const Duration(days: 1));
      }
      // 比固定通知晚 30 秒触发：同 ID 覆盖出动态内容，不受两者触发顺序竞争影响
      final delay = next.difference(now) + const Duration(seconds: 30);
      final uniqueName = 'reminder-slot-$hour'; // 每个时段独立命名，注册时互不顶掉
      await Workmanager().cancelByUniqueName(uniqueName);
      await Workmanager().registerOneOffTask(
        uniqueName,
        _taskName,
        initialDelay: delay,
        inputData: {'hour': hour.toString()},
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    } catch (_) {
      // 后台任务失败不影响固定本地通知
    }
  }

  /// 设备所在时区的下一个整点（用 UTC 定位 + 当前偏移换算，见 NotificationService.init）
  static tz.TZDateTime _nextInstanceOfHour(int hour) {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, hour);
    if (!target.isAfter(now)) {
      target = target.add(const Duration(days: 1));
    }
    final instant = target.subtract(now.timeZoneOffset);
    return tz.TZDateTime(
      tz.UTC,
      instant.year,
      instant.month,
      instant.day,
      instant.hour,
      instant.minute,
    );
  }
}
