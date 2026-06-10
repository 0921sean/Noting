import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../services/supabase_service.dart';

// Callback type for when user taps a notification while app is running
typedef NotificationTapCallback = void Function(int noteId);
typedef VoidNotificationCallback = void Function();

class NotificationService {
  static final NotificationService instance = NotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();

  NotificationTapCallback? onNotificationTap;
  // 자정 플래너 알림을 탭했을 때 호출 (앱 실행 중)
  VoidNotificationCallback? onPlannerReminderTap;
  bool _scheduling = false;

  NotificationService._();

  static const _channelId = 'noting_remind';
  static const _channelName = 'Noting 리마인드';
  static const _todoChannelId = 'noting_todo';
  static const _todoChannelName = 'Noting 투두';
  static const _timerChannelId = 'noting_timer';
  static const _timerChannelName = 'Noting 진행 중';
  static const _plannerChannelId = 'noting_planner';
  static const _plannerChannelName = 'Noting 플래너 알림';
  static const _plannerNotifId = 996;
  static const _nudgeNotifId = 997;
  static const _timerNotifId = 998;
  static const _nudgeMinutes = 90;
  static const _channelDesc = '예전 메모를 다시 보여줍니다';
  static const _plannerPayload = 'planner';

  // 하루에 알림을 띄울 시각 오프셋 (사용자가 설정한 hour 기준)
  // 예: hour=9 → 9시, 15시, 20시
  static const _dailyOffsets = [0, 6, 11];

  Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: iOS),
      onDidReceiveNotificationResponse: _handleResponse,
      onDidReceiveBackgroundNotificationResponse: _handleBackgroundResponse,
    );
  }

  void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    if (payload == _plannerPayload) {
      onPlannerReminderTap?.call();
      return;
    }
    final noteId = int.tryParse(payload);
    if (noteId != null) onNotificationTap?.call(noteId);
  }

  // Background taps are handled on next app open via getNotificationAppLaunchDetails
  @pragma('vm:entry-point')
  static void _handleBackgroundResponse(NotificationResponse response) {}

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  // Check if app was launched by tapping a notification. Returns note ID or null.
  Future<int?> getLaunchNoteId() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    final payload = details.notificationResponse?.payload;
    return payload != null ? int.tryParse(payload) : null;
  }

  // 콜드 스타트 시 자정 플래너 알림 탭으로 열렸는지 확인.
  Future<bool> wasLaunchedByPlannerReminder() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return false;
    return details.notificationResponse?.payload == _plannerPayload;
  }

  // 하루 3번(기본 9시/15시/20시) 각각 다른 옛 메모로 알림을 예약한다.
  // 앱이 열릴 때 호출 → 컨텐츠가 항상 신선.
  Future<void> scheduleReminders() async {
    if (_scheduling) return;
    _scheduling = true;
    try {
      final notes = await SupabaseService.readRemindPool(daysOld: 7);
      if (notes.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final hour = prefs.getInt('notif_hour') ?? 9;
      final minute = prefs.getInt('notif_minute') ?? 0;

      // 메모 알림만 취소 (타이머/nudge는 유지). ID 범위 0..(maxDays*slots-1)
      const maxDays = 20;
      final slots = _dailyOffsets.length; // 3
      for (int i = 0; i < maxDays * slots; i++) {
        await _plugin.cancel(i);
      }

      final shuffled = List.of(notes)..shuffle(Random());
      final now = tz.TZDateTime.now(tz.local);
      final base =
          tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

      int idx = 0;
      for (int d = 1; d <= maxDays; d++) {
        for (int s = 0; s < slots; s++) {
          final note = shuffled[idx % shuffled.length];
          final scheduled =
              base.add(Duration(days: d, hours: _dailyOffsets[s]));
          final preview = note.content.length > 120
              ? '${note.content.substring(0, 120)}...'
              : note.content;
          try {
            await _plugin.zonedSchedule(
              d * slots + s,
              '기억하고 있어? 💭',
              preview,
              scheduled,
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  _channelId,
                  _channelName,
                  channelDescription: _channelDesc,
                  importance: Importance.high,
                  priority: Priority.high,
                  visibility: NotificationVisibility.private,
                ),
                iOS: DarwinNotificationDetails(
                  presentAlert: true,
                  presentBadge: false,
                  presentSound: true,
                ),
              ),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
              payload: note.id.toString(),
            );
          } catch (_) {
            // exactAllowWhileIdle 제한 등 → 해당 슬롯 건너뜀
          }
          idx++;
        }
      }
    } finally {
      _scheduling = false;
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  /// 마지막 완료 시점으로부터 90분 후에 nudge 알림 예약.
  /// 완료 시마다 호출해서 타이머를 리셋.
  Future<void> scheduleNudge() async {
    await _plugin.cancel(_nudgeNotifId);
    final now = tz.TZDateTime.now(tz.local);
    final nudgeAt = now.add(const Duration(minutes: _nudgeMinutes));
    // 활성 시간대(09:00~22:00)에만 알림
    if (nudgeAt.hour < 9 || nudgeAt.hour >= 22) return;
    try {
      await _plugin.zonedSchedule(
        _nudgeNotifId,
        '잠깐, 하고 있어? 👀',
        '$_nudgeMinutes분째 완료된 할 일이 없어',
        nudgeAt,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _todoChannelId,
            _todoChannelName,
            channelDescription: '투두 미완료 nudge',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }

  Future<void> cancelNudge() async => _plugin.cancel(_nudgeNotifId);

  // ─── 매일 자정 플래너 작성 알림 ────────────────────────────────────────────────
  // 자정에 매일 반복 — '오늘의 플래너 짜자'고 상기.
  Future<void> scheduleMidnightPlannerReminder() async {
    final now = tz.TZDateTime.now(tz.local);
    var firstFire =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, 0, 0);
    if (!firstFire.isAfter(now)) {
      firstFire = firstFire.add(const Duration(days: 1));
    }
    try {
      await _plugin.zonedSchedule(
        _plannerNotifId,
        '오늘의 플래너 ✨',
        '오늘 할 일을 정리하고 플래너를 만들어볼까요?',
        firstFire,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _plannerChannelId,
            _plannerChannelName,
            channelDescription: '매일 자정 플래너 작성 알림',
            importance: Importance.high,
            priority: Priority.high,
            visibility: NotificationVisibility.private,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // 매일 같은 시각에 반복
        payload: _plannerPayload,
      );
    } catch (_) {}
  }

  Future<void> cancelMidnightPlannerReminder() =>
      _plugin.cancel(_plannerNotifId);

  // ─── 진행 중 타이머 상단 알림 배너 ─────────────────────────────────────────────
  // 타이머 켜진 동안 상단/잠금화면에 표시해서 종료 깜빡 잊는 걸 방지.
  // [active]가 비면 알림을 제거. 한 개면 단일 표시, 여러 개면 요약 표시.

  Future<void> showActiveTimers(List<ActiveTimer> active) async {
    if (active.isEmpty) {
      await _plugin.cancel(_timerNotifId);
      return;
    }
    final title = active.length == 1
        ? '진행 중: ${active.first.todoText}'
        : '진행 중인 일 ${active.length}개';
    final body = active.length == 1
        ? '${active.first.startTime} 시작'
        : active.map((t) => '• ${t.todoText} (${t.startTime}~)').join('\n');

    try {
      await _plugin.show(
        _timerNotifId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _timerChannelId,
            _timerChannelName,
            channelDescription: '진행 중인 할 일 표시 (계속 떠 있음)',
            importance: Importance.low, // 소리/진동 없이 조용히 상단 표시
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            visibility: NotificationVisibility.public,
            playSound: false,
            enableVibration: false,
            showWhen: true,
            styleInformation: active.length > 1
                ? BigTextStyleInformation(body)
                : null,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: false,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> cancelActiveTimers() => _plugin.cancel(_timerNotifId);
}

/// 진행 중 타이머 알림에 표시할 한 줄 항목.
class ActiveTimer {
  final String todoText;
  final String startTime; // 'HH:MM'
  const ActiveTimer({required this.todoText, required this.startTime});
}
