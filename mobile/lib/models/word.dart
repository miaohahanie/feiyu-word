import 'dart:convert';

class Example {
  String text;
  String translation;
  String source;

  Example({
    this.text = '',
    this.translation = '',
    this.source = '',
  });

  factory Example.fromJson(Map<String, dynamic> json) {
    return Example(
      text: (json['text'] ?? '').toString(),
      translation: (json['translation'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'translation': translation,
        'source': source,
      };
}

class Word {
  final String bookId;
  final String word;

  String meaning;
  String phonetic;
  List<Example> examples;

  int reps;
  double ease;
  int interval;
  int lapses;
  int? lastRating;
  int nextReview;
  bool mastered;
  bool deleted;
  int updatedAt;

  Word({
    required this.bookId,
    required this.word,
    this.meaning = '',
    this.phonetic = '',
    List<Example>? examples,
    this.reps = 0,
    this.ease = 2.5,
    this.interval = 0,
    this.lapses = 0,
    this.lastRating,
    this.nextReview = 0,
    this.mastered = false,
    this.deleted = false,
    this.updatedAt = 0,
  }) : examples = examples ?? [];

  factory Word.fromServerJson(String bookId, Map<String, dynamic> json) {
    final rawExamples = json['examples'];
    List<Example> examples = [];
    if (rawExamples is List) {
      examples = rawExamples
          .map((e) => Example.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return Word(
      bookId: bookId,
      word: (json['word'] ?? '').toString(),
      meaning: (json['meaning'] ?? '').toString(),
      phonetic: (json['phonetic'] ?? '').toString(),
      examples: examples,
      reps: (json['reps'] ?? 0) as int,
      ease: ((json['ease'] ?? 2.5) as num).toDouble(),
      interval: (json['interval'] ?? 0) as int,
      lapses: (json['lapses'] ?? 0) as int,
      lastRating: json['lastRating'] == null ? null : (json['lastRating'] as num).toInt(),
      nextReview: (json['nextReview'] ?? 0) as int,
      mastered: json['mastered'] == true,
      deleted: json['deleted'] == true,
      updatedAt: (json['updatedAt'] ?? 0) as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bookId': bookId,
      'word': word,
      'meaning': meaning,
      'phonetic': phonetic,
      'examplesJson': jsonEncode(examples.map((e) => e.toJson()).toList()),
      'reps': reps,
      'ease': ease,
      'interval': interval,
      'lapses': lapses,
      'lastRating': lastRating,
      'nextReview': nextReview,
      'mastered': mastered ? 1 : 0,
      'deleted': deleted ? 1 : 0,
      'updatedAt': updatedAt,
    };
  }

  factory Word.fromMap(Map<String, dynamic> map) {
    final rawExamples = map['examplesJson'] as String? ?? '[]';
    List<Example> examples = [];
    try {
      final list = jsonDecode(rawExamples);
      if (list is List) {
        examples = list
            .map((e) => Example.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      examples = [];
    }
    return Word(
      bookId: map['bookId'] as String,
      word: map['word'] as String,
      meaning: (map['meaning'] ?? '') as String,
      phonetic: (map['phonetic'] ?? '') as String,
      examples: examples,
      reps: (map['reps'] ?? 0) as int,
      ease: ((map['ease'] ?? 2.5) as num).toDouble(),
      interval: (map['interval'] ?? 0) as int,
      lapses: (map['lapses'] ?? 0) as int,
      lastRating: map['lastRating'] == null ? null : (map['lastRating'] as num).toInt(),
      nextReview: (map['nextReview'] ?? 0) as int,
      mastered: (map['mastered'] ?? 0) == 1,
      deleted: (map['deleted'] ?? 0) == 1,
      updatedAt: (map['updatedAt'] ?? 0) as int,
    );
  }

  bool isDue(int now) => !mastered && !deleted && (nextReview <= 0 || nextReview <= now);
}
