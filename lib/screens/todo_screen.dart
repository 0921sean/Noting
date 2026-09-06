import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:showcaseview/showcaseview.dart';
import '../services/analytics_service.dart';
import '../services/supabase_service.dart';
import '../models/todo.dart';
import '../models/time_record.dart';
import '../services/notification_service.dart';
import '../utils/planner_colors.dart';
import '../utils/coach_mark.dart';
import '../utils/tour.dart';
import 'planner_screen.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  static const _kBase = 10000;
  static const _dayLabels = ['일', '월', '화', '수', '목', '금', '토'];

  late final PageController _pageController;
  DateTime _selectedDate = _today();
  Map<String, List<Todo>> _byDate = {};
  bool _loading = true;

  final _addController = TextEditingController();
  final _addFocus = FocusNode();
  String? _editingId; // 'date:id'
  final _editController = TextEditingController();
  final _editFocus = FocusNode();

  // 활성 TimeRecord ID (todoId → TimeRecord.id)
  final Map<int, int> _activeRecordIds = {};
  // 타이머 실제 시작 시각 (경과 시간 계산용)
  final Map<int, DateTime> _timerStartTimes = {};
  // 경과 시간 갱신 타이머
  Timer? _elapsedTicker;
  // 날짜별 시간 기록 (todoId → List<TimeRecord>)
  Map<int, List<TimeRecord>> _timeRecords = {};
  // 날짜키 → 그 날짜의 시간 기록. 날짜 전환 시 재조회 없이 즉시 표시하기 위한 캐시.
  final Map<String, Map<int, List<TimeRecord>>> _recordsByDate = {};

  // 첫 진입 코치마크
  final _addKey = GlobalKey();
  final _copyKey = GlobalKey();
  final _plannerKey = GlobalKey();
  final _timerKey = GlobalKey();
  bool _coachDone = true;
  bool _coachStarted = false;

  // ─── 날짜 유틸 ──────────────────────────────────────────────────────────────
  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime _sundayOfWeek(DateTime d) =>
      d.subtract(Duration(days: d.weekday % 7));

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get _selKey => _key(_selectedDate);
  List<Todo> get _selTodos => _byDate[_selKey] ?? [];

  // ─── 라이프사이클 ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _kBase);
    _loadCoachFlag();
    _load();
    TourTrigger.notifier.addListener(_onTourRequest);
    // listener를 늦게 등록한 경우(예: 메모 모드에서 '투두 사용법' 호출 시
    // 그제서야 마운트됨)도 트리거를 놓치지 않도록 현재 값을 한 번 확인.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && TourTrigger.notifier.value?.kind == 'todo') {
        _onTourRequest();
      }
    });
  }

  BuildContext? _lastBuildCtx;
  bool _pendingTour = false; // _load 완료 후 시작해야 할 투어 대기 플래그

  void _onTourRequest() {
    final req = TourTrigger.notifier.value;
    if (req?.kind != 'todo' || !mounted) return;
    // 데이터가 아직 안 들어왔으면 _selTodos가 비어 ▶ 키가 누락된다.
    // _load 완료 후 재시도하도록 보류.
    if (_loading) {
      _pendingTour = true;
      return;
    }
    _pendingTour = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _lastBuildCtx;
      if (ctx == null) return;
      final keys = <GlobalKey>[
        _addKey,
        _copyKey,
        _plannerKey,
        if (_selTodos.isNotEmpty) _timerKey,
      ];
      ShowCaseWidget.of(ctx).startShowCase(keys);
      // 같은 요청이 토글 시 다시 재발되지 않도록 즉시 리셋
      TourTrigger.notifier.value = null;
    });
  }

  Future<void> _loadCoachFlag() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _coachDone = prefs.getBool('todo_coachmark_done') ?? false);
  }

  Future<void> _persistCoachDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('todo_coachmark_done', true);
  }

  void _maybeStartCoach(BuildContext ctx) {
    if (_coachDone || _coachStarted || _loading) return;
    _coachStarted = true;
    _persistCoachDone();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final keys = <GlobalKey>[
        _addKey,
        _copyKey,
        _plannerKey,
        if (_selTodos.isNotEmpty) _timerKey,
      ];
      ShowCaseWidget.of(ctx).startShowCase(keys);
    });
  }

  @override
  void dispose() {
    _elapsedTicker?.cancel();
    _pageController.dispose();
    _addController.dispose();
    _addFocus.dispose();
    _editController.dispose();
    _editFocus.dispose();
    TourTrigger.notifier.removeListener(_onTourRequest);
    super.dispose();
  }

  Future<void> _load() async {
    final todos = await SupabaseService.readAllTodos();
    final map = <String, List<Todo>>{};
    for (final t in todos) {
      map.putIfAbsent(t.date, () => []).add(t);
    }
    // 오늘 날짜 기준 시간 기록 로딩
    final todayKey = _key(_today());
    final records =
        await SupabaseService.readTimeRecordsForDate(todayKey);
    if (!mounted) return;
    // 앱 재시작 시 종료 시간 없는 기록 → 자동으로 진행 중 상태 복원
    for (final entry in records.entries) {
      final activeRecord = entry.value
          .where((r) => r.endTime == null && r.id != null)
          .firstOrNull;
      if (activeRecord != null) {
        _activeRecordIds[entry.key] = activeRecord.id!;
        _elapsedTicker ??= Timer.periodic(const Duration(seconds: 30), (_) {
          if (!mounted) return;
          if (_activeRecordIds.isNotEmpty) {
            setState(() {});
            _refreshTimerBanner();
          }
        });
      }
    }
    _recordsByDate[todayKey] = records;
    setState(() {
      _byDate = map;
      _timeRecords = records;
      _loading = false;
    });
    _refreshNudge();
    _refreshTimerBanner();
    // 로딩 중에 들어온 투어 요청 처리
    if (_pendingTour) _onTourRequest();
  }

  Future<void> _loadTimeRecordsForDate(String dateKey) async {
    // 캐시가 있으면 즉시 표시(대기 0) → 네트워크는 백그라운드로 최신값만 반영.
    final cached = _recordsByDate[dateKey];
    if (cached != null) {
      setState(() => _timeRecords = cached);
    }
    final records =
        await SupabaseService.readTimeRecordsForDate(dateKey);
    if (!mounted) return;
    _recordsByDate[dateKey] = records;
    // 그새 다른 날짜로 넘어갔으면 화면 반영은 생략(캐시에는 저장됨).
    if (_key(_selectedDate) != dateKey) return;
    setState(() => _timeRecords = records);
  }

  // ─── 투두 nudge 알림 ─────────────────────────────────────────────────────────
  // 오늘 미완료 투두가 있으면 90분 타이머 예약, 없으면 취소.
  // _toggleDone(완료 방향)에서 호출 시 타이머가 지금 시각 기준으로 리셋됨.
  // 단, 타이머가 진행 중이면 "지금 일하고 있는 중"이므로 nudge를 띄우지 않음.
  void _refreshNudge({bool completedNow = false}) {
    if (kIsWeb) return;
    final todayKey = _key(_today());
    if (_selKey != todayKey) return;
    final todayTodos = _byDate[todayKey] ?? [];
    final hasIncomplete = todayTodos.any((t) => !t.done);
    final timerRunning = _activeRecordIds.isNotEmpty;
    if (!hasIncomplete || timerRunning) {
      NotificationService.instance.cancelNudge();
    } else if (completedNow || hasIncomplete) {
      NotificationService.instance.scheduleNudge();
    }
  }

  // ─── 주간 캘린더 ─────────────────────────────────────────────────────────────
  DateTime _weekStart(int page) {
    final base = _sundayOfWeek(_today());
    return base.add(Duration(days: (page - _kBase) * 7));
  }

  int _pageForDate(DateTime date) {
    final base = _sundayOfWeek(_today());
    final ds = _sundayOfWeek(date);
    return _kBase + ds.difference(base).inDays ~/ 7;
  }

  void _onPageChanged(int page) {
    final ws = _weekStart(page);
    final dow = _selectedDate.weekday % 7;
    setState(() => _selectedDate = ws.add(Duration(days: dow)));
    _refreshNudge();
  }

  void _selectDay(DateTime day) {
    final page = _pageForDate(day);
    final cur = _pageController.page?.round() ?? _kBase;
    if (page != cur) {
      _pageController.animateToPage(page,
          duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
    }
    setState(() => _selectedDate = day);
    _loadTimeRecordsForDate(_key(day));
    _refreshNudge();
  }

  // ─── 투두 CRUD ───────────────────────────────────────────────────────────────
  Future<void> _addTodo() async {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    _addController.clear();
    // 생성 중(await)에 사용자가 페이지를 넘기면 _selKey가 바뀐다.
    // 생성 시점의 날짜키를 고정해, 완료 후 리스트도 그 날짜에 넣는다.
    final targetKey = _selKey;
    final todo = await SupabaseService.createTodo(text, targetKey);
    AnalyticsService.todoCreated();
    if (!mounted) return;
    setState(() => _byDate.putIfAbsent(targetKey, () => []).add(todo));
    _refreshNudge();
  }

  Future<void> _toggleDone(Todo todo) async {
    final completing = !todo.done; // true = 완료로 전환
    await SupabaseService.updateTodoDone(todo.id!, completing);
    if (!mounted) return;
    setState(() {
      final list = _byDate[todo.date];
      if (list == null) return;
      final i = list.indexWhere((t) => t.id == todo.id);
      if (i != -1) list[i] = todo.copyWith(done: completing);
    });
    // 완료 시 → 90분 타이머 리셋 (지금 이 순간부터 90분)
    _refreshNudge(completedNow: completing);
  }

  Future<void> _saveEdit(Todo todo) async {
    final text = _editController.text.trim();
    setState(() => _editingId = null);
    if (text.isEmpty || text == todo.text) return;
    await SupabaseService.updateTodoText(todo.id!, text);
    if (!mounted) return;
    setState(() {
      final list = _byDate[todo.date];
      if (list == null) return;
      final i = list.indexWhere((t) => t.id == todo.id);
      if (i != -1) list[i] = todo.copyWith(text: text);
    });
  }

  // 편집 중인 항목이 있으면 변경사항을 자동 저장하고 편집 모드 종료.
  // 외부 영역 탭(키보드 내리기 등) 시 호출 — 텍스트가 사라지지 않게 한다.
  void _commitEditingIfAny() {
    final eid = _editingId;
    if (eid == null) return;
    final parts = eid.split(':');
    if (parts.length < 2) {
      setState(() => _editingId = null);
      return;
    }
    final date = parts[0];
    final id = int.tryParse(parts[1]);
    final list = _byDate[date];
    if (id == null || list == null) {
      setState(() => _editingId = null);
      return;
    }
    Todo? todo;
    for (final t in list) {
      if (t.id == id) {
        todo = t;
        break;
      }
    }
    if (todo == null) {
      setState(() => _editingId = null);
      return;
    }
    _saveEdit(todo);
  }

  Future<void> _deleteTodo(Todo todo) async {
    // dismiss된 위젯이 다음 빌드에 남지 않도록 로컬 리스트에서 즉시 제거(낙관적).
    // Supabase 삭제는 뒤이어 비동기로 진행 — 네트워크 대기 중 리빌드가 나도
    // Dismissible이 트리에 남지 않는다.
    setState(() {
      _activeRecordIds.remove(todo.id);
      _timerStartTimes.remove(todo.id);
      _timeRecords.remove(todo.id);
      _byDate[todo.date]?.removeWhere((t) => t.id == todo.id);
    });
    _refreshNudge();
    _refreshTimerBanner();
    await SupabaseService.deleteTodo(todo.id!);
  }

  // ─── 타이머 (TimeRecord 기반) ─────────────────────────────────────────────
  static String _nowHHMM() {
    final t = TimeOfDay.now();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  bool _isRunning(int todoId) => _activeRecordIds.containsKey(todoId);

  Future<void> _startTimer(Todo todo) async {
    if (todo.id == null || _isRunning(todo.id!)) return;
    final s = _nowHHMM();
    final record =
        await SupabaseService.createTimeRecord(todo.id!, s);
    if (!mounted) return;
    _timerStartTimes[todo.id!] = DateTime.now();
    // 30초마다 경과시간 갱신 + 알림 배너 재게시(스와이프 해제 시 자동 복귀)
    _elapsedTicker ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (_activeRecordIds.isNotEmpty) {
        setState(() {});
        _refreshTimerBanner();
      }
    });
    setState(() {
      _activeRecordIds[todo.id!] = record.id!;
      _timeRecords
          .putIfAbsent(todo.id!, () => [])
          .add(record);
    });
    _refreshTimerBanner();
    _refreshNudge(); // 타이머 시작 → nudge 끔
  }

  Future<void> _stopTimer(Todo todo) async {
    final todoId = todo.id;
    if (todoId == null) return;
    final recordId = _activeRecordIds[todoId];
    if (recordId == null) return;

    final e = _nowHHMM();
    await SupabaseService.finishTimeRecord(recordId, e);
    if (!mounted) return;
    _timerStartTimes.remove(todoId);
    if (_activeRecordIds.length <= 1) {
      _elapsedTicker?.cancel();
      _elapsedTicker = null;
    }
    setState(() {
      _activeRecordIds.remove(todoId);
      final list = _timeRecords[todoId];
      if (list != null) {
        final idx = list.indexWhere((r) => r.id == recordId);
        if (idx != -1) list[idx] = list[idx].copyWith(endTime: e);
      }
    });
    _refreshTimerBanner();
    _refreshNudge(); // 타이머 종료 → nudge 다시 켜질 수 있음
  }

  // 현재 실행 중인 모든 타이머를 모아 상단 알림 배너를 갱신.
  // 종료 깜빡 잊는 걸 방지 — 진행 중이면 폰 상단에 계속 표시됨.
  void _refreshTimerBanner() {
    if (kIsWeb) return;
    final active = <ActiveTimer>[];
    for (final entry in _activeRecordIds.entries) {
      final todoId = entry.key;
      final recordId = entry.value;
      // todo 텍스트 찾기 (모든 날짜 스캔, 보통 한 자리)
      String? todoText;
      for (final list in _byDate.values) {
        for (final t in list) {
          if (t.id == todoId) {
            todoText = t.text;
            break;
          }
        }
        if (todoText != null) break;
      }
      if (todoText == null) continue;
      // 시작 시각 찾기
      final rec = _timeRecords[todoId]
          ?.firstWhere((r) => r.id == recordId, orElse: () => TimeRecord(todoId: todoId, startTime: ''));
      final start = rec?.startTime ?? '';
      if (start.isEmpty) continue;
      active.add(ActiveTimer(todoText: todoText, startTime: start));
    }
    NotificationService.instance.showActiveTimers(active);
  }

  // 타이머 실행 중 경과 시간 레이블
  String _elapsedLabel(int todoId, String startTime) {
    final startedAt = _timerStartTimes[todoId];
    if (startedAt == null) return '$startTime~ 진행중';
    final min = DateTime.now().difference(startedAt).inMinutes;
    return min > 0 ? '$startTime~ +$min분' : '$startTime~ 방금';
  }

  // 시간 기록 뱃지 텍스트
  String _timeBadgeLabel(int todoId) {
    final records = _timeRecords[todoId] ?? [];
    final activeId = _activeRecordIds[todoId];

    if (activeId != null) {
      final active = records.lastWhere((r) => r.id == activeId,
          orElse: () => TimeRecord(todoId: todoId, startTime: ''));
      return _elapsedLabel(todoId, active.startTime);
    }
    if (records.isEmpty) return '';
    final first = records.first;
    final firstLabel = first.endTime != null
        ? '${first.startTime}~${first.endTime}'
        : first.startTime;
    if (records.length == 1) return firstLabel;
    return '$firstLabel +${records.length - 1}';
  }

  bool _hasTimeRecords(int todoId) =>
      (_timeRecords[todoId]?.isNotEmpty ?? false) ||
      _activeRecordIds.containsKey(todoId);

  // ─── 밀린 투두 복사 ──────────────────────────────────────────────────────────
  // 선택한 날짜 "이전"의 모든 미완료 할 일을 오늘 목록으로 모아온다.
  // (어제 하루가 아니라 지금까지 쌓인 미완료 전부)
  Future<void> _copyIncompletePast() async {
    // 배치 삽입 중(await)에 페이지를 넘기면 _selKey가 바뀐다.
    // 복사 시점의 날짜키를 고정해, 완료 후 리스트도 그 날짜에 넣는다.
    final targetKey = _selKey;
    // 같은 내용이 여러 날에 밀려 중복돼 있을 수 있으니 텍스트로 중복 제거하고,
    // 이미 오늘 목록에 있는 내용은 건너뛴다(반복 클릭 시 중복 방지 포함).
    final existing = (_byDate[targetKey] ?? []).map((t) => t.text).toSet();
    final seen = <String>{};
    final texts = <String>[];
    // 날짜키(YYYY-MM-DD)는 사전순 = 시간순 → 오래된 날부터 모은다.
    final pastKeys = _byDate.keys
        .where((k) => k.compareTo(targetKey) < 0)
        .toList()
      ..sort();
    for (final k in pastKeys) {
      for (final t in (_byDate[k] ?? [])) {
        if (t.done) continue;
        if (existing.contains(t.text)) continue;
        if (!seen.add(t.text)) continue;
        texts.add(t.text);
      }
    }
    if (!mounted) return;
    if (texts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('가져올 밀린 할 일이 없어요'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    // 한 개씩 await하면 왕복이 2N회 → 배치로 2회. (복사 지연의 주원인)
    final created = await SupabaseService.createTodosBatch(texts, targetKey);
    if (!mounted) return;
    setState(() => _byDate.putIfAbsent(targetKey, () => []).addAll(created));
    _refreshNudge();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('밀린 할 일 ${created.length}개 가져왔어요'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // 시간 기록 목록 바텀시트 (기록 확인 + 개별 삭제)
  Future<void> _showTimeRecords(Todo todo) async {
    if (todo.id == null) return;
    final records = List<TimeRecord>.from(_timeRecords[todo.id!] ?? []);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(todo.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  Text('${records.length}회 기록',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.4))),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ...records.map((r) => ListTile(
                  dense: true,
                  title: Text(
                    r.endTime != null
                        ? '${r.startTime} ~ ${r.endTime}'
                        : '${r.startTime} ~ 진행 중',
                    style: TextStyle(
                        fontSize: 13,
                        color: r.endTime == null
                            ? Theme.of(context).colorScheme.primary
                            : null),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 수정 버튼
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.45),
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await _editTimeRecord(todo, r);
                        },
                      ),
                      // 삭제 버튼
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: Theme.of(context)
                            .colorScheme
                            .error
                            .withOpacity(0.6),
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await SupabaseService.deleteTimeRecord(r.id!);
                          if (!mounted) return;
                          setState(() {
                            _timeRecords[todo.id!]
                                ?.removeWhere((x) => x.id == r.id);
                            if (_activeRecordIds[todo.id!] == r.id) {
                              _activeRecordIds.remove(todo.id!);
                              _timerStartTimes.remove(todo.id!);
                            }
                          });
                        },
                      ),
                    ],
                  ),
                )),
            // 수동 입력 추가 버튼
            ListTile(
              dense: true,
              leading: Icon(Icons.add,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary),
              title: Text('직접 입력',
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary)),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _addManualRecord(todo);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // 수동으로 시간 기록 추가 (TimePicker)
  Future<void> _addManualRecord(Todo todo) async {
    if (todo.id == null || !mounted) return;
    final now = TimeOfDay.now();
    final startPicked = await showTimePicker(
      context: context,
      initialTime: now,
      helpText: '시작 시간',
    );
    if (startPicked == null || !mounted) return;
    final endPicked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
          hour: (startPicked.hour + 1).clamp(0, 23),
          minute: startPicked.minute),
      helpText: '종료 시간',
    );
    if (!mounted) return;
    final s =
        '${startPicked.hour.toString().padLeft(2, '0')}:${startPicked.minute.toString().padLeft(2, '0')}';
    final e = endPicked != null
        ? '${endPicked.hour.toString().padLeft(2, '0')}:${endPicked.minute.toString().padLeft(2, '0')}'
        : null;
    var record =
        await SupabaseService.createTimeRecord(todo.id!, s);
    if (e != null) {
      await SupabaseService.finishTimeRecord(record.id!, e);
      record = record.copyWith(endTime: e);
    }
    if (!mounted) return;
    setState(() {
      _timeRecords.putIfAbsent(todo.id!, () => []).add(record);
      // 종료 시간 없이 추가 → 진행 중 상태로 등록
      if (e == null && record.id != null) {
        _activeRecordIds[todo.id!] = record.id!;
        _timerStartTimes[todo.id!] = DateTime.now();
        _elapsedTicker ??= Timer.periodic(const Duration(seconds: 30), (_) {
          if (!mounted) return;
          if (_activeRecordIds.isNotEmpty) {
            setState(() {});
            _refreshTimerBanner();
          }
        });
      }
    });
  }

  // 기존 시간 기록 수정 (시작/종료 시간 변경)
  Future<void> _editTimeRecord(Todo todo, TimeRecord record) async {
    if (todo.id == null || record.id == null || !mounted) return;

    // 시작 시간 수정
    final startParts = record.startTime.split(':');
    final startPicked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(startParts[0]),
        minute: int.parse(startParts[1]),
      ),
      helpText: '시작 시간 수정',
    );
    if (startPicked == null || !mounted) return;

    // 종료 시간 수정
    TimeOfDay? endInitial;
    if (record.endTime != null) {
      final endParts = record.endTime!.split(':');
      endInitial = TimeOfDay(
        hour: int.parse(endParts[0]),
        minute: int.parse(endParts[1]),
      );
    } else {
      endInitial = TimeOfDay(
        hour: (startPicked.hour + 1).clamp(0, 23),
        minute: startPicked.minute,
      );
    }
    final endPicked = await showTimePicker(
      context: context,
      initialTime: endInitial,
      helpText: '종료 시간 수정',
    );
    if (!mounted) return;

    final s =
        '${startPicked.hour.toString().padLeft(2, '0')}:${startPicked.minute.toString().padLeft(2, '0')}';
    final e = endPicked != null
        ? '${endPicked.hour.toString().padLeft(2, '0')}:${endPicked.minute.toString().padLeft(2, '0')}'
        : record.endTime;

    await SupabaseService.updateTimeRecord(record.id!, s, e);
    if (!mounted) return;
    // startTime도 바뀌므로 DB에서 재로딩
    _loadTimeRecordsForDate(_selKey);
  }

  // _setTime은 레거시 todo.startTime 필드를 사용하지 않으므로 제거됨.
  // 수동 입력은 _addManualRecord, 목록 조회는 _showTimeRecords 사용.
  void _openPlanner() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlannerScreen(
        date: _selectedDate,
        todos: _selTodos,
        timeRecords: _timeRecords,
      ),
    ));
  }

  Future<bool> _confirmDelete() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('할 일 삭제',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            content: const Text('이 할 일을 삭제할까요?',
                style: TextStyle(fontSize: 14)),
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
                child: Text('삭제',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ─── 재정렬 ──────────────────────────────────────────────────────────────────
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final todos = List.of(_selTodos);
    final item = todos.removeAt(oldIndex);
    todos.insert(newIndex, item);

    setState(() {
      _byDate[_selKey] = todos;
    });

    // 배치 업데이트
    await Future.wait(todos.asMap().entries.map(
          (e) => SupabaseService.updateTodoOrderIndex(e.value.id!, e.key),
        ));
  }

  // ─── 빌드 ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    _lastBuildCtx = context;
    _maybeStartCoach(context);
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        // 외부 탭 시 편집 내용 날리지 않고 자동 저장 (오작동 방지)
        _commitEditingIfAny();
      },
      behavior: HitTestBehavior.translucent,
      child: Column(
        children: [
          _buildMonthHeader(),
          _buildWeekPager(),
          _buildDateBar(),
          Divider(
              height: 1,
              thickness: 0.5,
              color: Theme.of(context).dividerColor),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(child: _buildTodoList()),
          _buildAddBar(),
        ],
      ),
    );
  }

  // ─── 월 헤더 ─────────────────────────────────────────────────────────────────
  Widget _buildMonthHeader() {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final btn = landscape ? 34.0 : 44.0;
    Widget chevron(IconData icon, VoidCallback onTap) => SizedBox(
          width: btn,
          height: btn,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(icon, size: 22),
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            onPressed: onTap,
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
      child: Row(
        children: [
          chevron(
              Icons.chevron_left,
              () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOut)),
          Expanded(
            child: Center(
              child: Text(
                '${_selectedDate.year}년 ${_selectedDate.month}월',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
          chevron(
              Icons.chevron_right,
              () => _pageController.nextPage(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOut)),
        ],
      ),
    );
  }

  // ─── 주간 달력 ───────────────────────────────────────────────────────────────
  Widget _buildWeekPager() {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return SizedBox(
      height: landscape ? 56 : 80,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemBuilder: (_, page) => _buildWeekRow(_weekStart(page)),
      ),
    );
  }

  Widget _buildWeekRow(DateTime sunday) {
    final landscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final circle = landscape ? 28.0 : 36.0;
    final gapTop = landscape ? 3.0 : 6.0;
    final gapBot = landscape ? 2.0 : 5.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: List.generate(7, (i) {
          final day = sunday.add(Duration(days: i));
          final dk = _key(day);
          final isSelected = dk == _selKey;
          final isToday = dk == _key(_today());
          final hasTodo = _byDate[dk]?.any((t) => !t.done) ?? false;

          final Color labelColor = i == 0
              ? Theme.of(context).colorScheme.error.withOpacity(0.7)
              : i == 6
                  ? Colors.blue.withOpacity(0.65)
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.4);
          final Color numColor = i == 0
              ? Theme.of(context).colorScheme.error
              : i == 6
                  ? Colors.blue
                  : Theme.of(context).colorScheme.onSurface;

          return Expanded(
            child: GestureDetector(
              onTap: () => _selectDay(day),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_dayLabels[i],
                      style: TextStyle(fontSize: 11, color: labelColor)),
                  SizedBox(height: gapTop),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: circle,
                    height: circle,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      border: isToday && !isSelected
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 1.5)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected || isToday
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isSelected ? Colors.white : numColor,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: gapBot),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasTodo
                          ? (isSelected
                              ? Colors.white.withOpacity(0.8)
                              : Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.55))
                          : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── 날짜 제목 ───────────────────────────────────────────────────────────────
  Widget _buildDateBar() {
    final todos = _selTodos;
    final done = todos.where((t) => t.done).length;
    final total = todos.length;
    final todayKey = _key(_today());
    final tomorrowKey = _key(_today().add(const Duration(days: 1)));
    const weekdayKo = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdayKo[_selectedDate.weekday - 1];
    final prefix = _selKey == todayKey
        ? '오늘 · '
        : _selKey == tomorrowKey
            ? '내일 · '
            : '';
    final dateStr =
        '$prefix${_selectedDate.month}월 ${_selectedDate.day}일 $wd요일';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Text(dateStr,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              )),
          if (total > 0) ...[
            const SizedBox(width: 8),
            Text('$done/$total 완료',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.38),
                )),
          ],
          const Spacer(),
          buildCoachMark(
            context: context,
            key: _copyKey,
            title: '밀린 할 일 가져오기',
            description: '지금까지 못 끝낸 할 일을\n오늘 목록으로 한 번에 모아와요.',
            targetShapeBorder: const CircleBorder(),
            child: IconButton(
              icon: Icon(Icons.copy_outlined,
                  size: 18,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.38)),
              onPressed: _copyIncompletePast,
              tooltip: '밀린 할 일 가져오기',
            ),
          ),
          buildCoachMark(
            context: context,
            key: _plannerKey,
            title: '플래너',
            description: '하루를 색깔 시간표로 만들어\n인스타 스토리 등에 바로 공유할 수 있어요.',
            targetShapeBorder: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
            child: TextButton.icon(
              onPressed: _openPlanner,
              icon: const Icon(Icons.grid_view_rounded, size: 15),
              label: const Text('플래너'),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 투두 리스트 (ReorderableListView) ──────────────────────────────────────
  Widget _buildTodoList() {
    final todos = _selTodos;
    if (todos.isEmpty) {
      return Center(
        child: Text('할 일을 추가해봐요',
            style: TextStyle(
              fontSize: 14,
              color:
                  Theme.of(context).colorScheme.onSurface.withOpacity(0.28),
            )),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      buildDefaultDragHandles: false,
      itemCount: todos.length,
      onReorder: _onReorder,
      itemBuilder: (_, index) {
        final todo = todos[index];
        return _buildItem(todo, index);
      },
    );
  }

  Widget _buildItem(Todo todo, int index) {
    final eid = '${todo.date}:${todo.id}';
    final isEditing = _editingId == eid;
    final plannerColor = plannerColorAt(index);

    // 항목을 길게 누르면 바로 드래그해서 순서를 바꿀 수 있다 (핸들 없음).
    return ReorderableDelayedDragStartListener(
      key: ValueKey('todo-${todo.id}'),
      index: index,
      child: Dismissible(
        key: ValueKey('todo-dismiss-${todo.id}'),
        direction: DismissDirection.endToStart,
        // ReorderableListView 안에서 Dismissible이 실제로 dismiss되면
        // "A dismissed Dismissible widget is still part of the tree" 에러가
        // 특정 타이밍에 재발한다. 그래서 confirmDismiss에서 직접 삭제하고
        // 항상 false를 반환해 Dismissible이 스스로 dismiss되지 않게 한다.
        // 항목은 _deleteTodo의 setState로 리스트에서 즉시 빠져 rebuild로 사라진다.
        confirmDismiss: (_) async {
          final ok = await _confirmDelete();
          if (ok) unawaited(_deleteTodo(todo));
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 8),
          child: Icon(Icons.delete_outline,
              size: 18,
              color: Theme.of(context).colorScheme.error.withOpacity(0.55)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 체크박스
              GestureDetector(
              onTap: () => _toggleDone(todo),
              child: _buildCircleCheck(todo.done),
            ),
            const SizedBox(width: 14),
            // 타이머 버튼 + 시간 뱃지
            if (!isEditing) ...[
              const SizedBox(width: 4),
              // ▶/⏹ 타이머 버튼 (36px 터치 타겟)
              _buildTimerButton(todo, index, plannerColor),
              // 시간 기록 뱃지 (기록이 있거나 타이머 실행 중일 때)
              if (todo.id != null && _hasTimeRecords(todo.id!)) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => _showTimeRecords(todo),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: plannerColor.withOpacity(
                          _isRunning(todo.id!) ? 0.22 : 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _timeBadgeLabel(todo.id!),
                      style: TextStyle(
                        fontSize: 10,
                        color: plannerColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(width: 4),
            Expanded(
              child: isEditing
                  ? Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _editController,
                          focusNode: _editFocus,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          keyboardType: TextInputType.multiline,
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) => _saveEdit(todo),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _saveEdit(todo),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(Icons.check_rounded,
                              size: 20,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                    ])
                  : GestureDetector(
                      onTap: () {
                        _editController.text = todo.text;
                        setState(() => _editingId = eid);
                        WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _editFocus.requestFocus());
                      },
                      child: Text(
                        todo.text,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.45,
                          color: todo.done
                              ? Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.3)
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.88),
                          decoration: todo.done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          decorationColor: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.3),
                        ),
                      ),
                    ),
            ),
            // 플래너 색상 점
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: plannerColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  // ▶/⏹ 타이머 버튼. 첫 항목(index 0)에는 코치마크를 단다.
  Widget _buildTimerButton(Todo todo, int index, Color plannerColor) {
    final running = todo.id != null && _isRunning(todo.id!);
    final button = GestureDetector(
      onTap: () => running ? _stopTimer(todo) : _startTimer(todo),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: Icon(
            running ? Icons.stop_circle_outlined : Icons.play_circle_outline,
            size: 18,
            color: running
                ? plannerColor
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.22),
          ),
        ),
      ),
    );
    if (index != 0) return button;
    return buildCoachMark(
      context: context,
      key: _timerKey,
      title: '타이머로 시간 기록',
      description: '▶ 를 누르면 시작 시각이 기록되고,\n다시 누르면 종료까지 자동 저장돼요.',
      targetShapeBorder: const CircleBorder(),
      child: button,
    );
  }

  Widget _buildCircleCheck(bool done) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? Theme.of(context).colorScheme.primary
            : Colors.transparent,
        border: Border.all(
          color: done
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.22),
          width: 1.5,
        ),
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : null,
    );
  }

  // ─── 하단 입력창 ─────────────────────────────────────────────────────────────
  Widget _buildAddBar() {
    return buildCoachMark(
      context: context,
      key: _addKey,
      title: '할 일 추가',
      description: '여기에 오늘 할 일을 적어 추가해요.',
      targetShapeBorder: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
                color: Theme.of(context).dividerColor, width: 0.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
            _buildCircleCheck(false),
            const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: _addController,
                focusNode: _addFocus,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.multiline,
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: '할 일 추가...',
                  hintStyle: TextStyle(
                    fontSize: 15,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.28),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) => _addTodo(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _addTodo,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_upward_rounded,
                    size: 17,
                    color: Theme.of(context).colorScheme.onPrimary),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
