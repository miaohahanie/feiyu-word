import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/settings_repository.dart';
import '../data/word_repository.dart';
import '../models/word.dart';
import '../sync/sync_service.dart';

class WordsPage extends StatefulWidget {
  const WordsPage({super.key});

  @override
  State<WordsPage> createState() => _WordsPageState();
}

class _WordsPageState extends State<WordsPage> {
  List<Word> _words = [];
  bool _loading = true;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final repo = context.read<WordRepository>();
    final bookId = state.selectedBookId;
    if (bookId == null) {
      setState(() => _loading = false);
      return;
    }
    final list = await repo.getWords(bookId, keyword: _keyword.isEmpty ? null : _keyword);
    if (mounted) {
      setState(() {
        _words = list;
        _loading = false;
      });
    }
  }

  Future<SyncService?> _buildService() async {
    final state = context.read<AppState>();
    if (state.selectedBookId == null) return null;
    final settings = context.read<SettingsRepository>();
    final repo = context.read<WordRepository>();
    final deviceId = await settings.getString('sync.deviceId') ?? '';
    return SyncService(
      pairing: state.pairing,
      repository: repo,
      settings: settings,
      deviceId: deviceId,
      bookId: state.selectedBookId!,
    );
  }

  Future<void> _edit(Word w) async {
    final meaningCtrl = TextEditingController(text: w.meaning);
    final phoneticCtrl = TextEditingController(text: w.phonetic);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑 ${w.word}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: meaningCtrl,
              decoration: const InputDecoration(labelText: '中文释义'),
              maxLines: 2,
            ),
            TextField(
              controller: phoneticCtrl,
              decoration: const InputDecoration(labelText: '音标（可选）'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );
    if (saved != true) return;
    try {
      final service = await _buildService();
      if (service == null) return;
      await service.addWord(
        w.word,
        meaning: meaningCtrl.text.trim(),
        phonetic: phoneticCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
  }

  Future<void> _delete(Word w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除 ${w.word}？'),
        content: const Text('将从手机和电脑词本中删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final service = await _buildService();
      if (service == null) return;
      await service.deleteWord(w.word);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('单词本')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) {
                _keyword = v.trim();
                _load();
              },
              decoration: const InputDecoration(
                labelText: '搜索单词 / 释义',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _words.isEmpty
                    ? const Center(child: Text('没有单词'))
                    : ListView.builder(
                        itemCount: _words.length,
                        itemBuilder: (ctx, i) {
                          final w = _words[i];
                          final due = w.isDue(DateTime.now().millisecondsSinceEpoch);
                          return Card(
                            child: ListTile(
                              title: Text(w.word, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                (w.phonetic.isNotEmpty ? '${w.phonetic}\n' : '') + w.meaning,
                                maxLines: 3,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (due)
                                    const Icon(Icons.timer, color: Colors.orange, size: 18),
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () => _edit(w),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _delete(w),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
