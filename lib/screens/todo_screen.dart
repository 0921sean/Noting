import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/todo.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  final Map<String, List<Todo>> _byDate = {};
  final List<String> _dates = [];
  bool _loading = true;
  String? _addingForDate;
  String? _editingTodoId; // 'date:id'
  final _addController = TextEditingController();
  final _editController = TextEditingController();
  final _addFocus = FocusNode();
  final _editFocus = FocusNode();

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${_p(now.month)}-${_p(now.day)}';
  }

  static String _tomorrowKey() {
    final tm = DateTime.now().add(const Duration(days: 1));
    return '${tm.year}-${_p(tm.month)}-${_p(tm.day)}';
  }

  static String _p(int v) => v.toString().padLeft(2, '0');

  static String _label(String key) {
    final today = _todayKey();
    final tomorrow = _tomorrowKey();
    if (key == today) return '오늘';
    if (key == tomorrow) return '내일';
    final dt = DateTime.parse(key);
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return '${dt.month}월 ${dt.day}일 (${days[dt.weekday - 1]})';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addController.dispose();
    _editController.dispose();
    _addFocus.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final todos = await DatabaseHelper.instance.readAllTodos();
    final byDate = <String, List<Todo>>{};
    for (final t in todos) {
      byDate.putIfAbsent(t.date, () => []).add(t);
    }
    final allDates = <String>{_todayKey(), _tomorrowKey(), ...byDate.keys};
    final sorted = allDates.toList()..sort();

    if (!mounted) return;
    setState(() {
      _byDate
        ..clear()
        ..addAll(byDate);
      _dates
        ..clear()
        ..addAll(sorted);
      _loading = false;
    });
  }

  Future<void> _addTodo(String date) async {
    final text = _addController.text.trim();
    _addController.clear();
    setState(() => _addingForDate = null);
    if (text.isEmpty) return;

    final todo = await DatabaseHelper.instance.createTodo(text, date);
    if (!mounted) return;
    setState(() => _byDate.putIfAbsent(date, () => []).add(todo));
  }

  Future<void> _toggleDone(String date, Todo todo) async {
    await DatabaseHelper.instance.updateTodoDone(todo.id!, !todo.done);
    if (!mounted) return;
    setState(() {
      final list = _byDate[date];
      if (list == null) return;
      final idx = list.indexWhere((t) => t.id == todo.id);
      if (idx != -1) list[idx] = todo.copyWith(done: !todo.done);
    });
  }

  Future<void> _saveEdit(String date, Todo todo) async {
    final text = _editController.text.trim();
    setState(() => _editingTodoId = null);
    if (text.isEmpty || text == todo.text) return;

    await DatabaseHelper.instance.updateTodoText(todo.id!, text);
    if (!mounted) return;
    setState(() {
      final list = _byDate[date];
      if (list == null) return;
      final idx = list.indexWhere((t) => t.id == todo.id);
      if (idx != -1) list[idx] = todo.copyWith(text: text);
    });
  }

  Future<void> _deleteTodo(String date, Todo todo) async {
    await DatabaseHelper.instance.deleteTodo(todo.id!);
    if (!mounted) return;
    setState(() => _byDate[date]?.removeWhere((t) => t.id == todo.id));
  }

  Future<void> _addDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 2)),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      helpText: '날짜 선택',
    );
    if (picked == null) return;
    final key =
        '${picked.year}-${_p(picked.month)}-${_p(picked.day)}';
    if (!_dates.contains(key)) {
      setState(() {
        _dates.add(key);
        _dates.sort();
      });
    }
  }

  // ─── 빌드 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return GestureDetector(
      onTap: () {
        // 외부 탭 시 입력 필드 닫기
        if (_addingForDate != null) _addTodo(_addingForDate!);
        if (_editingTodoId != null) setState(() => _editingTodoId = null);
      },
      behavior: HitTestBehavior.translucent,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 80),
        itemCount: _dates.length + 1,
        itemBuilder: (_, i) {
          if (i == _dates.length) return _buildAddDateBtn();
          return _buildSection(_dates[i]);
        },
      ),
    );
  }

  Widget _buildSection(String date) {
    final todos = _byDate[date] ?? [];
    final isAdding = _addingForDate == date;

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 날짜 헤더
          Row(
            children: [
              Text(
                _label(date),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${todos.where((t) => !t.done).length}개',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _addingForDate = date;
                    _editingTodoId = null;
                  });
                  WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _addFocus.requestFocus());
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.add,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(
              height: 1,
              thickness: 0.5,
              color: Theme.of(context).dividerColor),
          const SizedBox(height: 6),

          // 할 일 목록
          ...todos.map((t) => _buildTodoItem(date, t)),

          // 추가 입력창
          if (isAdding)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  _buildCheckbox(false),
                  const SizedBox(width: 12),
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
                        hintText: '할 일 입력...',
                        hintStyle: TextStyle(
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addTodo(date),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: Icon(Icons.check_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary),
                    onPressed: () => _addTodo(date),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTodoItem(String date, Todo todo) {
    final editKey = '$date:${todo.id}';
    final isEditing = _editingTodoId == editKey;

    return Dismissible(
      key: ValueKey('todo-${todo.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Icon(Icons.delete_outline,
            size: 18,
            color: Theme.of(context).colorScheme.error.withOpacity(0.6)),
      ),
      onDismissed: (_) => _deleteTodo(date, todo),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _toggleDone(date, todo),
              child: _buildCheckbox(todo.done),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: isEditing
                  ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _editController,
                            focusNode: _editFocus,
                            textInputAction: TextInputAction.done,
                            keyboardType: TextInputType.multiline,
                            style: TextStyle(
                              fontSize: 15,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
                            onSubmitted: (_) => _saveEdit(date, todo),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: Icon(Icons.check_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary),
                          onPressed: () => _saveEdit(date, todo),
                        ),
                      ],
                    )
                  : GestureDetector(
                      onLongPress: () {
                        _editController.text = todo.text;
                        setState(() {
                          _editingTodoId = editKey;
                          _addingForDate = null;
                        });
                        WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _editFocus.requestFocus());
                      },
                      child: Text(
                        todo.text,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: todo.done
                              ? Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.35)
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
                              .withOpacity(0.35),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckbox(bool done) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: done
            ? Theme.of(context).colorScheme.primary
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: done
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : null,
    );
  }

  Widget _buildAddDateBtn() {
    return GestureDetector(
      onTap: _addDate,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.add_circle_outline,
                size: 16,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.35)),
            const SizedBox(width: 8),
            Text(
              '다른 날짜 추가',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
