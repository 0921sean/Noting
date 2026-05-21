class TimeRecord {
  final int? id;
  final int todoId;
  final String startTime; // 'HH:MM'
  final String? endTime;  // 'HH:MM'

  const TimeRecord({
    this.id,
    required this.todoId,
    required this.startTime,
    this.endTime,
  });

  int get startMinutes {
    final p = startTime.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  int? get endMinutes {
    if (endTime == null) return null;
    final p = endTime!.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  TimeRecord copyWith({int? id, String? endTime}) => TimeRecord(
        id: id ?? this.id,
        todoId: todoId,
        startTime: startTime,
        endTime: endTime ?? this.endTime,
      );

  factory TimeRecord.fromMap(Map<String, dynamic> m) => TimeRecord(
        id: m['id'] as int?,
        todoId: m['todo_id'] as int,
        startTime: m['start_time'] as String,
        endTime: m['end_time'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'todo_id': todoId,
        'start_time': startTime,
        'end_time': endTime,
      };
}
