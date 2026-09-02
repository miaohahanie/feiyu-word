class Book {
  final String id;
  final String name;
  final String description;
  final bool builtin;
  final int count;

  const Book({
    required this.id,
    required this.name,
    this.description = '',
    this.builtin = false,
    this.count = 0,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      builtin: json['builtin'] == true,
      count: (json['count'] ?? 0) is num ? (json['count'] as num).toInt() : 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'builtin': builtin ? 1 : 0,
      'count': count,
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'] as String,
      name: map['name'] as String,
      description: (map['description'] ?? '') as String,
      builtin: (map['builtin'] ?? 0) == 1,
      count: (map['count'] ?? 0) as int,
    );
  }
}
