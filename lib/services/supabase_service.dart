import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/note.dart';
import '../models/todo.dart';
import '../models/time_record.dart';

/// DatabaseHelper와 동일한 인터페이스 — 클라우드 버전.
/// RLS가 auth.uid() 기준으로 자동 필터링하므로
/// 별도 user_id 조건 없이 호출해도 됩니다.
class SupabaseService {
  static SupabaseClient get _db => Supabase.instance.client;
  static String get _uid => _db.auth.currentUser!.id;

  // ── Notes ─────────────────────────────────────────────────────────────────

  static Future<Note> createNote(String content) async {
    final now = DateTime.now();
    final row = await _db.from('noting_notes').insert({
      'user_id': _uid,
      'content': content,
      'created_at': now.millisecondsSinceEpoch,
    }).select().single();
    return Note.fromMap(row);
  }

  static Future<List<Note>> readAllNotes() async {
    final rows = await _db
        .from('noting_notes')
        .select()
        .order('created_at', ascending: false)
        .limit(500);
    return rows.map(Note.fromMap).toList();
  }

  static Future<List<Note>> searchNotes(String query) async {
    final rows = await _db
        .from('noting_notes')
        .select()
        .ilike('content', '%$query%')
        .order('created_at', ascending: false)
        .limit(500);
    return rows.map(Note.fromMap).toList();
  }

  static Future<List<Note>> readRemindPool({int daysOld = 7}) async {
    final cutoff = DateTime.now()
        .subtract(Duration(days: daysOld))
        .millisecondsSinceEpoch;
    final old = await _db
        .from('noting_notes')
        .select()
        .lt('created_at', cutoff);
    if (old.isNotEmpty) return old.map(Note.fromMap).toList();
    final all = await _db.from('noting_notes').select();
    return all.map(Note.fromMap).toList();
  }

  static Future<Note?> readNote(int id) async {
    final rows =
        await _db.from('noting_notes').select().eq('id', id).limit(1);
    if (rows.isEmpty) return null;
    return Note.fromMap(rows.first);
  }

  static Future<int> updateNote(Note note) async {
    await _db
        .from('noting_notes')
        .update({'content': note.content})
        .eq('id', note.id!);
    return 1;
  }

  static Future<void> updateNoteCategory(int id, String? category) async {
    await _db
        .from('noting_notes')
        .update({'category': category})
        .eq('id', id);
  }

  static Future<int> deleteNote(int id) async {
    await _db.from('noting_notes').delete().eq('id', id);
    return 1;
  }

  // ── Todos ─────────────────────────────────────────────────────────────────

  static Future<Todo> createTodo(String text, String date) async {
    final rows = await _db
        .from('noting_todos')
        .select('order_index')
        .eq('date', date)
        .order('order_index', ascending: false)
        .limit(1);
    final nextOrder =
        rows.isEmpty ? 0 : ((rows.first['order_index'] as int) + 1);
    final now = DateTime.now();
    final row = await _db.from('noting_todos').insert({
      'user_id': _uid,
      'text': text,
      'date': date,
      'done': 0,
      'created_at': now.millisecondsSinceEpoch,
      'order_index': nextOrder,
    }).select().single();
    return Todo.fromMap(row);
  }

  static Future<List<Todo>> readAllTodos() async {
    final rows = await _db
        .from('noting_todos')
        .select()
        .order('date', ascending: true)
        .order('order_index', ascending: true)
        .order('created_at', ascending: true);
    return rows.map(Todo.fromMap).toList();
  }

  static Future<List<Todo>> readTodosForDate(String date) async {
    final rows = await _db
        .from('noting_todos')
        .select()
        .eq('date', date)
        .order('order_index', ascending: true)
        .order('created_at', ascending: true);
    return rows.map(Todo.fromMap).toList();
  }

  static Future<void> updateTodoDone(int id, bool done) async {
    await _db
        .from('noting_todos')
        .update({'done': done ? 1 : 0})
        .eq('id', id);
  }

  static Future<void> updateTodoText(int id, String text) async {
    await _db.from('noting_todos').update({'text': text}).eq('id', id);
  }

  static Future<void> updateTodoTimes(
      int id, String? startTime, String? endTime) async {
    await _db.from('noting_todos').update({
      'start_time': startTime,
      'end_time': endTime,
    }).eq('id', id);
  }

  static Future<void> updateTodoOrderIndex(int id, int orderIndex) async {
    await _db
        .from('noting_todos')
        .update({'order_index': orderIndex})
        .eq('id', id);
  }

  static Future<void> deleteTodo(int id) async {
    await _db.from('noting_todos').delete().eq('id', id);
    // todo_time_records는 ON DELETE CASCADE로 자동 삭제
  }

  static Future<void> importNote(Map<String, dynamic> map) async {
    final existing = await _db
        .from('noting_notes')
        .select('id')
        .eq('content', map['content'] ?? '')
        .eq('created_at', map['created_at'] ?? 0)
        .limit(1);
    if (existing.isEmpty) {
      await _db.from('noting_notes').insert({
        'user_id': _uid,
        'content': map['content'],
        'created_at': map['created_at'],
        'category': map['category'],
      });
    }
  }

  static Future<void> importTodo(Map<String, dynamic> map) async {
    final existing = await _db
        .from('noting_todos')
        .select('id')
        .eq('text', map['text'] ?? '')
        .eq('date', map['date'] ?? '')
        .eq('created_at', map['created_at'] ?? 0)
        .limit(1);
    if (existing.isEmpty) {
      await _db.from('noting_todos').insert({
        'user_id': _uid,
        'text': map['text'],
        'date': map['date'],
        'done': map['done'] ?? 0,
        'created_at': map['created_at'],
        'order_index': map['order_index'] ?? 0,
      });
    }
  }

  // ── TimeRecords ───────────────────────────────────────────────────────────

  static Future<TimeRecord> createTimeRecord(
      int todoId, String startTime) async {
    final row = await _db.from('noting_time_records').insert({
      'user_id': _uid,
      'todo_id': todoId,
      'start_time': startTime,
      'end_time': null,
    }).select().single();
    return TimeRecord.fromMap(row);
  }

  static Future<void> finishTimeRecord(int id, String endTime) async {
    await _db
        .from('noting_time_records')
        .update({'end_time': endTime})
        .eq('id', id);
  }

  static Future<void> updateTimeRecord(
      int id, String startTime, String? endTime) async {
    await _db.from('noting_time_records').update({
      'start_time': startTime,
      'end_time': endTime,
    }).eq('id', id);
  }

  static Future<void> deleteTimeRecord(int id) async {
    await _db.from('noting_time_records').delete().eq('id', id);
  }

  static Future<Map<int, List<TimeRecord>>> readTimeRecordsForDate(
      String date) async {
    // 투두 + 시간 기록을 한 번의 요청으로 (PostgREST 임베드) — 네트워크 왕복 2회 → 1회
    final rows = await _db
        .from('noting_todos')
        .select('id, noting_time_records(*)')
        .eq('date', date);

    final map = <int, List<TimeRecord>>{};
    for (final todo in rows) {
      final recs = (todo['noting_time_records'] as List?) ?? const [];
      if (recs.isEmpty) continue;
      final list = recs
          .map((r) => TimeRecord.fromMap(r as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
      map[todo['id'] as int] = list;
    }
    return map;
  }

  static Future<void> deleteAllTimeRecordsForTodo(int todoId) async {
    await _db
        .from('noting_time_records')
        .delete()
        .eq('todo_id', todoId);
  }
}
