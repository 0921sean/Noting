import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path/path.dart';
import '../models/note.dart';
import '../models/todo.dart';
import '../models/time_record.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Future<Database>? _databaseFuture;

  DatabaseHelper._init();

  Future<Database> get database async {
    _databaseFuture ??= _initDB('noting.db');
    return _databaseFuture!;
  }

  Future<Database> _initDB(String filePath) async {
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
      return await openDatabase(filePath,
          version: 6, onCreate: _createDB, onUpgrade: _upgradeDB);
    }
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path,
        version: 6, onCreate: _createDB, onUpgrade: _upgradeDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        category TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE todos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT NOT NULL,
        date TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        order_index INTEGER NOT NULL DEFAULT 0,
        start_time TEXT,
        end_time TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE todo_time_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        todo_id INTEGER NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE notes ADD COLUMN category TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE todos (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          text TEXT NOT NULL,
          date TEXT NOT NULL,
          done INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute("UPDATE notes SET category = '아이디어' WHERE category = 'idea'");
      await db.execute("UPDATE notes SET category = '할 일' WHERE category = 'todo'");
      await db.execute("UPDATE notes SET category = '생각' WHERE category = 'thought'");
      await db.execute(
          'ALTER TABLE todos ADD COLUMN order_index INTEGER NOT NULL DEFAULT 0');
      final rows = await db.query('todos', orderBy: 'date ASC, created_at ASC');
      for (int i = 0; i < rows.length; i++) {
        await db.update('todos', {'order_index': i},
            where: 'id = ?', whereArgs: [rows[i]['id']]);
      }
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE todos ADD COLUMN start_time TEXT');
      await db.execute('ALTER TABLE todos ADD COLUMN end_time TEXT');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE todo_time_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          todo_id INTEGER NOT NULL,
          start_time TEXT NOT NULL,
          end_time TEXT
        )
      ''');
      // 기존 start_time/end_time이 있는 투두를 records로 마이그레이션
      final existing = await db.query('todos',
          where: 'start_time IS NOT NULL');
      for (final row in existing) {
        await db.insert('todo_time_records', {
          'todo_id': row['id'],
          'start_time': row['start_time'],
          'end_time': row['end_time'],
        });
      }
    }
  }

  // ── Notes ─────────────────────────────────────────────────────────────────

  Future<Note> createNote(String content) async {
    final db = await database;
    final note = Note(content: content, createdAt: DateTime.now());
    final id = await db.insert('notes', note.toMap());
    return note.copyWith(id: id);
  }

  Future<List<Note>> readAllNotes() async {
    final db = await database;
    final result =
        await db.query('notes', orderBy: 'created_at DESC', limit: 500);
    return result.map(Note.fromMap).toList();
  }

  Future<List<Note>> searchNotes(String query) async {
    final db = await database;
    final result = await db.query(
      'notes',
      where: 'content LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'created_at DESC',
      limit: 500,
    );
    return result.map(Note.fromMap).toList();
  }

  Future<List<Note>> readRemindPool({int daysOld = 7}) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: daysOld))
        .millisecondsSinceEpoch;
    final old =
        await db.query('notes', where: 'created_at < ?', whereArgs: [cutoff]);
    if (old.isNotEmpty) return old.map(Note.fromMap).toList();
    final all = await db.query('notes');
    return all.map(Note.fromMap).toList();
  }

  Future<Note?> readNote(int id) async {
    final db = await database;
    final maps = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Note.fromMap(maps.first);
  }

  Future<int> updateNote(Note note) async {
    final db = await database;
    return db.update('notes', {'content': note.content},
        where: 'id = ?', whereArgs: [note.id]);
  }

  Future<void> updateNoteCategory(int id, String? category) async {
    final db = await database;
    await db.update('notes', {'category': category},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteNote(int id) async {
    final db = await database;
    return db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  // ── Todos ─────────────────────────────────────────────────────────────────

  Future<Todo> createTodo(String text, String date) async {
    final db = await database;
    final rows = await db.query('todos',
        where: 'date = ?',
        whereArgs: [date],
        orderBy: 'order_index DESC',
        limit: 1);
    final nextOrder =
        rows.isEmpty ? 0 : ((rows.first['order_index'] as int) + 1);
    final todo =
        Todo(text: text, date: date, createdAt: DateTime.now(), orderIndex: nextOrder);
    final id = await db.insert('todos', todo.toMap());
    return todo.copyWith(id: id);
  }

  Future<List<Todo>> readAllTodos() async {
    final db = await database;
    final result = await db.query('todos',
        orderBy: 'date ASC, order_index ASC, created_at ASC');
    return result.map(Todo.fromMap).toList();
  }

  Future<List<Todo>> readTodosForDate(String date) async {
    final db = await database;
    final result = await db.query('todos',
        where: 'date = ?',
        whereArgs: [date],
        orderBy: 'order_index ASC, created_at ASC');
    return result.map(Todo.fromMap).toList();
  }

  Future<void> updateTodoDone(int id, bool done) async {
    final db = await database;
    await db.update('todos', {'done': done ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateTodoText(int id, String text) async {
    final db = await database;
    await db.update('todos', {'text': text},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateTodoTimes(int id, String? startTime, String? endTime) async {
    final db = await database;
    await db.update('todos', {'start_time': startTime, 'end_time': endTime},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateTodoOrderIndex(int id, int orderIndex) async {
    final db = await database;
    await db.update('todos', {'order_index': orderIndex},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> importNote(Map<String, dynamic> map) async {
    final db = await database;
    final existing = await db.query('notes',
        where: 'content = ? AND created_at = ?',
        whereArgs: [map['content'], map['created_at']]);
    if (existing.isEmpty) {
      await db.insert('notes', {
        'content': map['content'],
        'created_at': map['created_at'],
        'category': map['category'],
      });
    }
  }

  Future<void> importTodo(Map<String, dynamic> map) async {
    final db = await database;
    final existing = await db.query('todos',
        where: 'text = ? AND date = ? AND created_at = ?',
        whereArgs: [map['text'], map['date'], map['created_at']]);
    if (existing.isEmpty) {
      await db.insert('todos', {
        'text': map['text'],
        'date': map['date'],
        'done': map['done'] ?? 0,
        'created_at': map['created_at'],
        'order_index': map['order_index'] ?? 0,
      });
    }
  }

  Future<void> deleteTodo(int id) async {
    final db = await database;
    await db.delete('todos', where: 'id = ?', whereArgs: [id]);
    await db.delete('todo_time_records', where: 'todo_id = ?', whereArgs: [id]);
  }

  // ── TimeRecords ───────────────────────────────────────────────────────────

  Future<TimeRecord> createTimeRecord(int todoId, String startTime) async {
    final db = await database;
    final record = TimeRecord(todoId: todoId, startTime: startTime);
    final id = await db.insert('todo_time_records', {
      'todo_id': todoId,
      'start_time': startTime,
      'end_time': null,
    });
    return record.copyWith(id: id);
  }

  Future<void> finishTimeRecord(int id, String endTime) async {
    final db = await database;
    await db.update('todo_time_records', {'end_time': endTime},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateTimeRecord(
      int id, String startTime, String? endTime) async {
    final db = await database;
    await db.update('todo_time_records',
        {'start_time': startTime, 'end_time': endTime},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTimeRecord(int id) async {
    final db = await database;
    await db.delete('todo_time_records', where: 'id = ?', whereArgs: [id]);
  }

  /// 특정 날짜의 모든 투두에 대한 시간 기록 (todoId → List<TimeRecord>)
  Future<Map<int, List<TimeRecord>>> readTimeRecordsForDate(String date) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT r.* FROM todo_time_records r
      INNER JOIN todos t ON r.todo_id = t.id
      WHERE t.date = ?
      ORDER BY r.start_time ASC
    ''', [date]);

    final map = <int, List<TimeRecord>>{};
    for (final row in rows) {
      final rec = TimeRecord.fromMap(row);
      map.putIfAbsent(rec.todoId, () => []).add(rec);
    }
    return map;
  }

  Future<void> deleteAllTimeRecordsForTodo(int todoId) async {
    final db = await database;
    await db.delete('todo_time_records',
        where: 'todo_id = ?', whereArgs: [todoId]);
  }
}
