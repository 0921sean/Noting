import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> _exportData() async {
    final notes = await DatabaseHelper.instance.readAllNotes();
    final todos = await DatabaseHelper.instance.readAllTodos();
    final payload = jsonEncode({
      'exported_at': DateTime.now().toIso8601String(),
      'notes': notes.map((n) => n.toMap()).toList(),
      'todos': todos.map((t) => t.toMap()).toList(),
    });
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('데이터가 클립보드에 복사됐어요 (노트 ${notes.length}개, 투두 ${todos.length}개)'),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _importData() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('데이터 가져오기',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            hintText: '내보낸 JSON 데이터를 붙여넣어요',
            hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
                fontSize: 13),
            filled: true,
            fillColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('취소',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5)))),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('가져오기',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final data = jsonDecode(ctrl.text) as Map<String, dynamic>;
      final notesRaw = (data['notes'] as List?) ?? [];
      final todosRaw = (data['todos'] as List?) ?? [];
      for (final n in notesRaw) {
        await DatabaseHelper.instance.importNote(n as Map<String, dynamic>);
      }
      for (final t in todosRaw) {
        await DatabaseHelper.instance.importTodo(t as Map<String, dynamic>);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('가져오기 완료 (노트 ${notesRaw.length}개, 투두 ${todosRaw.length}개)'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('가져오기 실패 — JSON 형식을 확인해요'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _reclassifyAll() async {
    setState(() => _reclassifying = true);
    final notes = await DatabaseHelper.instance.readAllNotes();
    await ClassifierService.reclassifyAll(
      notes: notes,
      onClassified: (id, category) async =>
          DatabaseHelper.instance.updateNoteCategory(id, category),
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
                  // 데이터 동기화
                  const _SectionLabel(label: '데이터 동기화'),
                  const SizedBox(height: 8),
                  _WarmCard(
                    children: [
                      _WarmTile(
                        icon: Icons.upload_outlined,
                        title: '데이터 내보내기',
                        subtitle: '클립보드에 JSON 복사 → 다른 기기에서 붙여넣기',
                        onTap: _exportData,
                      ),
                      Divider(height: 1, thickness: 0.5,
                          color: Theme.of(context).dividerColor),
                      _WarmTile(
                        icon: Icons.download_outlined,
                        title: '데이터 가져오기',
                        subtitle: '내보낸 JSON을 붙여넣어 동기화',
                        onTap: _importData,
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),

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
