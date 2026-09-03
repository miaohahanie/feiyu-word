import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'app_state.dart';
import 'data/app_database.dart';
import 'data/settings_repository.dart';
import 'data/word_repository.dart';
import 'notifications/notification_service.dart';
import 'notifications/reminder_scheduler.dart';
import 'sync/pairing_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.database;

  final settings = SettingsRepository();
  final repository = WordRepository();
  final pairing = PairingService(settings: settings, repository: repository);
  final state = AppState(repository: repository, settings: settings, pairing: pairing);
  await state.init();

  // 通知权限与每日复习提醒（默认开启，失败不影响 App 启动）
  try {
    await NotificationService.init();
    final remindersEnabled = await settings.getBool('reminders.enabled') ?? true;
    if (remindersEnabled) {
      final granted = await NotificationService.requestPermission();
      await settings.setBool('reminders.permissionGranted', granted);
      if (granted) {
        await ReminderScheduler.schedule();
      }
    }
  } catch (_) {
    /* 忽略通知初始化失败 */
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        Provider.value(value: settings),
        Provider.value(value: repository),
        Provider.value(value: pairing),
      ],
      child: const WordPetApp(),
    ),
  );
}
