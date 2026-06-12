// PostHog Capture API에 HTTP로 직접 이벤트를 보내는 얇은 클라이언트.
//
// SDK 대신 raw HTTP를 쓰는 이유: posthog_flutter가 요구하는 AGP/Kotlin 버전이
// 현재 프로젝트 툴체인보다 높아 빌드가 깨짐. 6개 이벤트만 보내면 되는 우리
// 규모에선 SDK가 과함. /capture 엔드포인트로 단발 POST만 해도 충분.
//
// 동작:
//  - distinct_id: 로그인 후엔 Supabase user UUID, 그 전엔 익명 UUID (앱 설치 식별).
//  - 익명 UUID는 SharedPreferences에 저장 — 앱 재설치 전까지 유지.
//  - 로그인 시 identify로 익명 ID를 user UUID에 alias (PostHog의 $identify).
//  - 모든 호출 fire-and-forget. 네트워크 실패해도 앱 정상 작동.

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class AnalyticsService {
  static const _kAnonIdKey = 'analytics_anon_id';
  static const _kUserIdKey = 'analytics_user_id';
  static bool _enabled = false;
  static String? _distinctId; // 현재 활성 ID (user UUID 또는 anon)

  /// main.dart에서 호출. 익명 ID 로드/생성 + 저장된 user ID 복원.
  static Future<void> initialize() async {
    if (kPostHogApiKey.isEmpty) return;
    _enabled = true;
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_kUserIdKey);
    if (userId != null) {
      _distinctId = userId;
      return;
    }
    var anon = prefs.getString(_kAnonIdKey);
    if (anon == null) {
      anon = _generateAnonId();
      await prefs.setString(_kAnonIdKey, anon);
    }
    _distinctId = anon;
  }

  /// 로그인/가입 성공 시 호출. PostHog의 $identify로 익명→user 매핑.
  static Future<void> identify(String userId) async {
    if (!_enabled) return;
    final prefs = await SharedPreferences.getInstance();
    final prevAnon = prefs.getString(_kAnonIdKey);
    await prefs.setString(_kUserIdKey, userId);
    _distinctId = userId;
    // 익명 ID가 있고 새 userId와 다르면 alias (코호트 연속성 유지)
    if (prevAnon != null && prevAnon != userId) {
      await _send('\$identify', extra: {
        '\$anon_distinct_id': prevAnon,
      });
    } else {
      await _send('\$identify');
    }
  }

  /// 로그아웃/계정 삭제 시 호출. 새 익명 ID로 재시작.
  static Future<void> reset() async {
    if (!_enabled) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUserIdKey);
    final newAnon = _generateAnonId();
    await prefs.setString(_kAnonIdKey, newAnon);
    _distinctId = newAnon;
  }

  static Future<void> _send(String event,
      {Map<String, Object>? props, Map<String, Object>? extra}) async {
    if (!_enabled || _distinctId == null) return;
    if (kDebugMode) {
      debugPrint('[analytics] $event ${props ?? {}}');
    }
    try {
      final body = <String, Object>{
        'api_key': kPostHogApiKey,
        'event': event,
        'distinct_id': _distinctId!,
        'properties': {
          if (props != null) ...props,
          if (extra != null) ...extra,
          '\$lib': 'noting-flutter',
        },
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      await http
          .post(
            Uri.parse('$kPostHogHost/i/v0/e/'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // 의도적 무시 — analytics 실패가 앱 기능에 영향 주지 않게
    }
  }

  static String _generateAnonId() {
    final r = Random.secure();
    // 32자리 hex (UUID 비슷한 길이, 식별만 가능하면 됨)
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  // ── 코어 6개 ─────────────────────────────────────────────────────────────
  static Future<void> signUp() => _send('sign_up');
  static Future<void> onboardingCompleted() => _send('onboarding_completed');
  static Future<void> appOpen(String source) =>
      _send('app_open', props: {'source': source});
  static Future<void> noteCreated() => _send('note_created');
  static Future<void> todoCreated() => _send('todo_created');
  static Future<void> plannerShared() => _send('planner_shared');

  // ── 2차 ────────────────────────────────────────────────────────────────
  static Future<void> aiClassifyUsed(
          {required bool success, int? notesCount}) =>
      _send('ai_classify_used', props: {
        'success': success,
        if (notesCount != null) 'notes_count': notesCount,
      });
}
