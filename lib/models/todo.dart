class Todo {
  final int? id;
  final String text;
  final String date; // 'YYYY-MM-DD'
  final bool done;
  final DateTime createdAt;

  const Todo({
    this.id,
    required this.text,
    required this.date,
    this.done = false,
    required this.createdAt,
  });

  Todo copyWith({int? id, String? text, bool? done}) => Todo(
        id: id ?? this.id,
        text: text ?? this.text,
        date: date,
        done: done ?? this.done,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'date': date,
        'done': done ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Todo.fromMap(Map<String, dynamic> map) => Todo(
        id: map['id'] as int?,
        text: (map['text'] as String?) ?? '',
        date: (map['date'] as String?) ?? '',
        done: ((map['done'] as int?) ?? 0) == 1,
        createdAt: map['created_at'] is int
            ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
            : DateTime.now(),
      );
}
