import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/todo.dart';
import '../services/notification_service.dart';
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
    _pageController.dispose();
    _addController.dispose();
    _addFocus.dispose();
    _editController.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final todos = await DatabaseHelper.instance.readAllTodos();
    final map = <String, List<Todo>>{};
    for (final t in todos) {
      map.putIfAbsent(t.date, () => []).add(t);
    }
    if (!mounted) return;
    setState(() {
      _byDate = map;
      _loading = false;
    });
    _refreshNudge();
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
    _refreshNudge();
  }

  // ─── 투두 CRUD ───────────────────────────────────────────────────────────────
  Future<void> _addTodo() async {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    _addController.clear();
    final todo = await DatabaseHelper.instance.createTodo(text, _selKey);
    if (!mounted) return;
    setState(() => _byDate.putIfAbsent(_selKey, () => []).add(todo));
    _refreshNudge();
  }

  Future<void> _toggleDone(Todo todo) async {
    final completing = !todo.done; // true = 완료로 전환
    await DatabaseHelper.instance.updateTodoDone(todo.id!, completing);
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
    await DatabaseHelper.instance.updateTodoText(todo.id!, text);
    if (!mounted) return;
    setState(() {
      final list = _byDate[todo.date];
      if (list == null) return;
      final i = list.indexWhere((t) => t.id == todo.id);
      if (i != -1) list[i] = todo.copyWith(text: text);
    });
  }

  Future<void> _deleteTodo(Todo todo) async {
    await DatabaseHelper.instance.deleteTodo(todo.id!);
    if (!mounted) return;
    setState(() => _byDate[todo.date]?.removeWhere((t) => t.id == todo.id));
    _refreshNudge();
  }

  Future<void> _setTime(Todo todo) async {
    final isSet = todo.startTime != null;
    if (isSet) {
      // 이미 시간 있으면 수정/삭제 메뉴
      final action = await showModalBottomSheet<String>(
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
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 8),
              ListTile(
                  leading: const Icon(Icons.edit_outlined, size: 20),
                  title: const Text('시간 변경'),
                  onTap: () => Navigator.of(ctx).pop('edit')),
              ListTile(
                  leading: const Icon(Icons.delete_outline, size: 20),
                  title: const Text('시간 삭제'),
                  onTap: () => Navigator.of(ctx).pop('delete')),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (action == 'delete') {
        await DatabaseHelper.instance.updateTodoTimes(todo.id!, null, null);
        if (!mounted) return;
        setState(() {
          final list = _byDate[todo.date];
          if (list == null) return;
          final i = list.indexWhere((t) => t.id == todo.id);
          if (i != -1) {
            list[i] = todo.copyWith(
                clearStartTime: true, clearEndTime: true);
          }
        });
        return;
      }
      if (action != 'edit') return;
    }

    // 시작 시간 선택
    final now = TimeOfDay.now();
    if (!mounted) return;
    final startPicked = await showTimePicker(
      context: context,
      initialTime: todo.startTime != null
          ? TimeOfDay(
              hour: int.parse(todo.startTime!.split(':')[0]),
              minute: int.parse(todo.startTime!.split(':')[1]))
          : now,
      helpText: '시작 시간',
    );
    if (startPicked == null || !mounted) return;

    // 종료 시간 선택
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

    await DatabaseHelper.instance.updateTodoTimes(todo.id!, s, e);
    if (!mounted) return;
    setState(() {
      final list = _byDate[todo.date];
      if (list == null) return;
      final i = list.indexWhere((t) => t.id == todo.id);
      if (i != -1) list[i] = todo.copyWith(startTime: s, endTime: e);
    });
  }

  void _openPlanner() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlannerScreen(
        date: _selectedDate,
        todos: _selTodos,
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
          (e) => DatabaseHelper.instance
              .updateTodoOrderIndex(e.value.id!, e.key),
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
            icon: Icon(Icons.calendar_view_day_outlined,
                size: 20,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.45)),
            onPressed: _openPlanner,
            tooltip: '플래너 보기',
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
            // 텍스트 (탭하면 편집)
            // 시간 표시/설정 버튼
            if (!isEditing) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _setTime(todo),
                child: todo.startTime != null
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${todo.startTime}${todo.endTime != null ? '~${todo.endTime}' : ''}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    : Icon(Icons.access_time_outlined,
                        size: 16,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.22)),
              ),
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
                              color:
                                  Theme.of(context).colorScheme.primary),
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
