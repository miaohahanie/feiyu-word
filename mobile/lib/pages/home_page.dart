import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/word_repository.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _dueCount = 0;
  int _reviewedToday = 0;

  @override
  void initState() {
    super.initState();
    _loadDue();
  }

  Future<void> _loadDue() async {
    final state = context.read<AppState>();
    final repo = context.read<WordRepository>();
    final count = await state.dueCount();
    final reviewed = await repo.countTodayEvents();
    if (mounted) {
      setState(() {
        _dueCount = count;
        _reviewedToday = reviewed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('单词桌宠')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '今日到期：$_dueCount 词',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text('今日已复习：$_reviewedToday 词'),
                  const SizedBox(height: 8),
                  Text('当前词本：${_selectedBookName(state)}'),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(labelText: '选择词本'),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: state.selectedBookId,
                        isExpanded: true,
                        items: state.books
                            .map((b) => DropdownMenuItem(value: b.id, child: Text('${b.name}（${b.count}）')))
                            .toList(),
                        onChanged: (v) async {
                          if (v != null) await state.selectBook(v);
                          _loadDue();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.sync),
              title: Text(state.syncing ? '同步中…' : '同步'),
              subtitle: Text(state.lastMessage.isEmpty ? '与电脑端同步词库与复习进度' : state.lastMessage),
              onTap: () async {
                if (state.syncing) return; // 同步进行中忽略重复点击
                await state.syncNow();
                _loadDue();
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('单词本'),
              subtitle: const Text('查看 / 搜索 / 编辑 / 删除当前词本单词'),
              onTap: () async {
                await Navigator.pushNamed(context, '/words');
                _loadDue();
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.add),
              title: const Text('添加单词'),
              subtitle: const Text('手动添加或在线查词后加入词本'),
              onTap: () async {
                await Navigator.pushNamed(context, '/add');
                _loadDue();
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.school),
              title: const Text('开始复习'),
              subtitle: Text('$_dueCount 个到期词'),
              enabled: _dueCount > 0,
              onTap: _dueCount > 0
                  ? () async {
                      await Navigator.pushNamed(context, '/review');
                      _loadDue();
                    }
                  : null,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('设置'),
              onTap: () async {
                await Navigator.pushNamed(context, '/settings');
                _loadDue();
              },
            ),
          ),
        ],
      ),
    );
  }

  String _selectedBookName(AppState state) {
    if (state.selectedBookId == null) return '未选择';
    final b = state.books.where((x) => x.id == state.selectedBookId);
    return b.isEmpty ? '未选择' : b.first.name;
  }
}
