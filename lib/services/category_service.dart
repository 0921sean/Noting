import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CategoryService {
  static const _key = 'user_categories';
  static const defaults = ['아이디어', '할 일', '생각'];

  static Future<List<String>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return List.from(defaults);
    return (jsonDecode(raw) as List).cast<String>();
  }

  static Future<void> add(String name) async {
    final cats = await getAll();
    if (cats.contains(name)) return;
    cats.add(name);
    await _save(cats);
  }

  static Future<void> remove(String name) async {
    final cats = await getAll();
    cats.remove(name);
    await _save(cats);
  }

  static Future<void> _save(List<String> cats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(cats));
  }

  // 카테고리 인덱스 기반 색상
  static const palette = [
    0xFFD4843A, // 앰버
    0xFF7C5C3E, // 브라운
    0xFF8B8070, // 웜 그레이
    0xFF6B8F71, // 세이지
    0xFF7B6EA6, // 라벤더
    0xFFB85C38, // 러스트
    0xFF5B7FA6, // 스틸 블루
    0xFFA67B5B, // 카라멜
  ];

  static int colorValue(String category, List<String> all) {
    final i = all.indexOf(category);
    return palette[i < 0 ? 0 : i % palette.length];
  }
}
