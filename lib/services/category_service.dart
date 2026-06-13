import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 카테고리 목록은 Supabase의 noting_categories 테이블에 보관 (사용자별 RLS).
/// 이전 버전에서 SharedPreferences에 두던 로컬 목록은 첫 호출 시 자동으로
/// 클라우드로 이전(migrate)된다.
class CategoryService {
  static SupabaseClient get _db => Supabase.instance.client;
  static const _legacyLocalKey = 'user_categories';
  static const _migratedKey = 'categories_migrated_to_cloud';

  // 신규 사용자가 처음 들어왔을 때 보여줄 기본값.
  // 클라우드가 비어있고 로컬에도 아무것도 없을 때만 적용.
  static const defaults = ['아이디어', '할 일', '생각'];

  /// 클라우드에서 카테고리 목록을 순서대로 반환.
  /// 필요 시 로컬 → 클라우드 마이그레이션도 같이 수행.
  static Future<List<String>> getAll() async {
    await _migrateLocalToCloudIfNeeded();
    final rows = await _db
        .from('noting_categories')
        .select('name')
        .order('position', ascending: true);
    return rows.map<String>((r) => r['name'] as String).toList();
  }

  static Future<void> add(String name) async {
    final cats = await getAll();
    if (cats.contains(name)) return;
    await _db.from('noting_categories').insert({
      'name': name,
      'position': cats.length,
    });
  }

  static Future<void> remove(String name) async {
    await _db.from('noting_categories').delete().eq('name', name);
  }

  /// 전체 목록을 통째로 교체 (순서 변경 등).
  /// RLS로 user_id 스코프된 행만 영향받음.
  static Future<void> setAll(List<String> cats) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    // 1) 내 모든 카테고리 삭제
    await _db.from('noting_categories').delete().eq('user_id', uid);
    // 2) 새 순서로 일괄 삽입
    if (cats.isEmpty) return;
    final rows = <Map<String, Object>>[];
    for (int i = 0; i < cats.length; i++) {
      rows.add({'name': cats[i], 'position': i});
    }
    await _db.from('noting_categories').insert(rows);
  }

  /// 이전 버전(SharedPreferences) 카테고리를 클라우드로 일회성 이전.
  /// 이미 클라우드에 데이터가 있거나 한 번 마이그레이션했으면 아무 일도 안 함.
  static Future<void> _migrateLocalToCloudIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_migratedKey) ?? false) return;
    if (_db.auth.currentUser == null) return; // 로그인 안 됐으면 스킵

    // 클라우드에 이미 있으면 그게 진실 — 건너뜀
    final existing =
        await _db.from('noting_categories').select('id').limit(1);
    if (existing.isNotEmpty) {
      await prefs.setBool(_migratedKey, true);
      return;
    }

    // 로컬에서 가져올 수 있는 카테고리
    final raw = prefs.getString(_legacyLocalKey);
    List<String> local;
    if (raw == null) {
      local = List.from(defaults); // 신규 유저 기본값 한 번 심어줌
    } else {
      try {
        local = (jsonDecode(raw) as List).cast<String>();
      } catch (_) {
        local = const [];
      }
    }
    if (local.isNotEmpty) {
      final rows = <Map<String, Object>>[];
      for (int i = 0; i < local.length; i++) {
        rows.add({'name': local[i], 'position': i});
      }
      await _db.from('noting_categories').insert(rows);
    }
    await prefs.setBool(_migratedKey, true);
  }

  /// 로그아웃/계정 삭제 시 마이그레이션 플래그를 리셋. 다음 로그인 사용자가
  /// 자기 클라우드 데이터로 시작할 수 있게 한다.
  static Future<void> resetMigrationFlag() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_migratedKey);
  }

  // ─── 카테고리 인덱스 기반 색상 ─────────────────────────────────────────────
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
