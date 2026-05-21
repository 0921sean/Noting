import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../models/todo.dart';
import '../models/time_record.dart';
import '../services/notification_service.dart';
import '../utils/planner_colors.dart';
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
    _load();
  }

  @override
  void dispose() {
    _elapsedTicker?.cancel();
    _pageController.dispose();
    _addController.dispose();
    _addFocus.dispose();
    _editController.dispose();
    _editFocus.dispose();
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
          if (mounted && _activeRecordIds.isNotEmpty) setState(() {});
        });
      }
    }
    setState(() {
      _byDate = map;
      _timeRecords = records;
      _loading = false;
    });
    _refreshNudge();
  }

  Future<void> _loadTimeRecordsForDate(String dateKey) async {
    final records =
        await SupabaseService.readTimeRecordsForDate(dateKey);
    if (!mounted) return;
    setState(() => _timeRecords = records);
  }

  // ─── 투두 nudge 알림 ─────────────────────────────────────────────────────────
  // 오늘 미완료 투두가 있으면 90분 타이머 예약, 없으면 취소.
  // _toggleDone(완료 방향)에서 호출 시 타이머가 지금 시각 기준으로 리셋됨.
  void _refreshNudge({bool completedNow = false}) {
    if (kIsWeb) return;
    final todayKey = _key(_today());
    if (_selKey != todayKey) return;
    final todayTodos = _byDate[todayKey] ?? [];
    final hasIncomplete = todayTodos.any((t) => !t.done);
    if (!hasIncomplete) {
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
    final todo = await SupabaseService.createTodo(text, _selKey);
    if (!mounted) return;
    setState(() => _byDate.putIfAbsent(_selKey, () => []).add(todo));
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

  Future<void> _deleteTodo(Todo todo) async {
    await SupabaseService.deleteTodo(todo.id!);
    if (!mounted) return;
    setState(() {
      _activeRecordIds.remove(todo.id);
      _timerStartTimes.remove(todo.id);
      _timeRecords.remove(todo.id);
      _byDate[todo.date]?.removeWhere((t) => t.id == todo.id);
    });
    _refreshNudge();
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
    _elapsedTicker ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _activeRecordIds.isNotEmpty) setState(() {});
    });
    setState(() {
      _activeRecordIds[todo.id!] = record.id!;
      _timeRecords
          .putIfAbsent(todo.id!, () => [])
          .add(record);
    });
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

  // ─── 어제 투두 복사 ──────────────────────────────────────────────────────────
  Future<void> _copyFromYesterday() async {
    final yesterday = _selectedDate.subtract(const Duration(days: 1));
    final yesterdayKey = _key(yesterday);
    final incomplete =
        (_byDate[yesterdayKey] ?? []).where((t) => !t.done).toList();
    if (!mounted) return;
    if (incomplete.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('어제 미완료 할 일이 없어요'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    for (final todo in incomplete) {
      final created =
          await SupabaseService.createTodo(todo.text, _selKey);
      if (!mounted) return;
      setState(() => _byDate.putIfAbsent(_selKey, () => []).add(created));
    }
    _refreshNudge();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('어제 할 일 ${incomplete.length}개 가져왔어요'),
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
                  Text(todo.text,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
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
          if (mounted && _activeRecordIds.isNotEmpty) setState(() {});
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
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        if (_editingId != null) setState(() => _editingId = null);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 22),
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            onPressed: () => _pageController.previousPage(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut),
          ),
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
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 22),
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            onPressed: () => _pageController.nextPage(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOut),
          ),
        ],
      ),
    );
  }

  // ─── 주간 달력 ───────────────────────────────────────────────────────────────
  Widget _buildWeekPager() {
    return SizedBox(
      height: 80,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemBuilder: (_, page) => _buildWeekRow(_weekStart(page)),
      ),
    );
  }

  Widget _buildWeekRow(DateTime sunday) {
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
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 36,
                    height: 36,
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
                  const SizedBox(height: 5),
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
          IconButton(
            icon: Icon(Icons.copy_outlined,
                size: 18,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.38)),
            onPressed: _copyFromYesterday,
            tooltip: '어제 할 일 가져오기',
          ),
          TextButton.icon(
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

    return Dismissible(
      key: ValueKey('todo-${todo.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(),
      onDismissed: (_) => _deleteTodo(todo),
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
            // 드래그 핸들
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.drag_indicator_outlined,
                  size: 18,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.22),
                ),
              ),
            ),
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
              GestureDetector(
                onTap: () => todo.id != null && _isRunning(todo.id!)
                    ? _stopTimer(todo)
                    : _startTimer(todo),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: Icon(
                      todo.id != null && _isRunning(todo.id!)
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outline,
                      size: 18,
                      color: todo.id != null && _isRunning(todo.id!)
                          ? plannerColor
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.22),
                    ),
                  ),
                ),
              ),
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
    return Container(
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
    );
  }
}
