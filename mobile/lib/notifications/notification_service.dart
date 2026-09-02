import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    // 先按中国大陆时区初始化；后续可换成读取设备时区
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));

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

  static Future<void> showNow(String title, String body) async {
    await init();
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  static FlutterLocalNotificationsPlugin get plugin => _plugin;
}
