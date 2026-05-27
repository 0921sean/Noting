import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz_local;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'services/notification_service.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 세로 모드 고정 (가로 회전 비활성화)
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Supabase 초기화
  await Supabase.initialize(
    url: kSupabaseUrl,
    anonKey: kSupabaseAnonKey,
  );

  if (!kIsWeb) {
    // Timezone init — getLocation throws for unknown IDs; fall back to UTC
    tz.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz_local.setLocalLocation(tz_local.getLocation(tzName));
    } catch (_) {
      tz_local.setLocalLocation(tz_local.getLocation('UTC'));
    }

    // Notification init
    await NotificationService.instance.initialize();
  }

  final prefs = await SharedPreferences.getInstance();
  final permissionAsked = prefs.getBool('permission_asked') ?? false;
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;

  final launchNoteId = kIsWeb
      ? null
      : await NotificationService.instance.getLaunchNoteId();

  final isLoggedIn =
      Supabase.instance.client.auth.currentSession != null;

  runApp(NotingApp(
    permissionAsked: permissionAsked,
    onboardingDone: onboardingDone,
    launchNoteId: launchNoteId,
    isLoggedIn: isLoggedIn,
  ));
}

class NotingApp extends StatelessWidget {
  final bool permissionAsked;
  final bool onboardingDone;
  final bool isLoggedIn;
  final int? launchNoteId;

  const NotingApp({
    super.key,
    required this.permissionAsked,
    required this.onboardingDone,
    required this.isLoggedIn,
    this.launchNoteId,
  });

  @override
  Widget build(BuildContext context) {
    Widget home;
    if (!isLoggedIn) {
      home = const AuthScreen();
    } else if (!onboardingDone) {
      home = const OnboardingScreen();
    } else {
      home = _HomeWrapper(
        permissionAsked: permissionAsked,
        launchNoteId: launchNoteId,
      );
    }

    return MaterialApp(
      title: 'Noting',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
      themeMode: ThemeMode.system,
      home: home,
    );
  }

  ThemeData _lightTheme() {
    const surface = Color(0xFFFAF7F2);
    const primary = Color(0xFF7C5C3E);
    const onSurface = Color(0xFF2C1F14);

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        surface: surface,
        primary: primary,
        onPrimary: Color(0xFFFFFDF9),
        secondary: Color(0xFFB5896A),
        onSecondary: Color(0xFFFFFDF9),
        onSurface: onSurface,
        outline: Color(0xFFD4C4B0),
        error: Color(0xFFB85C38),
        onError: Color(0xFFFFFDF9),
      ),
      scaffoldBackgroundColor: surface,
      dividerColor: const Color(0xFFE8DDD0),
      splashColor: const Color(0x147C5C3E),
      highlightColor: const Color(0x0A7C5C3E),
    );
  }

  ThemeData _darkTheme() {
    const surface = Color(0xFF1C1712);
    const primary = Color(0xFFC8956C);
    const onSurface = Color(0xFFF0E8DE);

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        surface: surface,
        primary: primary,
        onPrimary: Color(0xFF1C1712),
        secondary: Color(0xFF9A7055),
        onSecondary: Color(0xFFF0E8DE),
        onSurface: onSurface,
        outline: Color(0xFF4A3D32),
        error: Color(0xFFCF7A5A),
        onError: Color(0xFF1C1712),
      ),
      scaffoldBackgroundColor: surface,
      dividerColor: const Color(0xFF3A2E24),
      splashColor: const Color(0x14C8956C),
      highlightColor: const Color(0x0AC8956C),
    );
  }
}

class _HomeWrapper extends StatefulWidget {
  final bool permissionAsked;
  final int? launchNoteId;

  const _HomeWrapper({
    required this.permissionAsked,
    this.launchNoteId,
  });

  @override
  State<_HomeWrapper> createState() => _HomeWrapperState();
}

class _HomeWrapperState extends State<_HomeWrapper> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && !widget.permissionAsked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _askPermission();
      });
    }
  }

  Future<void> _askPermission() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('알림 허용할게?'),
        content: const Text(
          '예전에 쓴 메모를 가끔 다시 보내줄게.\n매일 한 번, 너가 설정한 시간에.',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('permission_asked', true);
            },
            child: Text(
              '나중에',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('permission_asked', true);
              await NotificationService.instance.requestPermission();
            },
            child: const Text('허용'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HomeScreen(initialNoteId: widget.launchNoteId);
  }
}
