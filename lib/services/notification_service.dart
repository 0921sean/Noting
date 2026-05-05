import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import '../database/database_helper.dart';

// Callback type for when user taps a notification while app is running
typedef NotificationTapCallback = void Function(int noteId);

class NotificationService {
  static final NotificationService instance = NotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();

  NotificationTapCallback? onNotificationTap;
  bool _scheduling = false;

  NotificationService._();

  static const _channelId = 'noting_remind';
  static const _channelName = 'Noting 리마인드';
  static const _todoChannelId = 'noting_todo';
  static const _todoChannelName = 'Noting 투두';
  static const _todoNotifId = 998;
  static const _channelDesc = '예전 메모를 다시 보여줍니다';

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
    if (payload != null) {
      final noteId = int.tryParse(payload);
      if (noteId != null) onNotificationTap?.call(noteId);
    }
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

  // Schedule up to 30 daily notifications, each with a different random note.
  // Called on app open so content stays fresh.
  Future<void> scheduleReminders() async {
    if (_scheduling) return;
    _scheduling = true;
    try {
      final notes = await DatabaseHelper.instance.readRemindPool(daysOld: 7);
      if (notes.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final hour = prefs.getInt('notif_hour') ?? 9;
      final minute = prefs.getInt('notif_minute') ?? 0;

      await _plugin.cancelAll();

      final shuffled = List.of(notes)..shuffle(Random());
      final count = shuffled.length.clamp(1, 30);
      final now = tz.TZDateTime.now(tz.local);

      for (int i = 0; i < count; i++) {
        final note = shuffled[i % shuffled.length];
        final preview = note.content.length > 120
            ? '${note.content.substring(0, 120)}...'
            : note.content;

        // Start from tomorrow (day 1), each subsequent day +1
        final scheduled = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day,
          hour,
          minute,
        ).add(Duration(days: i + 1));

        try {
          await _plugin.zonedSchedule(
            i,
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
          // exactAllowWhileIdle may be restricted on this device; skip slot
        }
      }
    } finally {
      _scheduling = false;
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  /// 오늘 미완료 투두가 있으면 21:00에 알림 예약. 없으면 취소.
  Future<void> scheduleTodoReminder(bool hasIncomplete) async {
    await _plugin.cancel(_todoNotifId);
    if (!hasIncomplete) return;

    final now = tz.TZDateTime.now(tz.local);
    final reminderTime =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, 21, 0);
    if (reminderTime.isBefore(now)) return;

    try {
      await _plugin.zonedSchedule(
        _todoNotifId,
        '오늘 할 일 어때? 🤔',
        '아직 완료 못한 할 일이 있어',
        reminderTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _todoChannelId,
            _todoChannelName,
            channelDescription: '오늘 완료 못한 할 일 알림',
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
}
