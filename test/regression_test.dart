// Regression tests for bugs found by /codex challenge on 2026-04-27
// Report: codex adversarial review — 13 findings fixed

import 'package:flutter_test/flutter_test.dart';
import 'package:noting/models/note.dart';

void main() {
  group('Note.fromMap — safe cast regressions', () {
    // Regression: ISSUE-010 — hard casts in fromMap crash on corrupt DB rows
    // Found by /codex challenge on 2026-04-27
    test('handles null content without throwing', () {
      final map = {'id': 1, 'content': null, 'created_at': 1000000};
      final note = Note.fromMap(map);
      expect(note.content, '');
    });

    test('handles wrong-type content without throwing', () {
      final map = {'id': 1, 'content': 42, 'created_at': 1000000};
      final note = Note.fromMap(map);
      expect(note.content, '');
    });

    test('handles null created_at without throwing', () {
      final map = {'id': 1, 'content': 'hello', 'created_at': null};
      final note = Note.fromMap(map);
      expect(note.createdAt, isNotNull);
    });

    test('handles wrong-type created_at without throwing', () {
      final map = {'id': 1, 'content': 'hello', 'created_at': 'not-a-number'};
      final note = Note.fromMap(map);
      expect(note.createdAt, isNotNull);
    });

    test('handles null id without throwing', () {
      final map = {'id': null, 'content': 'hello', 'created_at': 1000000};
      final note = Note.fromMap(map);
      expect(note.id, isNull);
    });

    test('handles wrong-type id without throwing', () {
      final map = {'id': 'abc', 'content': 'hello', 'created_at': 1000000};
      final note = Note.fromMap(map);
      expect(note.id, isNull);
    });

    test('round-trips correctly with valid data', () {
      final original = Note(
        id: 7,
        content: 'test note',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final roundTripped = Note.fromMap(original.toMap());
      expect(roundTripped.id, original.id);
      expect(roundTripped.content, original.content);
      expect(roundTripped.createdAt, original.createdAt);
    });
  });
}
