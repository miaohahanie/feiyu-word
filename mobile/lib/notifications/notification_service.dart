import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // 测试通知固定 ID，重复点击互相覆盖而不是堆积
  static const int testNotificationId = 99;

  static Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    // 不写死时区名：调度统一用 UTC 定位 + 设备当前 UTC 偏移换算墙钟时间
    // （见 ReminderScheduler._nextInstanceOfHour），任何时区都能在本地整点触发。
    // 代价是 DST 切换当日可能有 1 小时偏差，对复习提醒可接受。
    tz.setLocalLocation(tz.UTC);

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      var granted = await android.requestNotificationsPermission();
      if (granted != true) return false;
      // Android 12+ 精确闹钟权限
      await android.requestExactAlarmsPermission();
      return true;
    }
    return true;
  }

  static NotificationDetails get details {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'review_reminder',
        '复习提醒',
        channelDescription: '每天 08:00 - 22:00 每 2 小时复习提醒',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
  }

  /// 展示一条通知。滚动/提醒类内容请传固定 id，让后到的内容覆盖先到的，
  /// 避免同一时段弹出两条通知。
  static Future<void> showNow(String title, String body, {int? id}) async {
    await init();
    await _plugin.show(
      id ?? testNotificationId,
      title,
      body,
      details,
    );
  }

  static FlutterLocalNotificationsPlugin get plugin => _plugin;
}
