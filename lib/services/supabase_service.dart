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

  /// 여러 투두를 한 번에 생성 (밀린 할 일 복사 등).
  /// createTodo를 N번 부르면 왕복이 2N회지만, 이건 order 조회 1 + 삽입 1 = 2회로 끝난다.
  ///
  /// [orderIndexes]를 주면 그 값을 그대로 쓴다 — 옮긴 항목과 섞어서 원래 순서를
  /// 복원해야 할 때 필요(밀린 할 일 가져오기). 안 주면 해당 날짜 끝에 차례로 붙인다.
  static Future<List<Todo>> createTodosBatch(List<String> texts, String date,
      {List<int>? orderIndexes}) async {
    if (texts.isEmpty) return [];
    var next = 0;
    if (orderIndexes == null) {
      final rows = await _db
          .from('noting_todos')
          .select('order_index')
          .eq('date', date)
          .order('order_index', ascending: false)
          .limit(1);
      next = rows.isEmpty ? 0 : ((rows.first['order_index'] as int) + 1);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final payload = [
      for (int i = 0; i < texts.length; i++)
        {
          'user_id': _uid,
          'text': texts[i],
          'date': date,
          'done': 0,
          'created_at': now,
          'order_index': orderIndexes?[i] ?? next++,
        }
    ];
    final inserted = await _db.from('noting_todos').insert(payload).select();
    // insert().select()의 행 반환 순서는 Postgres가 보장하지 않는다.
    // 화면에 붙일 때 입력 순서가 어긋나지 않게 order_index로 정렬해 돌려준다.
    final list = inserted.map(Todo.fromMap).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return list;
  }

  /// 해당 날짜 목록 맨 끝에 붙일 order_index.
  static Future<int> nextOrderIndex(String date) async {
    final rows = await _db
        .from('noting_todos')
        .select('order_index')
        .eq('date', date)
        .order('order_index', ascending: false)
        .limit(1);
    return rows.isEmpty ? 0 : ((rows.first['order_index'] as int) + 1);
  }

  /// 주어진 투두들 중 **시간 기록이 달린 것**의 id 집합.
  /// 시간 기록은 자체 날짜가 없고 todo의 date를 따라가므로, 기록이 있는 투두를
  /// 다른 날짜로 옮기면 그 날 플래너에서 시간 블록이 사라진다. 그래서 옮기기
  /// 전에 걸러내려고 쓴다.
  static Future<Set<int>> todoIdsWithTimeRecords(List<int> todoIds) async {
    if (todoIds.isEmpty) return {};
    final rows = await _db
        .from('noting_time_records')
        .select('todo_id')
        .inFilter('todo_id', todoIds);
    return rows.map((r) => r['todo_id'] as int).toSet();
  }

  /// 여러 투두의 날짜를 옮긴다(밀린 할 일 가져오기).
  /// `todoIds` **순서대로** order_index를 1씩 늘려 부여하고, 그 순서대로 돌려준다.
  ///
  /// 예전엔 한 번의 update로 전부 같은 order_index를 주고 "정렬이
  /// order_index → created_at이니 created_at이 순서를 지켜준다"고 봤는데 **틀렸다.**
  /// created_at은 *최초 생성* 시각이라, 사용자가 드래그로 바꿔둔 순서를 무시한다
  /// (B를 A 위로 올려놨어도 A가 먼저 만들어졌으면 A가 위로 올라감).
  /// 그래서 행마다 다른 값을 줘야 하고, 이는 N번 업데이트가 불가피하다
  /// (`id`가 `generated always as identity`라 upsert로 다중행 update가 안 됨).
  /// 대신 순차 await가 아니라 병렬로 날려 지연을 왕복 1회 수준으로 억제한다.
  static Future<List<Todo>> moveTodosToDate(List<int> todoIds, String date,
      {List<int>? orderIndexes}) async {
    if (todoIds.isEmpty) return [];
    var base = 0;
    if (orderIndexes == null) base = await nextOrderIndex(date);
    final updated = await Future.wait([
      for (int i = 0; i < todoIds.length; i++)
        _db
            .from('noting_todos')
            .update({
              'date': date,
              'order_index': orderIndexes?[i] ?? (base + i),
            })
            .eq('id', todoIds[i])
            .select()
            .single(),
    ]);
    // Future.wait는 입력 순서대로 결과를 돌려주므로 todoIds 순서가 그대로 유지된다.
    // (update().select()의 행 반환 순서는 Postgres가 보장하지 않아 믿으면 안 된다)
    return updated.map(Todo.fromMap).toList();
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
