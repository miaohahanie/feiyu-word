import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/settings_repository.dart';
import '../notifications/notification_service.dart';
import '../notifications/reminder_scheduler.dart';
import '../sync/pairing_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8787');
  final _codeCtrl = TextEditingController();

  String _message = '';
  bool _remindersEnabled = true;
  bool _keepScreenOn = false;
  bool _spellingMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final settings = context.read<SettingsRepository>();
      final enabled = await settings.getBool('reminders.enabled') ?? true;
      final keepOn = await settings.getBool('review.keepScreenOn') ?? false;
      final spelling = await settings.getBool('review.spellingMode') ?? false;
      if (mounted) {
        setState(() {
          _remindersEnabled = enabled;
          _keepScreenOn = keepOn;
          _spellingMode = spelling;
        });
      }
    });
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleReminders(bool value) async {
    final settings = context.read<SettingsRepository>();
    if (value) {
      final ok = await NotificationService.requestPermission();
      if (!ok) {
        // 权限被拒也要落库，否则下次启动会按默认值再次请求并调度
        await settings.setBool('reminders.enabled', false);
        if (mounted) {
          setState(() => _remindersEnabled = false);
          setState(() => _message = '通知权限未授予，请在系统设置中开启');
        }
        return;
      }
      await settings.setBool('reminders.enabled', true);
      await ReminderScheduler.schedule();
    } else {
      await settings.setBool('reminders.enabled', false);
      await ReminderScheduler.cancel();
    }
    if (mounted) setState(() => _remindersEnabled = value);
  }

  Future<void> _pairManual() async {
    final pairing = context.read<PairingService>();
    final info = pairing.parseManual(_hostCtrl.text, _portCtrl.text, _codeCtrl.text);
    if (info == null) {
      setState(() => _message = '请填写正确的 IP、端口与 6 位配对码');
      return;
    }
    try {
      final result = await pairing.pairWith(info);
      if (mounted) {
        setState(() => _message = '配对成功：${result.deviceId.substring(0, 8)}…');
        context.read<AppState>().markPaired();
        await context.read<AppState>().refreshBooks();
      }
    } catch (e) {
      if (mounted) setState(() => _message = '配对失败：$e');
    }
  }

  Future<void> _unpair() async {
    final pairing = context.read<PairingService>();
    await pairing.unpair();
    if (mounted) {
      setState(() => _message = '已退出配对');
      context.read<AppState>().markUnpaired();
      await context.read<AppState>().refreshBooks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(state.paired ? '已配对' : '未配对',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(_message),
                  const SizedBox(height: 12),
                  if (!state.paired) ...[
                    TextField(
                      controller: _hostCtrl,
                      decoration: const InputDecoration(labelText: '电脑 IP（如 192.168.1.5）'),
                    ),
                    TextField(
                      controller: _portCtrl,
                      decoration: const InputDecoration(labelText: '端口（默认 8787）'),
                      keyboardType: TextInputType.number,
                    ),
                    TextField(
                      controller: _codeCtrl,
                      decoration: const InputDecoration(labelText: '6 位配对码'),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _pairManual,
                            child: const Text('手动配对'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await Navigator.pushNamed(context, '/qr');
                              if (mounted) setState(() {});
                            },
                            child: const Text('扫码配对'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const ListTile(
                      leading: Icon(Icons.link),
                      title: Text('已连接电脑同步服务'),
                      subtitle: Text('点击首页「同步」即可拉取/上传'),
                    ),
                    FilledButton(
                      onPressed: state.syncing ? null : () async {
                        await state.syncNow();
                        if (mounted) setState(() {});
                      },
                      child: Text(state.syncing ? '同步中…' : '立即同步'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _unpair,
                      child: const Text('解除配对'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _remindersEnabled,
                  onChanged: _toggleReminders,
                  title: const Text('开启复习提醒'),
                  subtitle: const Text('每天 08:00–22:00 每 2 小时提醒：8 / 10 / 12 / 14 / 16 / 18 / 20 / 22 点'),
                ),
                SwitchListTile(
                  value: _keepScreenOn,
                  onChanged: (v) async {
                    await context.read<SettingsRepository>().setBool('review.keepScreenOn', v);
                    if (mounted) setState(() => _keepScreenOn = v);
                  },
                  title: const Text('复习时保持屏幕常亮'),
                  subtitle: const Text('进入复习/滚动练习页期间屏幕不会自动熄灭'),
                ),
                SwitchListTile(
                  value: _spellingMode,
                  onChanged: (v) async {
                    await context.read<SettingsRepository>().setBool('review.spellingMode', v);
                    if (mounted) setState(() => _spellingMode = v);
                  },
                  title: const Text('拼写模式（听写）'),
                  subtitle: const Text('首轮复习先看释义拼单词：拼对自动记“认识”，拼错自动进入滚动练习'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: OutlinedButton(
                    onPressed: () async {
                      await NotificationService.requestPermission();
                      await NotificationService.showNow(
                        '单词桌宠',
                        '通知测试：看到这条消息说明通知已就绪',
                      );
                      if (mounted) setState(() => _message = '已发出测试通知');
                    },
                    child: const Text('立即测试通知'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.description),
              title: const Text('关于与许可'),
              onTap: () => Navigator.pushNamed(context, '/license'),
            ),
          ),
        ],
      ),
    );
  }
}
