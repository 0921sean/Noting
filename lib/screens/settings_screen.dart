import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/database_helper.dart';
import '../services/supabase_service.dart';
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
  bool _migrating = false;

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

  // ─── 기기 이전 ────────────────────────────────────────────────────────────────
  Future<void> _migrateLocalToCloud() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('이전 데이터 업로드',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text(
          '이 기기의 기존 메모·투두·시간 기록을 클라우드에 올려요.\n처음 로그인한 기기에서 한 번만 하면 돼요.',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
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
            child: Text('업로드',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _migrating = true);
    try {
      final notes = await DatabaseHelper.instance.readAllNotes();
      final todos = await DatabaseHelper.instance.readAllTodos();
      for (final n in notes) {
        await SupabaseService.importNote(n.toMap());
      }
      for (final t in todos) {
        await SupabaseService.importTodo(t.toMap());
      }

      // 시간 기록 마이그레이션
      int timeRecordCount = 0;
      final localTimeRecords =
          await DatabaseHelper.instance.readAllTimeRecordsRaw();
      if (localTimeRecords.isNotEmpty) {
        final cloudTodos = await SupabaseService.readAllTodos();
        final todoMap = <String, int>{};
        for (final t in cloudTodos) {
          if (t.id != null) todoMap['${t.text}|${t.date}'] = t.id!;
        }
        for (final row in localTimeRecords) {
          final key = '${row['text']}|${row['date']}';
          final cloudTodoId = todoMap[key];
          if (cloudTodoId == null) continue;
          try {
            final rec = await SupabaseService.createTimeRecord(
                cloudTodoId, row['start_time'] as String);
            final endTime = row['end_time'] as String?;
            if (endTime != null && rec.id != null) {
              await SupabaseService.finishTimeRecord(rec.id!, endTime);
            }
            timeRecordCount++;
          } catch (_) {}
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            '업로드 완료 — 메모 ${notes.length}개, 투두 ${todos.length}개, 시간 기록 $timeRecordCount개'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('업로드 실패: $e'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ));
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
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
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
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

                  // ── 기기 이전 ─────────────────────────────────────────────
                  const _SectionLabel(label: '기기 이전'),
                  const SizedBox(height: 8),
                  _WarmCard(
                    children: [
                      _migrating
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                    SizedBox(width: 10),
                                    Text('업로드 중...',
                                        style: TextStyle(fontSize: 14)),
                                  ],
                                ),
                              ),
                            )
                          : _WarmTile(
                              icon: Icons.cloud_upload_outlined,
                              title: '이전 데이터 클라우드에 올리기',
                              subtitle: '이전 버전 앱을 쓰던 경우에만 필요해요',
                              onTap: _migrateLocalToCloud,
                            ),
                    ],
                  ),
                  const SizedBox(height: 28),

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
