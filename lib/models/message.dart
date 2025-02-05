class Message {
  final String id;
  final String text;
  final String? imageUrl;
  final String authorId;
  final String authorName;
  final DateTime timestamp;
  final String? replyToId;
  final String? replyToText;
  final Map<String, bool> likes;
  final Map<String, bool> dislikes;

  Message({
    required this.id,
    required this.text,
    this.imageUrl,
    required this.authorId,
    required this.authorName,
    required this.timestamp,
    this.replyToId,
    this.replyToText,
    Map<String, bool>? likes,
    Map<String, bool>? dislikes,
  }) : 
    likes = likes ?? {},
    dislikes = dislikes ?? {};

  factory Message.fromJson(Map<String, dynamic> json) {
    // Обработка различных форматов timestamp
    DateTime parseTimestamp(dynamic timestamp) {
      if (timestamp is int) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else if (timestamp is String) {
        return DateTime.parse(timestamp);
      } else {
        return DateTime.now(); // Возвращаем текущее время как запасной вариант
      }
    }

    return Message(
      id: json['id'] as String,
      text: json['text'] as String,
      imageUrl: json['imageUrl'] as String?,
      authorId: json['authorId'] as String,
      authorName: json['authorName'] as String,
      timestamp: parseTimestamp(json['timestamp']),
      replyToId: json['replyToId'] as String?,
      replyToText: json['replyToText'] as String?,
      likes: Map<String, bool>.from(json['likes'] ?? {}),
      dislikes: Map<String, bool>.from(json['dislikes'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'imageUrl': imageUrl,
      'authorId': authorId,
      'authorName': authorName,
      'timestamp': timestamp.toIso8601String(), // Сохраняем как строку ISO8601
      'replyToId': replyToId,
      'replyToText': replyToText,
      'likes': likes,
      'dislikes': dislikes,
    };
  }
} 