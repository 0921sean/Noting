import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/note.dart';
import '../models/note_group.dart';

typedef AutoCategoryResult = ({
  List<String> categories,
  Map<int, String> assignments,
});

class ClassifierService {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-haiku-4-5-20251001';

  /// 한글 카테고리명 ('아이디어', '할 일', '생각') 중 하나를 반환.
  /// 실패 시 '생각' 반환.
  static Future<String?> classify(String content) async {
    try {
      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'x-api-key': kAnthropicApiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'max_tokens': 20,
              'messages': [
                {
                  'role': 'user',
                  'content': '다음 한국어 메모를 분류하세요.\n'
                      '카테고리: 아이디어(새로운 생각/제안) / 할 일(해야 할 일/계획/약속) / 생각(일상/감정/관찰/기억)\n'
                      '메모: "${content.replaceAll('"', '\\"')}"\n'
                      '아이디어, 할 일, 생각 중 하나만 응답하세요.',
                }
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final text =
            ((data['content'] as List).first['text'] as String).trim();
        if (['아이디어', '할 일', '생각'].contains(text)) return text;
      }
    } catch (_) {}
    return '생각';
  }

  static Future<void> reclassifyAll({
    required List<Note> notes,
    required void Function(int id, String category) onClassified,
  }) async {
    for (final note in notes) {
      if (note.id == null) continue;
      final category = await classify(note.content);
      if (category != null) onClassified(note.id!, category);
    }
  }

  /// 메모 전체를 분석해서 적절한 카테고리를 자동 생성하고 분류.
  /// 반환: 카테고리 목록 + 각 note id 별 카테고리 배정.
  static Future<AutoCategoryResult?> autoGenerateCategories(
      List<Note> notes) async {
    if (notes.isEmpty) return null;

    // 메모가 많으면 일부만 사용 (max 80개, 내용은 120자까지)
    final sample = notes.length > 80 ? notes.sublist(0, 80) : notes;
    final noteLines = sample.map((n) {
      final content = n.content.length > 120
          ? n.content.substring(0, 120).replaceAll('\n', ' ')
          : n.content.replaceAll('\n', ' ');
      return '[${n.id}] $content';
    }).join('\n');

    const prompt = '''아래는 사용자의 메모 목록이야. 전체 내용을 읽고 적절한 한국어 카테고리를 만들어서 각 메모를 분류해줘.

규칙:
- 카테고리는 3~6개 (너무 세분화 금지, 큰 주제로 묶기)
- 카테고리 이름은 한국어 2~5글자
- 모든 메모에 카테고리 배정 (id 기준)
- 다른 텍스트 없이 JSON만 응답

응답 형식:
{"categories":["카테고리1","카테고리2"],"assignments":{"메모id":"카테고리명",...}}

메모 목록:
''';

    try {
      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'x-api-key': kAnthropicApiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'max_tokens': 2000,
              'messages': [
                {'role': 'user', 'content': '$prompt$noteLines'},
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (resp.statusCode != 200) return null;

      final body = utf8.decode(resp.bodyBytes);
      final data = jsonDecode(body) as Map<String, dynamic>;
      final text =
          ((data['content'] as List).first['text'] as String).trim();

      // JSON 블록 추출
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (match == null) return null;

      final parsed = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      final categories = (parsed['categories'] as List).cast<String>();
      final raw = (parsed['assignments'] as Map<String, dynamic>);
      final assignments = <int, String>{};
      for (final entry in raw.entries) {
        final id = int.tryParse(entry.key);
        if (id != null) assignments[id] = entry.value as String;
      }

      return (categories: categories, assignments: assignments);
    } catch (_) {
      return null;
    }
  }

  /// 메모를 AI가 실시간으로 주제별 그루핑 (저장 안 함, 표시용).
  static Future<List<NoteGroup>?> clusterNotes(List<Note> notes) async {
    if (notes.isEmpty) return null;

    final sample = notes.length > 100 ? notes.sublist(0, 100) : notes;
    final noteLines = sample.map((n) {
      final content = n.content.length > 100
          ? n.content.substring(0, 100).replaceAll('\n', ' ')
          : n.content.replaceAll('\n', ' ');
      return '[${n.id}] $content';
    }).join('\n');

    const prompt = '''아래 메모들을 주제별로 그루핑해줘.

규칙:
- 그룹 3~7개, 한국어 2~6글자 이름
- 모든 메모를 하나의 그룹에 배정
- 다른 텍스트 없이 JSON만 응답

{"groups":[{"name":"그룹명","ids":[메모id,...]}, ...]}

메모:
''';

    try {
      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'x-api-key': kAnthropicApiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'max_tokens': 2000,
              'messages': [
                {'role': 'user', 'content': '$prompt$noteLines'},
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (resp.statusCode != 200) return null;

      final body = utf8.decode(resp.bodyBytes);
      final data = jsonDecode(body) as Map<String, dynamic>;
      final text =
          ((data['content'] as List).first['text'] as String).trim();

      final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (match == null) return null;

      final parsed = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      final groups = (parsed['groups'] as List).map((g) {
        final name = g['name'] as String;
        final ids = (g['ids'] as List)
            .map((id) => id is int ? id : int.tryParse(id.toString()))
            .whereType<int>()
            .toList();
        return NoteGroup(name: name, noteIds: ids);
      }).toList();

      return groups;
    } catch (_) {
      return null;
    }
  }
}
