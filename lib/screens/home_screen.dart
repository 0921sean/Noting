import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import '../models/note.dart';
import '../services/category_service.dart';
import '../services/classifier_service.dart';
import '../services/notification_service.dart';
import 'category_detail_screen.dart';
import 'note_detail_screen.dart';
import 'settings_screen.dart';
import 'todo_screen.dart';

enum _AppMode { notes, todos }

// 카테고리 카드 색상
const _cardColors = [
  Color(0xFFFA7D7C),
  Color(0xFFF9AE7D),
  Color(0xFF7DF97E),
  Color(0xFF80E0FA),
  Color(0xFF7D7DFA),
  Color(0xFFCA7CFA),
  Color(0xFF7FCD7F),
  Color(0xFF80BDCD),
];

class HomeScreen extends StatefulWidget {
  final int? initialNoteId;
  const HomeScreen({super.key, this.initialNoteId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Note> _notes = [];
  List<String> _categories = [];
  bool _loading = true;
  bool _classifying = false;

  _AppMode _mode = _AppMode.notes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAll().then((_) {
      _scheduleIfNeeded();
      if (widget.initialNoteId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openNoteById(widget.initialNoteId!);
        });
      }
    });
    NotificationService.instance.onNotificationTap = _openNoteById;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.instance.onNotificationTap = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadAll();
  }

  Future<void> _loadAll() async {
    final results = await Future.wait([
      SupabaseService.readAllNotes(),
      CategoryService.getAll(),
    ]);
    if (!mounted) return;
    setState(() {
      _notes = results[0] as List<Note>;
      _categories = results[1] as List<String>;
      _loading = false;
    });
    _checkSwipeHint();
    _scheduleIfNeeded();
  }

  Future<void> _checkSwipeHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('swipe_hint_shown') ?? false) return;
    await prefs.setBool('swipe_hint_shown', true);
  }

  Future<void> _scheduleIfNeeded() async {
    if (!kIsWeb && _notes.isNotEmpty) {
      await NotificationService.instance.scheduleReminders();
    }
  }

  // ─── 자동분류 ────────────────────────────────────────────────────────────────
  Future<void> _autoClassify() async {
    if (_notes.isEmpty) return;
    setState(() => _classifying = true);
    try {
      final result = await ClassifierService.autoGenerateCategories(_notes);
      if (result == null || !mounted) return;

      await _updateCategories(result.categories);
      for (final entry in result.assignments.entries) {
        if (result.categories.contains(entry.value)) {
          await SupabaseService.updateNoteCategory(entry.key, entry.value);
        }
      }
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.categories.length}개 카테고리로 분류 완료'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('자동분류 실패. 다시 시도해봐요.')),
      );
    } finally {
      if (mounted) setState(() => _classifying = false);
    }
  }

  Future<void> _updateCategories(List<String> newCats) async {
    for (final cat in newCats) {
      await CategoryService.add(cat);
    }
    final current = await CategoryService.getAll();
    for (final old in List.from(current)) {
      if (!newCats.contains(old)) await CategoryService.remove(old);
    }
  }

  // ─── 네비게이션 ──────────────────────────────────────────────────────────────
  void _openNoteById(int noteId) async {
    final note = await SupabaseService.readNote(noteId);
    if (note == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NoteDetailScreen(
        note: note,
        onDeleted: _loadAll,
        onEdited: (updated) => setState(() {
          final idx = _notes.indexWhere((n) => n.id == updated.id);
          if (idx != -1) _notes[idx] = updated;
        }),
      ),
    ));
  }

  void _openCategory(String? category) async {
    // 해당 카테고리 노트 필터
    final notes = category == '전체'
        ? _notes
        : category == null
            ? _notes.where((n) => n.category == null).toList()
            : _notes.where((n) => n.category == category).toList();

    await Navigator.of(context).push<List<Note>>(
      MaterialPageRoute(
        builder: (_) => CategoryDetailScreen(
          category: category == '전체' ? '전체' : category,
          initialNotes: notes,
        ),
      ),
    );
    // 돌아오면 전체 재로딩
    _loadAll();
  }

  void _setMode(_AppMode mode) => setState(() => _mode = mode);

  // ─── 빌드 ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            _buildModeToggle(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_mode == _AppMode.todos) return const TodoScreen();
    if (_loading) return const Center(child: CircularProgressIndicator());
    return _buildCategoryGrid();
  }

  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          _modeTab('메모', _AppMode.notes),
          _modeTab('투두', _AppMode.todos),
        ]),
      ),
    );
  }

  Widget _modeTab(String label, _AppMode mode) {
    final selected = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _setMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.surface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
            boxShadow: selected
                ? [BoxShadow(
                    color: Colors.black.withOpacity(0.07),
                    blurRadius: 4,
                    offset: const Offset(0, 1))]
                : null,
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                )),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Noting',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: cs.onSurface,
                  )),
              Text('${_notes.length}개의 생각',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.55),
                  )),
            ],
          ),
          const Spacer(),
          if (_mode == _AppMode.notes)
            _classifying
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.primary),
                    ),
                  )
                : IconButton(
                    icon: Icon(Icons.auto_awesome_outlined,
                        size: 20, color: cs.onSurface.withOpacity(0.5)),
                    tooltip: 'AI 자동분류',
                    onPressed: _autoClassify,
                  ),
          IconButton(
            icon: Icon(Icons.settings_outlined,
                size: 22, color: cs.onSurface.withOpacity(0.5)),
            onPressed: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
                  .then((_) => _loadAll());
            },
          ),
        ],
      ),
    );
  }

  // ─── 카테고리 카드 그리드 ─────────────────────────────────────────────────────
  Widget _buildCategoryGrid() {
    // 각 카테고리별 노트 수 계산
    final counts = <String?, int>{};
    counts['전체'] = _notes.length;
    counts[null] = _notes.where((n) => n.category == null).length; // 미분류
    for (final cat in _categories) {
      counts[cat] = _notes.where((n) => n.category == cat).length;
    }

    final items = <_CategoryItem>[
      _CategoryItem(label: '전체', category: '전체', count: counts['전체']!),
      ..._categories.asMap().entries.map((e) => _CategoryItem(
            label: e.value,
            category: e.value,
            count: counts[e.value] ?? 0,
            color: _cardColors[e.key % _cardColors.length],
          )),
      _CategoryItem(
          label: '미분류',
          category: null,
          count: counts[null]!,
          isUncategorized: true),
    ];

    if (items.length <= 1 && _notes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('✦',
                style: TextStyle(
                  fontSize: 36,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
                )),
            const SizedBox(height: 20),
            Text('아직 메모가 없어',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
                )),
            const SizedBox(height: 6),
            Text('✨ 버튼으로 카테고리를 만들거나\n카테고리를 탭해서 메모를 추가해봐요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
                )),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.35,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildCategoryCard(items[i]),
    );
  }

  Widget _buildCategoryCard(_CategoryItem item) {
    final cs = Theme.of(context).colorScheme;
    final isAll = item.category == '전체';
    final color = isAll
        ? cs.primary
        : item.isUncategorized
            ? cs.onSurface.withOpacity(0.25)
            : item.color ?? cs.primary;

    return GestureDetector(
      onTap: () => _openCategory(item.category),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 색상 점
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color.withOpacity(item.isUncategorized ? 0.4 : 0.8),
                shape: BoxShape.circle,
              ),
            ),
            const Spacer(),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: item.isUncategorized
                    ? cs.onSurface.withOpacity(0.4)
                    : cs.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '${item.count}개',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryItem {
  final String label;
  final String? category;
  final int count;
  final Color? color;
  final bool isUncategorized;

  const _CategoryItem({
    required this.label,
    required this.category,
    required this.count,
    this.color,
    this.isUncategorized = false,
  });
}
