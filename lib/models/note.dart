class Note {
  final int? id;
  final String content;
  final DateTime createdAt;
  final String? category;

  Note({
    this.id,
    required this.content,
    required this.createdAt,
    this.category,
  });

  Note copyWith({
    int? id,
    String? content,
    DateTime? createdAt,
    String? category,
    bool clearCategory = false,
  }) =>
      Note(
        id: id ?? this.id,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        category: clearCategory ? null : (category ?? this.category),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'content': content,
        'created_at': createdAt.millisecondsSinceEpoch,
        'category': category,
      };

  factory Note.fromMap(Map<String, dynamic> map) => Note(
        id: map['id'] is int ? map['id'] as int : null,
        content: map['content'] is String ? map['content'] as String : '',
        createdAt: map['created_at'] is int
            ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
            : DateTime.now(),
        category: map['category'] as String?,
      );
}
