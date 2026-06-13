import 'dart:math';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import '../utils/coach_mark.dart';
import '../utils/tour.dart';
import '../services/analytics_service.dart';
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
  final bool startInTodos;
  const HomeScreen({super.key, this.initialNoteId, this.startInTodos = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Note> _notes = [];
  List<String> _categories = [];
  bool _loading = true;
  bool _classifying = false;
  bool _dragging = false; // 카테고리 드래그 중 (삭제 영역 표시용)
  Note? _recallNote; // 메모 탭 진입 시 랜덤으로 띄우는 옛 메모

  // 첫 진입 코치마크 (showcaseview)
  final _addKey = GlobalKey();
  final _aiKey = GlobalKey();
  final _catKey = GlobalKey();
  bool _coachDone = true; // 기본은 '봤음'으로 두고, prefs 확인 후에만 false
  bool _coachStarted = false;

  // 투어 활성 상태 — 뒤로가기를 가로채서 설정 화면으로 복귀시킬지 결정.
  bool _tourActive = false;
  bool _tourFromSettings = false;

  late _AppMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.startInTodos ? _AppMode.todos : _AppMode.notes;
    WidgetsBinding.instance.addObserver(this);
    _loadCoachFlag();
    _loadAll().then((_) {
      _scheduleIfNeeded();
      if (widget.initialNoteId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _openNoteById(widget.initialNoteId!);
        });
      }
    });
    NotificationService.instance.onNotificationTap = _openNoteById;
    // 자정 플래너 알림 탭 시 투두 탭으로 전환
    NotificationService.instance.onPlannerReminderTap = () {
      if (!mounted) return;
      setState(() => _mode = _AppMode.todos);
    };
    // 설정 → 사용법에서 투어 재개 요청 리스닝
    TourTrigger.notifier.addListener(_onTourRequest);
  }

  // 코치마크를 본 적 없으면(_coachDone=false) 첫 진입 시 한 번 띄운다.
  Future<void> _loadCoachFlag() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _coachDone = prefs.getBool('home_coachmark_done') ?? false);
  }

  Future<void> _persistCoachDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('home_coachmark_done', true);
  }

  void _maybeStartCoach(BuildContext ctx) {
    if (_coachDone || _coachStarted || _loading || _mode != _AppMode.notes) {
      return;
    }
    _coachStarted = true;
    _persistCoachDone(); // 띄우는 순간 '봤음'으로 저장
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final keys = <GlobalKey>[
        _addKey,
        _aiKey,
        if (_categories.isNotEmpty) _catKey,
      ];
      ShowCaseWidget.of(ctx).startShowCase(keys);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.instance.onNotificationTap = null;
    NotificationService.instance.onPlannerReminderTap = null;
    TourTrigger.notifier.removeListener(_onTourRequest);
    super.dispose();
  }

  // 글로벌 투어 요청 처리. 'memo' → 메모 탭에서 코치마크. 'todo' → 투두 모드로
  // 전환만 (TodoScreen이 자체적으로 자기 투어를 띄움).
  BuildContext? _showcaseCtx; // ShowCaseWidget의 builder ctx — 외부 트리거용

  void _onTourRequest() {
    final req = TourTrigger.notifier.value;
    if (req == null || !mounted) return;
    setState(() {
      _tourActive = true;
      _tourFromSettings = req.fromSettings;
      if (req.kind == 'memo') _mode = _AppMode.notes;
      if (req.kind == 'todo') _mode = _AppMode.todos;
    });
    if (req.kind == 'memo') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _showcaseCtx;
        if (ctx == null) return;
        final keys = <GlobalKey>[
          _addKey,
          _aiKey,
          if (_categories.isNotEmpty) _catKey,
        ];
        ShowCaseWidget.of(ctx).startShowCase(keys);
        // 같은 요청이 다시 처리되지 않도록 즉시 리셋
        TourTrigger.notifier.value = null;
      });
    }
    // 'todo'는 TodoScreen이 자기 listener로 투어 시작하면서 값을 리셋.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAll();
      // 백그라운드 → 포그라운드 복귀도 app_open으로 기록 (출처 구분 어려워 organic)
      AnalyticsService.appOpen('resume');
    }
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
      _shuffleRecall();
    });
    _checkSwipeHint();
    _scheduleIfNeeded();
  }

  // 메모 탭에서 보여줄 랜덤 옛 메모를 뽑는다.
  // 카테고리로 분류되어 카드에 묻혀버린 메모들을 다시 마주치게 하는 역할.
  void _shuffleRecall() {
    if (_notes.isEmpty) {
      _recallNote = null;
      return;
    }
    final rng = Random();
    Note pick = _notes[rng.nextInt(_notes.length)];
    // 가능하면 직전에 뜬 거랑 다른 걸로
    if (_notes.length > 1 && _recallNote != null) {
      for (int i = 0; i < 4 && pick.id == _recallNote!.id; i++) {
        pick = _notes[rng.nextInt(_notes.length)];
      }
    }
    _recallNote = pick;
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
  // 미분류 메모만 대상으로, 기존 카테고리는 유지하고 필요하면 새 카테고리를 추가한다.
  Future<void> _autoClassify() async {
    final uncategorized = _notes.where((n) => n.category == null).toList();
    if (uncategorized.isEmpty) {
      _showSnack('분류할 미분류 메모가 없어요');
      return;
    }
    setState(() => _classifying = true);
    try {
      final result = await ClassifierService.autoGenerateCategories(
        uncategorized,
        existing: _categories,
      );
      AnalyticsService.aiClassifyUsed(
        success: result != null,
        notesCount: uncategorized.length,
      );
      if (result == null || !mounted) return;

      // 새 카테고리만 추가 (기존 카테고리는 보존, 삭제 없음)
      for (final cat in result.categories) {
        await CategoryService.add(cat);
      }
      for (final entry in result.assignments.entries) {
        if (result.categories.contains(entry.value)) {
          await SupabaseService.updateNoteCategory(entry.key, entry.value);
        }
      }
      await _loadAll();
      if (!mounted) return;
      _showSnack('미분류 메모 ${uncategorized.length}개를 분류했어요');
    } on ClassifierException catch (e) {
      if (!mounted) return;
      _showSnack(e.message);
    } catch (_) {
      if (!mounted) return;
      _showSnack('자동분류 실패. 다시 시도해봐요.');
    } finally {
      if (mounted) setState(() => _classifying = false);
    }
  }

  // ─── 카테고리 직접 생성 ────────────────────────────────────────────────────────
  Future<void> _addCategory() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _AddCategoryDialog(),
    );
    if (name == null || name.isEmpty) return;
    if (name == '전체' || name == '미분류') {
      _showSnack('그 이름은 사용할 수 없어요');
      return;
    }
    if (_categories.contains(name)) {
      _showSnack('이미 있는 카테고리예요');
      return;
    }
    await CategoryService.add(name);
    await _loadAll();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─── 카테고리 순서 변경 / 삭제 ─────────────────────────────────────────────────
  Future<void> _reorderCategory(int from, int to) async {
    if (from < 0 || from >= _categories.length) return;
    setState(() {
      final item = _categories.removeAt(from);
      final dest = (from < to ? to - 1 : to).clamp(0, _categories.length);
      _categories.insert(dest, item);
      _dragging = false;
    });
    await CategoryService.setAll(_categories);
  }

  Future<void> _confirmDeleteCategory(int index) async {
    setState(() => _dragging = false);
    if (index < 0 || index >= _categories.length) return;
    final name = _categories[index];
    final count = _notes.where((n) => n.category == name).length;
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("'$name' 삭제",
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
          count > 0
              ? '이 카테고리의 메모 $count개는 미분류로 옮겨져요.'
              : '이 카테고리를 삭제할까요?',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('취소',
                style: TextStyle(color: cs.onSurface.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('삭제', style: TextStyle(color: cs.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // 해당 카테고리 메모를 미분류로
    for (final n in _notes.where((n) => n.category == name)) {
      if (n.id != null) await SupabaseService.updateNoteCategory(n.id!, null);
    }
    await CategoryService.remove(name);
    await _loadAll();
    _showSnack(count > 0 ? "'$name' 삭제 · 메모 $count개는 미분류로" : "'$name' 삭제됨");
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
    return ShowCaseWidget(
      // disableBarrierInteraction은 false 유지 — Showcase별 onBarrierClick에서
      // 다음 단계로 진행하게 처리.
      onFinish: _onTourFinished,
      onDismiss: (_) => _onTourFinished(),
      builder: (ctx) {
        _showcaseCtx = ctx;
        _maybeStartCoach(ctx);
        return _buildScaffold();
      },
    );
  }

  void _onTourFinished() {
    if (!mounted) return;
    setState(() => _tourActive = false);
  }

  Widget _buildScaffold() {
    return PopScope(
      canPop: !_tourActive,
      onPopInvoked: (didPop) {
        if (didPop) return;
        // 투어 진행 중 뒤로가기 → 투어 종료 + 설정에서 시작된 경우 설정 복귀
        final ctx = _showcaseCtx;
        if (ctx != null) {
          try {
            ShowCaseWidget.of(ctx).dismiss();
          } catch (_) {}
        }
        setState(() => _tourActive = false);
        if (_tourFromSettings) {
          _tourFromSettings = false;
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SettingsScreen()));
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              _buildModeToggle(),
              Expanded(child: _buildContent()),
            ],
          ),
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
            buildCoachMark(
              context: context,
              key: _addKey,
              title: '카테고리 추가',
              description: '여기를 눌러 카테고리를 직접 만들 수 있어요.',
              targetShapeBorder: const CircleBorder(),
              targetPadding: const EdgeInsets.all(4),
              child: IconButton(
                icon: Icon(Icons.add_rounded,
                    size: 24, color: cs.onSurface.withOpacity(0.5)),
                tooltip: '카테고리 추가',
                onPressed: _addCategory,
              ),
            ),
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
                : buildCoachMark(
                    context: context,
                    key: _aiKey,
                    title: 'AI 자동분류',
                    description: '미분류 메모를 AI가 알아서 카테고리에 정리해줘요.',
                    targetShapeBorder: const CircleBorder(),
                    targetPadding: const EdgeInsets.all(4),
                    child: IconButton(
                      icon: Icon(Icons.auto_awesome_outlined,
                          size: 20, color: cs.onSurface.withOpacity(0.5)),
                      tooltip: 'AI 자동분류',
                      onPressed: _autoClassify,
                    ),
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
            catIndex: e.key,
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
            Text('＋ 버튼으로 카테고리를 만들거나\n카테고리를 탭해서 메모를 추가해봐요',
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

    final grid = GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200, // 너비에 따라 열 수 자동 (세로 2열, 가로 4열~)
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.35,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _buildCategoryCell(items[i]),
    );

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: _dragging
              ? _buildDeleteZone()
              : const SizedBox(width: double.infinity),
        ),
        if (_recallNote != null && !_dragging) _buildRecallCard(),
        Expanded(child: grid),
      ],
    );
  }

  // ─── 랜덤 회상 카드 (메모 탭 상단) ─────────────────────────────────────────────
  Widget _buildRecallCard() {
    final cs = Theme.of(context).colorScheme;
    final note = _recallNote!;
    final preview = note.content.length > 80
        ? '${note.content.substring(0, 80).replaceAll('\n', ' ')}…'
        : note.content.replaceAll('\n', ' ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: GestureDetector(
        onTap: () => _openNoteById(note.id!),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.primary.withOpacity(0.18), width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('💭',
                  style: TextStyle(
                      fontSize: 18, color: cs.onSurface.withOpacity(0.75))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('기억나?',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.primary.withOpacity(0.75),
                          letterSpacing: 0.2,
                        )),
                    const SizedBox(height: 3),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: cs.onSurface.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh_rounded,
                    size: 18, color: cs.onSurface.withOpacity(0.45)),
                tooltip: '다른 메모 보기',
                onPressed: () => setState(_shuffleRecall),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 카테고리 카드를 드래그(순서변경/삭제) 가능하게 감싼다. 전체/미분류는 고정.
  Widget _buildCategoryCell(_CategoryItem item) {
    final card = _buildCategoryCard(item);
    final idx = item.catIndex;
    if (idx == null) return card;

    Widget cell = LongPressDraggable<int>(
      data: idx,
      onDragStarted: () {
        HapticFeedback.mediumImpact();
        setState(() => _dragging = true);
      },
      onDragEnd: (_) => setState(() => _dragging = false),
      onDraggableCanceled: (_, __) => setState(() => _dragging = false),
      feedback: _dragFeedback(item),
      childWhenDragging: Opacity(opacity: 0.25, child: card),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != idx,
        onAcceptWithDetails: (d) => _reorderCategory(d.data, idx),
        builder: (_, candidate, __) {
          final cs = Theme.of(context).colorScheme;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: candidate.isNotEmpty
                  ? Border.all(color: cs.primary, width: 2)
                  : Border.all(color: Colors.transparent, width: 2),
            ),
            child: card,
          );
        },
      ),
    );

    // 첫 번째 사용자 카테고리 카드에 코치마크를 단다.
    if (idx == 0) {
      cell = buildCoachMark(
        context: context,
        key: _catKey,
        title: '카테고리 정리',
        description: '카드를 길게 누르면 드래그로 순서를 바꾸거나,\n위에 나타나는 영역에 놓아 삭제할 수 있어요.',
        targetShapeBorder: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        child: cell,
      );
    }
    return cell;
  }

  Widget _dragFeedback(_CategoryItem item) {
    // 그리드 셀 너비를 SliverGridDelegateWithMaxCrossAxisExtent와 동일하게 계산
    final avail = MediaQuery.of(context).size.width - 40; // 좌우 패딩 20+20
    final count = (avail / (200 + 12)).ceil().clamp(1, 99);
    final w = (avail - (count - 1) * 12) / count;
    return Material(
      color: Colors.transparent,
      child: Transform.rotate(
        angle: -0.02,
        child: SizedBox(
          width: w,
          height: w / 1.35,
          child: DefaultTextStyle(
            style: const TextStyle(),
            child: Opacity(opacity: 0.95, child: _buildCategoryCard(item)),
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteZone() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (d) => _confirmDeleteCategory(d.data),
        builder: (_, candidate, __) {
          final active = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 52,
            decoration: BoxDecoration(
              color: cs.error.withOpacity(active ? 0.18 : 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: cs.error.withOpacity(active ? 0.7 : 0.25),
                width: active ? 1.5 : 1,
              ),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline,
                      size: 20, color: cs.error.withOpacity(0.85)),
                  const SizedBox(width: 8),
                  Text(
                    active ? '놓으면 삭제' : '여기로 끌어서 삭제',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.error.withOpacity(0.9),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
  final int? catIndex; // _categories 내 인덱스 (사용자 카테고리만, 드래그용)

  const _CategoryItem({
    required this.label,
    required this.category,
    required this.count,
    this.color,
    this.isUncategorized = false,
    this.catIndex,
  });
}

// 컨트롤러를 자체 소유/해제해서 dispose 레이스를 방지하는 카테고리 추가 다이얼로그.
class _AddCategoryDialog extends StatefulWidget {
  const _AddCategoryDialog();

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('새 카테고리',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 20,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: '카테고리 이름',
          counterText: '',
          hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.3)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.primary),
          ),
        ),
        style: const TextStyle(fontSize: 15),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('취소',
              style: TextStyle(color: cs.onSurface.withOpacity(0.5))),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('추가', style: TextStyle(color: cs.primary)),
        ),
      ],
    );
  }
}
