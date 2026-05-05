import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/note.dart';
import '../services/category_service.dart';
import '../services/classifier_service.dart';
import '../services/notification_service.dart';
import 'note_detail_screen.dart';
import 'settings_screen.dart';
import 'todo_screen.dart';

enum _AppMode { notes, todos }

// 카테고리 색상 팔레트 (인덱스 기반 자동 배정)
const _palette = [
  Color(0xFFD4843A),
  Color(0xFF7C5C3E),
  Color(0xFF8B8070),
  Color(0xFF6B8F71),
  Color(0xFF7B6EA6),
  Color(0xFFB85C38),
  Color(0xFF5B7FA6),
  Color(0xFFA67B5B),
];

class HomeScreen extends StatefulWidget {
  final int? initialNoteId;
  const HomeScreen({super.key, this.initialNoteId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Note> _notes = [];
  bool _loading = true;
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  var _listKey = GlobalKey<AnimatedListState>();
  bool _submitting = false;

  // 검색
  bool _isSearching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // 카테고리 필터
  String? _selectedCategory;

  // 모드 (메모 / 투두)
  _AppMode _mode = _AppMode.notes;

  // 사용자 카테고리 목록
  List<String> _categories = [];

  bool get _hasCategoryData =>
      _categories.isNotEmpty && _notes.any((n) => n.category != null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    CategoryService.getAll().then((cats) {
      if (mounted) setState(() => _categories = cats);
    });
    _loadNotes().then((_) {
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
    _inputController.dispose();
    _inputFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshCurrentView();
      _scheduleIfNeeded();
    }
  }

  Future<void> _loadNotes() async {
    final notes = await DatabaseHelper.instance.readAllNotes();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
      _listKey = GlobalKey<AnimatedListState>();
    });
    if (notes.isNotEmpty) _checkSwipeHint();
  }

  Future<void> _searchNotes(String query) async {
    final notes = query.isEmpty
        ? await DatabaseHelper.instance.readAllNotes()
        : await DatabaseHelper.instance.searchNotes(query);
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _listKey = GlobalKey<AnimatedListState>();
    });
  }

  Future<void> _refreshCurrentView() async {
    if (_isSearching && _searchQuery.isNotEmpty) {
      await _searchNotes(_searchQuery);
    } else {
      await _loadNotes();
    }
  }

  Future<void> _checkSwipeHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('swipe_hint_shown') ?? false) return;
    await prefs.setBool('swipe_hint_shown', true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('← 밀어서 메모를 삭제할 수 있어요'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _scheduleIfNeeded() async {
    if (!kIsWeb && _notes.isNotEmpty) {
      await NotificationService.instance.scheduleReminders();
    }
  }

  // ─── 노트 저장 + 백그라운드 분류 ────────────────────────────────────────────
  Future<void> _submit() async {
    final rawText = _inputController.text.trim();
    if (rawText.isEmpty || _submitting) return;
    final text = rawText.length > 2000 ? rawText.substring(0, 2000) : rawText;
    setState(() => _submitting = true);

    try {
      final note = await DatabaseHelper.instance.createNote(text);
      if (!mounted) return;
      _inputController.clear();
      setState(() {
        _notes.insert(0, note);
        _submitting = false;
      });
      _listKey.currentState?.insertItem(0, duration: const Duration(milliseconds: 350));
      _scheduleIfNeeded();
      _checkSwipeHint();
      _classifyInBackground(note);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('저장하지 못했어요. 다시 시도해줘요.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _classifyInBackground(Note note) {
    ClassifierService.classify(note.content).then((category) async {
      if (category == null || note.id == null) return;
      await DatabaseHelper.instance.updateNoteCategory(note.id!, category);
      if (!mounted) return;
      setState(() {
        final idx = _notes.indexWhere((n) => n.id == note.id);
        if (idx != -1) _notes[idx] = _notes[idx].copyWith(category: category);
      });
    });
  }

  // ─── 네비게이션 ──────────────────────────────────────────────────────────────
  void _openNoteById(int noteId) async {
    final note = await DatabaseHelper.instance.readNote(noteId);
    if (note == null || !mounted) return;
    _openNote(note);
  }

  void _openNote(Note note) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteDetailScreen(
          note: note,
          onDeleted: _refreshCurrentView,
          onEdited: (updated) {
            setState(() {
              final idx = _notes.indexWhere((n) => n.id == updated.id);
              if (idx != -1) _notes[idx] = updated;
            });
          },
        ),
      ),
    );
  }

  // ─── 검색 ─────────────────────────────────────────────────────────────────
  void _setMode(_AppMode mode) {
    if (_isSearching) _exitSearch();
    setState(() => _mode = mode);
  }

  void _enterSearch() => setState(() {
        _isSearching = true;
        _searchQuery = '';
        _selectedCategory = null;
      });

  void _exitSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
    });
    _searchController.clear();
    _loadNotes();
  }

  // ─── 빌드 ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            if (!_isSearching) _buildModeToggle(),
            Expanded(child: _buildContent()),
            if (_mode == _AppMode.notes) _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_mode == _AppMode.todos) return const TodoScreen();
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        if (_hasCategoryData && !_isSearching) _buildCategoryFilter(),
        Expanded(
          child: _notes.isEmpty ? _buildEmptyState() : _buildNoteList(),
        ),
      ],
    );
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
        child: Row(
          children: [
            _modeTab('메모', _AppMode.notes),
            _modeTab('투두', _AppMode.todos),
          ],
        ),
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
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.07),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.45),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_isSearching) ...[
            Expanded(
              child: TextField(
                controller: _searchController,
                autofocus: true,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  hintText: '메모 검색...',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onChanged: (q) {
                  setState(() => _searchQuery = q);
                  _searchNotes(q);
                },
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 22,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
              onPressed: _exitSearch,
            ),
          ] else ...[
            GestureDetector(
              onTap: _enterSearch,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Noting',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: Theme.of(context).colorScheme.onSurface,
                      )),
                  Text('${_notes.length}개의 생각',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                        letterSpacing: 0.2,
                      )),
                ],
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.settings_outlined, size: 22,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
              onPressed: () {
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
                    .then((_) => _refreshCurrentView());
              },
            ),
          ],
        ],
      ),
    );
  }

  Color _catColor(String? cat) {
    if (cat == null) return Theme.of(context).colorScheme.primary;
    final i = _categories.indexOf(cat);
    return Color(_palette[i < 0 ? 0 : i % _palette.length].value);
  }

  Widget _buildCategoryFilter() {
    final filters = [null, ..._categories];
    final labels = ['전체', ..._categories];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
      child: Row(
        children: [
          ...List.generate(filters.length, (i) {
            final cat = filters[i];
            final selected = _selectedCategory == cat;
            final color = _catColor(cat);

            return GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat),
              onLongPress: cat == null
                  ? null
                  : () => _deleteCategoryDialog(cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? color
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.06),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? Colors.white
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
                  ),
                ),
              ),
            );
          }),
          // + 카테고리 추가 버튼
          GestureDetector(
            onTap: _addCategoryDialog,
            child: Container(
              margin: const EdgeInsets.only(right: 20),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.2),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(Icons.add,
                  size: 16,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.4)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addCategoryDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('새 카테고리',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.text,
          decoration: InputDecoration(
            hintText: '카테고리 이름',
            hintStyle: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.35)),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('취소',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5)))),
          TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim()),
              child: Text('추가',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await CategoryService.add(name);
    if (!mounted) return;
    setState(() {
      if (!_categories.contains(name)) _categories.add(name);
    });
  }

  Future<void> _deleteCategoryDialog(String cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("'$cat' 삭제",
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text('카테고리를 삭제해도 기존 메모의 태그는 유지돼요.',
            style: TextStyle(fontSize: 14)),
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
              child: Text('삭제',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    await CategoryService.remove(cat);
    if (!mounted) return;
    setState(() {
      _categories.remove(cat);
      if (_selectedCategory == cat) _selectedCategory = null;
    });
  }

  Future<void> _assignCategoryDialog(Note note) async {
    final cats = _categories;
    final selected = await showModalBottomSheet<String>(
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text('카테고리 선택',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...cats.map((cat) {
              final isCurrent = note.category == cat;
              final color = _catColor(cat);
              return ListTile(
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: color, shape: BoxShape.circle),
                ),
                title: Text(cat),
                trailing: isCurrent
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary,
                        size: 18)
                    : null,
                onTap: () => Navigator.of(ctx).pop(cat),
              );
            }),
            ListTile(
              leading: Icon(Icons.close,
                  size: 16,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.4)),
              title: Text('카테고리 없음',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5))),
              onTap: () => Navigator.of(ctx).pop(''),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final newCat = selected.isEmpty ? null : selected;
    await DatabaseHelper.instance.updateNoteCategory(note.id!, newCat);
    setState(() {
      final idx = _notes.indexWhere((n) => n.id == note.id);
      if (idx != -1) {
        _notes[idx] = _notes[idx].copyWith(
          category: newCat,
          clearCategory: newCat == null,
        );
      }
    });
  }

  Widget _buildEmptyState() {
    if (_isSearching) {
      return Center(
        child: Text('검색 결과가 없어',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
            )),
      );
    }
    if (_selectedCategory != null) {
      final label = _selectedCategory ?? '';
      return Center(
        child: Text('$label 메모가 없어',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
            )),
      );
    }
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
          Text('지금 드는 생각을 아래에 써봐',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
              )),
        ],
      ),
    );
  }

  Widget _buildNoteList() {
    // 카테고리 필터 활성 시 → 일반 ListView (AnimatedList 불필요)
    if (_selectedCategory != null) {
      final filtered =
          _notes.where((n) => n.category == _selectedCategory).toList();
      if (filtered.isEmpty) return _buildEmptyState();
      return ListView.builder(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        itemCount: filtered.length,
        itemBuilder: (_, i) =>
            _buildNoteItem(filtered[i], const AlwaysStoppedAnimation(1.0)),
      );
    }

    return AnimatedList(
      key: _listKey,
      initialItemCount: _notes.length,
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      itemBuilder: (_, index, animation) {
        if (index >= _notes.length) return const SizedBox.shrink();
        return _buildNoteItem(_notes[index], animation);
      },
    );
  }

  Widget _buildNoteItem(Note note, Animation<double> animation) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: SizeTransition(
        sizeFactor: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: Dismissible(
          key: ValueKey(note.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 28),
            color: Theme.of(context).colorScheme.error.withOpacity(0.1),
            child: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error.withOpacity(0.7)),
          ),
          confirmDismiss: (_) => _confirmDismiss(note),
          onDismissed: (_) async {
            final idx = _notes.indexOf(note);
            if (idx == -1) return;
            setState(() => _notes.removeAt(idx));
            _listKey.currentState?.removeItem(
              idx,
              (_, anim) => _buildNoteItem(note, anim),
              duration: const Duration(milliseconds: 200),
            );
            if (note.id != null) {
              final deleted = await DatabaseHelper.instance.deleteNote(note.id!);
              if (deleted == 0 && mounted) _loadNotes();
            }
          },
          child: InkWell(
            onTap: () => _openNote(note),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.content,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSerifKr(
                      fontSize: 15,
                      height: 1.6,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.88),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (note.category != null) ...[
                        _buildCategoryChip(note.category!,
                            onTap: () => _assignCategoryDialog(note)),
                        const SizedBox(width: 8),
                      ] else ...[
                        _buildAddCategoryChip(note),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        _relativeTime(note.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(height: 1, thickness: 0.5,
                      color: Theme.of(context).dividerColor),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String category, {VoidCallback? onTap}) {
    final color = _catColor(category);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3), width: 0.5),
        ),
        child: Text(
          category,
          style: TextStyle(
            fontSize: 10,
            color: color,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _buildAddCategoryChip(Note note) {
    return GestureDetector(
      onTap: () => _assignCategoryDialog(note),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.18),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add,
                size: 9,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.3)),
            const SizedBox(width: 2),
            Text('태그',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.3),
                  letterSpacing: 0.2,
                )),
          ],
        ),
      ),
    );
  }

  Future<bool?> _confirmDismiss(Note note) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('메모 삭제',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text('이 메모를 삭제할까요?', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('취소',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('삭제',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocus,
                maxLines: 5,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: '지금 무슨 생각해?',
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
                    fontSize: 15,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedOpacity(
            opacity: _submitting ? 0.4 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: GestureDetector(
              onTap: _submit,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_upward_rounded, size: 20,
                    color: Theme.of(context).colorScheme.onPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return DateFormat('M월 d일').format(dt);
  }
}
