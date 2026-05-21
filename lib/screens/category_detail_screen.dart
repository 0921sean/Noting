import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import '../services/supabase_service.dart';
import 'note_detail_screen.dart';

class CategoryDetailScreen extends StatefulWidget {
  final String? category; // null = 미분류, '전체' = 전부
  final List<Note> initialNotes;

  const CategoryDetailScreen({
    super.key,
    required this.category,
    required this.initialNotes,
  });

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  late List<Note> _notes;
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();
  bool _submitting = false;

  String get _title => widget.category ?? '미분류';
  bool get _isAll => widget.category == '전체';

  @override
  void initState() {
    super.initState();
    _notes = List.from(widget.initialNotes);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      var note = await SupabaseService.createNote(text);
      // 전체/미분류가 아닌 카테고리에서 추가하면 해당 카테고리 적용
      if (widget.category != null && !_isAll) {
        await SupabaseService.updateNoteCategory(note.id!, widget.category);
        note = note.copyWith(category: widget.category);
      }
      if (!mounted) return;
      _inputController.clear();
      setState(() => _notes.insert(0, note));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('저장하지 못했어요. 다시 시도해줘요.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openNote(Note note) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NoteDetailScreen(
        note: note,
        onDeleted: () => setState(
            () => _notes.removeWhere((n) => n.id == note.id)),
        onEdited: (updated) {
          setState(() {
            final idx = _notes.indexWhere((n) => n.id == updated.id);
            if (idx != -1) _notes[idx] = updated;
          });
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 18, color: cs.onSurface.withOpacity(0.6)),
          onPressed: () => Navigator.of(context).pop(_notes),
        ),
        title: Text(
          _title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_notes.length}개',
                style: TextStyle(
                    fontSize: 13, color: cs.onSurface.withOpacity(0.4)),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _notes.isEmpty
                ? Center(
                    child: Text(
                      '아직 메모가 없어요\n아래에서 추가해봐요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.7,
                        color: cs.onSurface.withOpacity(0.35),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 16),
                    itemCount: _notes.length,
                    itemBuilder: (_, i) => _buildNoteItem(_notes[i]),
                  ),
          ),
          // 입력창
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 16),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                top: BorderSide(
                    color: Theme.of(context).dividerColor, width: 0.5),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocus,
                        maxLines: 5,
                        minLines: 1,
                        textInputAction: TextInputAction.newline,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          hintText: _isAll
                              ? '지금 무슨 생각해?'
                              : '$_title에 추가...',
                          hintStyle: TextStyle(
                              color: cs.onSurface.withOpacity(0.3),
                              fontSize: 15),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                        style: TextStyle(
                            fontSize: 15, height: 1.5, color: cs.onSurface),
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
                            color: cs.primary, shape: BoxShape.circle),
                        child: Icon(Icons.arrow_upward_rounded,
                            size: 20, color: cs.onPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteItem(Note note) {
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 28),
        color: Theme.of(context).colorScheme.error.withOpacity(0.1),
        child: Icon(Icons.delete_outline,
            color: Theme.of(context).colorScheme.error.withOpacity(0.7)),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('메모 삭제',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: const Text('이 메모를 삭제할까요?',
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
      ),
      onDismissed: (_) async {
        setState(() => _notes.removeWhere((n) => n.id == note.id));
        if (note.id != null) await SupabaseService.deleteNote(note.id!);
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
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.88),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _relativeTime(note.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.4),
                ),
              ),
              const SizedBox(height: 14),
              Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Theme.of(context).dividerColor),
            ],
          ),
        ),
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
