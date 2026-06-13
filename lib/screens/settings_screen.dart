import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/analytics_service.dart';
import '../services/category_service.dart';
import '../services/notification_service.dart';
import 'auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _hour = 9;
  int _minute = 0;
  bool _loading = true;

  String get _userEmail =>
      Supabase.instance.client.auth.currentUser?.email ?? '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _hour = prefs.getInt('notif_hour') ?? 9;
      _minute = prefs.getInt('notif_minute') ?? 0;
      _loading = false;
    });
  }

  // ─── 알림 ─────────────────────────────────────────────────────────────────
  Future<void> _pickTime() async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
      helpText: '알림 시간 선택',
    );
    if (picked == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_hour', picked.hour);
    await prefs.setInt('notif_minute', picked.minute);
    if (!mounted) return;
    setState(() {
      _hour = picked.hour;
      _minute = picked.minute;
    });
    await NotificationService.instance.scheduleReminders();
    if (mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text('${_z(_hour)}:${_z(_minute)}에 알림이 올 거야'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ─── 로그아웃 ─────────────────────────────────────────────────────────────
  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('로그아웃',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text('로그아웃할까요?', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('취소',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('로그아웃',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await Supabase.instance.client.auth.signOut();
    await AnalyticsService.reset();
    await CategoryService.resetMigrationFlag();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  // ─── 계정 삭제 ────────────────────────────────────────────────────────────
  // App Store/Play Store 정책상 앱 내 계정 삭제 기능 필수.
  // 확인 다이얼로그 두 단계(텍스트 일치) 후 Edge Function 호출 → 로그아웃.
  static const _protectedEmails = {'0921sean@gmail.com'};

  Future<void> _deleteAccount() async {
    final cs = Theme.of(context).colorScheme;
    // 본인 운영 계정 보호 (서버에도 동일 체크 있음)
    final email =
        Supabase.instance.client.auth.currentUser?.email?.toLowerCase();
    if (email != null && _protectedEmails.contains(email)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('이 계정은 삭제할 수 없어요'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ));
      return;
    }
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: cs.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('계정 삭제',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '계정과 모든 메모·투두·시간 기록이 영구 삭제돼요.\n'
                '되돌릴 수 없어요.\n\n'
                '진행하려면 아래에 "삭제"라고 입력해주세요.',
                style: TextStyle(fontSize: 13, height: 1.55),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: '삭제',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('취소',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.5))),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim() == '삭제'),
              child: Text('영구 삭제', style: TextStyle(color: cs.error)),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;

    // 비동기 작업 전에 navigator/messenger 캡처 — 위젯 dispose 중 context 참조
    // 시 발생하는 _dependents.isEmpty 어설션을 회피.
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final overlayColors = Theme.of(context).colorScheme;

    // 전체 화면을 덮는 로딩 오버레이 — HomeScreen/SettingsScreen 위에서
    // 시각적으로 모든 teardown 깜빡임을 가린다.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: overlayColors.surface,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: overlayColors.surface,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: overlayColors.primary),
                const SizedBox(height: 16),
                Text('계정 삭제 중...',
                    style: TextStyle(
                        fontSize: 14,
                        color: overlayColors.onSurface.withOpacity(0.6))),
              ],
            ),
          ),
        ),
      ),
    );

    String? errorMessage;
    try {
      final resp =
          await Supabase.instance.client.functions.invoke('delete_account');
      if (resp.status != 200) {
        errorMessage = '계정 삭제 실패: ${resp.data?['error'] ?? resp.status}';
      }
    } catch (e) {
      errorMessage = '계정 삭제 실패: $e';
    }

    if (errorMessage != null) {
      // 실패 — 로딩 오버레이 닫고 스낵바
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text(errorMessage),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ));
      return;
    }

    // 성공 — 로딩 오버레이가 화면을 덮은 상태에서 한 번에 AuthScreen으로 교체.
    // pushAndRemoveUntil이 로딩 다이얼로그까지 같이 제거하므로 사용자는
    // 로딩 → 로그인 화면으로 깔끔히 전환되는 것만 본다.
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
    unawaited(Supabase.instance.client.auth.signOut());
    unawaited(AnalyticsService.reset());
    unawaited(CategoryService.resetMigrationFlag());
  }

  String _z(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('설정',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            )),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  // ── 계정 ──────────────────────────────────────────────────
                  const _SectionLabel(label: '계정'),
                  const SizedBox(height: 8),
                  _WarmCard(
                    children: [
                      // 이메일 표시
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Icon(Icons.person_outline,
                              size: 20,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.7)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _userEmail,
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.6),
                              ),
                            ),
                          ),
                        ]),
                      ),
                      Divider(
                          height: 1,
                          thickness: 0.5,
                          color: Theme.of(context).dividerColor),
                      _WarmTile(
                        icon: Icons.logout_outlined,
                        title: '로그아웃',
                        onTap: _signOut,
                        titleColor: Theme.of(context).colorScheme.error,
                        showChevron: false,
                      ),
                      Divider(
                          height: 1,
                          thickness: 0.5,
                          color: Theme.of(context).dividerColor),
                      _WarmTile(
                        icon: Icons.delete_forever_outlined,
                        title: '계정 삭제',
                        subtitle: '계정과 모든 데이터를 영구 삭제',
                        onTap: _deleteAccount,
                        titleColor: Theme.of(context).colorScheme.error,
                        showChevron: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // ── 리마인드 (네이티브만) ─────────────────────────────────
                  if (!kIsWeb) ...[
                    const _SectionLabel(label: '리마인드'),
                    const SizedBox(height: 8),
                    _WarmCard(
                      children: [
                        _WarmTile(
                          icon: Icons.access_time_outlined,
                          title: '${_z(_hour)}:${_z(_minute)}에 예전 메모를 보내줘요',
                          subtitle: '탭해서 시간 변경',
                          onTap: _pickTime,
                          showChevron: false,
                        ),
                        Divider(
                            height: 1,
                            thickness: 0.5,
                            color: Theme.of(context).dividerColor),
                        _WarmTile(
                          icon: Icons.notifications_outlined,
                          title: '알림 권한 확인',
                          subtitle: '알림이 안 오면 여기서 확인해요',
                          onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final ok = await NotificationService.instance
                                .requestPermission();
                            if (mounted) {
                              messenger.showSnackBar(SnackBar(
                                content: Text(ok
                                    ? '알림 권한이 있어요 ✓'
                                    : '설정에서 알림을 허용해줘요'),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ));
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                  ],

                  // ── 정보 ──────────────────────────────────────────────────
                  const _SectionLabel(label: '정보'),
                  const SizedBox(height: 8),
                  const _WarmCard(
                    children: [
                      _WarmTile(
                        icon: Icons.auto_awesome_outlined,
                        title: 'Noting',
                        subtitle: '생각을 기록하고, 잊을 때쯤 다시 만나자',
                        showChevron: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 2),
        child: Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
              letterSpacing: 0.8,
            )),
      );
}

class _WarmCard extends StatelessWidget {
  final List<Widget> children;
  const _WarmCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        child: Column(children: children),
      );
}

class _WarmTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  final bool showChevron;

  const _WarmTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(icon,
                size: 20,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withOpacity(0.7)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: titleColor ??
                              Theme.of(context).colorScheme.onSurface,
                        )),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.45),
                          )),
                    ],
                  ]),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null && showChevron)
              Icon(Icons.chevron_right,
                  size: 18,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.25)),
          ]),
        ),
      );
}
