import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/book.dart';
import '../models/review_event.dart';
import '../models/word.dart';

class PairResult {
  final String deviceId;
  final String token;
  final int serverTime;
  final List<Book> books;

  const PairResult({
    required this.deviceId,
    required this.token,
    required this.serverTime,
    required this.books,
  });
}

class SyncPullResult {
  final int serverTime;
  final String bookId;
  final String bookName;
  final List<Word> words;
  final List<String> tombstones;

  const SyncPullResult({
    required this.serverTime,
    required this.bookId,
    required this.bookName,
    required this.words,
    required this.tombstones,
  });
}

class SyncPushResult {
  final int serverTime;
  final int accepted;
  final int ignored;
  final List<Word> changedWords;

  const SyncPushResult({
    required this.serverTime,
    required this.accepted,
    required this.ignored,
    required this.changedWords,
  });
}

class SyncClient {
  final String host;
  final int port;
  final String deviceId;
  final String token;
  final http.Client _client;

  SyncClient({
    required this.host,
    required this.port,
    required this.deviceId,
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();

  String get baseUrl => 'http://$host:$port';

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
        'Device-Id': deviceId,
      };

  static String normalizeIp(String input) {
    var ip = input.trim();
    if (ip.contains('://')) {
      final uri = Uri.tryParse(ip);
      if (uri != null) ip = uri.host;
    }
    return ip;
  }

  static Future<PairResult> pair({
    required String host,
    required int port,
    required String code,
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final res = await c.post(
        Uri.parse('http://$host:$port/api/pair'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );
      if (res.statusCode != 200) {
        throw Exception('配对失败：${res.statusCode} ${res.body}');
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return PairResult(
        deviceId: data['deviceId'] as String,
        token: data['token'] as String,
        serverTime: (data['serverTime'] as num?)?.toInt() ?? 0,
        books: ((data['books'] ?? []) as List)
            .map((b) => Book.fromJson(Map<String, dynamic>.from(b as Map)))
            .toList(),
      );
    } finally {
      if (client == null) c.close();
    }
  }

  Future<List<Book>> fetchBooks() async {
    final res = await _client.get(Uri.parse('$baseUrl/api/books'), headers: headers);
    if (res.statusCode != 200) {
      throw Exception('获取词本失败：${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return ((data['books'] ?? []) as List)
        .map((b) => Book.fromJson(Map<String, dynamic>.from(b as Map)))
        .toList();
  }

  Future<SyncPullResult> pull(String bookId, int since) async {
    final uri = Uri.parse('$baseUrl/api/sync?book=${Uri.encodeComponent(bookId)}&since=$since');
    final res = await _client.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw Exception('同步失败：${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final words = ((data['words'] ?? []) as List)
        .map((w) => Word.fromServerJson(bookId, Map<String, dynamic>.from(w as Map)))
        .toList();
    final tombstones = ((data['tombstones'] ?? []) as List)
        .map((t) => (t as Map)['word'].toString())
        .toList();
    return SyncPullResult(
      serverTime: (data['serverTime'] as num?)?.toInt() ?? 0,
      bookId: bookId,
      bookName: ((data['book'] ?? {})['name'] ?? '').toString(),
      words: words,
      tombstones: tombstones,
    );
  }

  Future<SyncPushResult> push(List<ReviewEvent> events) async {
    if (events.isEmpty) {
      return const SyncPushResult(serverTime: 0, accepted: 0, ignored: 0, changedWords: []);
    }
    final res = await _client.post(
      Uri.parse('$baseUrl/api/sync'),
      headers: headers,
      body: jsonEncode({
        'bookId': events.first.bookId,
        'deviceId': deviceId,
        'events': events
            .map((e) => {
                  'eventId': e.eventId,
                  'word': e.word,
                  'rating': e.rating,
                  'createdAt': e.createdAt,
                })
            .toList(),
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('上传复习进度失败：${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final changed = ((data['changedWords'] ?? []) as List)
        .map((w) => Word.fromServerJson(events.first.bookId, Map<String, dynamic>.from(w as Map)))
        .toList();
    return SyncPushResult(
      serverTime: (data['serverTime'] as num?)?.toInt() ?? 0,
      accepted: (data['accepted'] ?? 0) as int,
      ignored: (data['ignored'] ?? 0) as int,
      changedWords: changed,
    );
  }
}
