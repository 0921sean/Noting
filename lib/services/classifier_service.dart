import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/note.dart';

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
}
