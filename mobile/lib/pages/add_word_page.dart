import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/settings_repository.dart';
import '../data/word_repository.dart';
import '../sync/sync_service.dart';

class AddWordPage extends StatefulWidget {
  const AddWordPage({super.key});

  @override
  State<AddWordPage> createState() => _AddWordPageState();
}

class _AddWordPageState extends State<AddWordPage> {
  final _wordCtrl = TextEditingController();
  final _meaningCtrl = TextEditingController();
  final _phoneticCtrl = TextEditingController();
  bool _busy = false;
  String _message = '';

  @override
  void dispose() {
    _wordCtrl.dispose();
    _meaningCtrl.dispose();
    _phoneticCtrl.dispose();
    super.dispose();
  }

  Future<SyncService?> _buildService() async {
    final state = context.read<AppState>();
    if (state.selectedBookId == null) {
      setState(() => _message = '请先在首页选择词本');
      return null;
    }
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

  Future<void> _lookupAndAdd() async {
    final word = _wordCtrl.text.trim();
    if (word.isEmpty) {
      setState(() => _message = '请输入单词');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = '正在查词…';
    });
    try {
      final service = await _buildService();
      if (service == null) return;
      final result = await service.lookupWord(word);
      if (!mounted) return;
      setState(() {
        _meaningCtrl.text = result.meaning;
        _phoneticCtrl.text = result.phonetic;
        _message = '已查到释义，请确认后点击“添加”（来源：${result.source}）';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _message = '查词失败：$e\n可手动填写释义后再添加');
      }
    } finally {
      // 未选词本等提前返回也要复位，否则按钮永久禁用
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add({required bool lookupFirst}) async {
    final word = _wordCtrl.text.trim();
    final meaning = _meaningCtrl.text.trim();
    if (word.isEmpty) {
      setState(() => _message = '请输入单词');
      return;
    }
    if (!lookupFirst && meaning.isEmpty) {
      setState(() => _message = '请填写释义，或先点击“查词”');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = '正在添加…';
    });
    try {
      final service = await _buildService();
      if (service == null) return;
      final saved = await service.addWord(
        word,
        meaning: meaning.isEmpty ? null : meaning,
        phonetic: _phoneticCtrl.text.trim().isEmpty ? null : _phoneticCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _message = '已添加：${saved.word}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已添加「${saved.word}」到词本')),
      );
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message = '添加失败：$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('添加单词')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _wordCtrl,
            decoration: const InputDecoration(labelText: '单词（英文）'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _meaningCtrl,
            decoration: const InputDecoration(labelText: '中文释义（可点击“查词”自动填充）'),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneticCtrl,
            decoration: const InputDecoration(labelText: '音标（可选）'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : () => _add(lookupFirst: false),
            child: Text(_busy ? '处理中…' : '手动添加'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _lookupAndAdd,
            child: const Text('自动查词并填充'),
          ),
          const SizedBox(height: 12),
          Text(_message),
        ],
      ),
    );
  }
}
