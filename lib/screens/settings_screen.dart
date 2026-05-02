import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../services/classifier_service.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _hour = 9;
  int _minute = 0;
  bool _loading = true;
  bool _reclassifying = false;

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

  Future<void> _reclassifyAll() async {
    setState(() => _reclassifying = true);
    final notes = await DatabaseHelper.instance.readAllNotes();
    await ClassifierService.reclassifyAll(
      notes: notes,
      onClassified: (id, category) async =>
          DatabaseHelper.instance.updateCategory(id, category),
    );
    if (!mounted) return;
    setState(() => _reclassifying = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${notes.length}개 메모 분류 완료'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

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
      messenger.showSnackBar(
        SnackBar(
          content: Text('${_z(_hour)}:${_z(_minute)} 에 알림이 올 거야'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
          icon: Icon(Icons.arrow_back_ios_new, size: 18,
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  // AI 분류
                  const _SectionLabel(label: 'AI 분류'),
                  const SizedBox(height: 8),
                  _WarmCard(
                    children: [
                      _reclassifying
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(width: 10),
                                    Text('분류 중...', style: TextStyle(fontSize: 14)),
                                  ],
                                ),
                              ),
                            )
                          : _WarmTile(
                              icon: Icons.auto_awesome_outlined,
                              title: '전체 메모 재분류',
                              onTap: _reclassifyAll,
                            ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // 알림 (네이티브만)
                  if (!kIsWeb) ...[
                    const _SectionLabel(label: '알림'),
                    const SizedBox(height: 8),
                    _WarmCard(
                      children: [
                        _WarmTile(
                          icon: Icons.access_time_outlined,
                          title: '매일 알림 시간',
                          trailing: Text('${_z(_hour)}:${_z(_minute)}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.primary,
                              )),
                          onTap: _pickTime,
                        ),
                        Divider(height: 1, thickness: 0.5,
                            color: Theme.of(context).dividerColor),
                        _WarmTile(
                          icon: Icons.notifications_outlined,
                          title: '알림 권한 확인',
                          onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final ok = await NotificationService.instance.requestPermission();
                            if (mounted) {
                              messenger.showSnackBar(SnackBar(
                                content: Text(ok ? '알림 권한이 있어요 ✓' : '설정에서 알림을 허용해줘요'),
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

                  // 정보
                  const _SectionLabel(label: '정보'),
                  const SizedBox(height: 8),
                  const _WarmCard(
                    children: [
                      _WarmTile(
                        icon: Icons.auto_awesome_outlined,
                        title: 'Noting',
                        subtitle: '생각을 기록하고, 잊을 때쯤 다시 만나자',
                      ),
                    ],
                  ),
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
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
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
  const _WarmTile({required this.icon, required this.title, this.subtitle, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(icon, size: 20,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.7)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    )),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                      )),
                ],
              ]),
            ),
            if (trailing != null) trailing!
            else if (onTap != null)
              Icon(Icons.chevron_right, size: 18,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.25)),
          ]),
        ),
      );
}
