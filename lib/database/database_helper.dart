import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:path/path.dart';
import '../models/note.dart';
import '../models/todo.dart';

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
          version: 3, onCreate: _createDB, onUpgrade: _upgradeDB);
    }
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path,
        version: 3, onCreate: _createDB, onUpgrade: _upgradeDB);
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
        created_at INTEGER NOT NULL
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
  }

  // ── Notes ────────────────────────────────────────────────────────────────

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
    final old = await db.query(
      'notes',
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );
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
    return db.update(
      'notes',
      {'content': note.content},
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<int> updateCategory(int id, String category) async {
    final db = await database;
    return db.update(
      'notes',
      {'category': category},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteNote(int id) async {
    final db = await database;
    return db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  // ── Todos ─────────────────────────────────────────────────────────────────

  Future<Todo> createTodo(String text, String date) async {
    final db = await database;
    final todo = Todo(text: text, date: date, createdAt: DateTime.now());
    final id = await db.insert('todos', todo.toMap());
    return todo.copyWith(id: id);
  }

  Future<List<Todo>> readAllTodos() async {
    final db = await database;
    final result =
        await db.query('todos', orderBy: 'date ASC, created_at ASC');
    return result.map(Todo.fromMap).toList();
  }

  Future<void> updateTodoDone(int id, bool done) async {
    final db = await database;
    await db.update(
      'todos',
      {'done': done ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateTodoText(int id, String text) async {
    final db = await database;
    await db.update(
      'todos',
      {'text': text},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteTodo(int id) async {
    final db = await database;
    await db.delete('todos', where: 'id = ?', whereArgs: [id]);
  }
}
