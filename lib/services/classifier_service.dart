import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/note.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClassifierService {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-haiku-4-5-20251001';
  static const _validCategories = ['idea', 'todo', 'thought'];

  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('anthropic_api_key');
  }

  /// Returns 'idea', 'todo', or 'thought'. Returns null if API key is missing.
  static Future<String?> classify(String content, String apiKey) async {
    if (apiKey.isEmpty) return null;
    try {
      final resp = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'max_tokens': 10,
              'messages': [
                {
                  'role': 'user',
                  'content': '다음 한국어 메모를 분류하세요.\n'
                      '카테고리: idea(아이디어/새로운 생각/제안) / todo(해야 할 일/계획/약속) / thought(일상/감정/관찰/기억)\n'
                      '메모: "${content.replaceAll('"', '\\"')}"\n'
                      'idea, todo, thought 중 하나만 응답하세요.',
                }
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final text =
            ((data['content'] as List).first['text'] as String).trim().toLowerCase();
        if (_validCategories.contains(text)) return text;
      }
    } catch (_) {}
    return 'thought';
  }

  /// Classifies all given notes and calls [onClassified] for each result.
  static Future<void> reclassifyAll({
    required String apiKey,
    required List<Note> notes,
    required void Function(int id, String category) onClassified,
  }) async {
    for (final note in notes) {
      if (note.id == null) continue;
      final category = await classify(note.content, apiKey);
      if (category != null) {
        onClassified(note.id!, category);
      }
    }
  }
}
