class ReviewEvent {
  final String eventId;
  final String deviceId;
  final String bookId;
  final String word;
  final int rating;
  final int createdAt;
  final bool synced;

  const ReviewEvent({
    required this.eventId,
    required this.deviceId,
    required this.bookId,
    required this.word,
    required this.rating,
    required this.createdAt,
    this.synced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'deviceId': deviceId,
      'bookId': bookId,
      'word': word,
      'rating': rating,
      'createdAt': createdAt,
      'synced': synced ? 1 : 0,
    };
  }

  factory ReviewEvent.fromMap(Map<String, dynamic> map) {
    return ReviewEvent(
      eventId: map['eventId'] as String,
      deviceId: map['deviceId'] as String,
      bookId: map['bookId'] as String,
      word: map['word'] as String,
      rating: (map['rating'] ?? 0) as int,
      createdAt: (map['createdAt'] ?? 0) as int,
      synced: (map['synced'] ?? 0) == 1,
    );
  }
}
