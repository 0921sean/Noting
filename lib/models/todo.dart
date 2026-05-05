class Todo {
  final int? id;
  final String text;
  final String date; // 'YYYY-MM-DD'
  final bool done;
  final DateTime createdAt;
  final int orderIndex;
  final String? startTime; // 'HH:MM'
  final String? endTime;   // 'HH:MM'

  const Todo({
    this.id,
    required this.text,
    required this.date,
    this.done = false,
    required this.createdAt,
    this.orderIndex = 0,
    this.startTime,
    this.endTime,
  });

  Todo copyWith({
    int? id,
    String? text,
    bool? done,
    int? orderIndex,
    String? startTime,
    String? endTime,
    bool clearStartTime = false,
    bool clearEndTime = false,
  }) =>
      Todo(
        id: id ?? this.id,
        text: text ?? this.text,
        date: date,
        done: done ?? this.done,
        createdAt: createdAt,
        orderIndex: orderIndex ?? this.orderIndex,
        startTime: clearStartTime ? null : (startTime ?? this.startTime),
        endTime: clearEndTime ? null : (endTime ?? this.endTime),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'text': text,
        'date': date,
        'done': done ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'order_index': orderIndex,
        'start_time': startTime,
        'end_time': endTime,
      };

  factory Todo.fromMap(Map<String, dynamic> map) => Todo(
        id: map['id'] as int?,
        text: (map['text'] as String?) ?? '',
        date: (map['date'] as String?) ?? '',
        done: ((map['done'] as int?) ?? 0) == 1,
        createdAt: map['created_at'] is int
            ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
            : DateTime.now(),
        orderIndex: (map['order_index'] as int?) ?? 0,
        startTime: map['start_time'] as String?,
        endTime: map['end_time'] as String?,
      );

  /// 'HH:MM' → 분 단위 정수
  static int? parseMinutes(String? t) {
    if (t == null) return null;
    final parts = t.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  int? get startMinutes => parseMinutes(startTime);
  int? get endMinutes => parseMinutes(endTime);
}
