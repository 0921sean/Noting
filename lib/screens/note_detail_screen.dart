import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import '../database/database_helper.dart';

class NoteDetailScreen extends StatefulWidget {
  final Note note;
  final VoidCallback? onDeleted;
  final Function(Note)? onEdited;

  const NoteDetailScreen({
    super.key,
    required this.note,
    this.onDeleted,
    this.onEdited,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  late Note _note;
  bool _isEditing = false;
  late TextEditingController _editController;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _editController = TextEditingController(text: _note.content);
  }

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  Future<void> _saveEdit() async {
    final raw = _editController.text.trim();
    final text = raw.length > 2000 ? raw.substring(0, 2000) : raw;
    if (text.isEmpty) {
      setState(() => _isEditing = false);
      return;
    }
    if (text == _note.content) {
      setState(() => _isEditing = false);
      return;
    }
    final updated = _note.copyWith(content: text);
    await DatabaseHelper.instance.updateNote(updated);
    if (!mounted) return;
    setState(() {
      _note = updated;
      _isEditing = false;
    });
    widget.onEdited?.call(updated);
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _editController.text = _note.content;
      _editController.selection = TextSelection.collapsed(
        offset: _editController.text.length,
      );
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editController.text = _note.content;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isEditing,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        await _saveEdit();
        if (mounted) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: Icon(
              _isEditing ? Icons.close : Icons.arrow_back_ios_new,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
            onPressed: () {
              if (_isEditing) {
                _cancelEditing();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            if (_isEditing)
              IconButton(
                icon: Icon(
                  Icons.check_rounded,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onPressed: _saveEdit,
              )
            else ...[
              IconButton(
                icon: Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
                onPressed: _startEditing,
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
                onPressed: _confirmDelete,
              ),
            ],
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(_note.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: _isEditing
                      ? TextField(
                          controller: _editController,
                          maxLines: null,
                          expands: true,
                          autofocus: true,
                          textAlignVertical: TextAlignVertical.top,
                          keyboardType: TextInputType.multiline,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: GoogleFonts.notoSerifKr(
                            fontSize: 18,
                            height: 1.8,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.88),
                            letterSpacing: 0.1,
                          ),
                        )
                      : GestureDetector(
                          onTap: _startEditing,
                          behavior: HitTestBehavior.opaque,
                          child: SingleChildScrollView(
                            child: SelectableText(
                              _note.content,
                              style: GoogleFonts.notoSerifKr(
                                fontSize: 18,
                                height: 1.8,
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.88),
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ),
                ),
                if (!_isEditing)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '탭하여 편집',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.28),
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return '오늘 ${DateFormat('HH:mm').format(dt)}';
    if (diff.inDays == 1) return '어제 ${DateFormat('HH:mm').format(dt)}';
    if (diff.inDays < 7) return '${diff.inDays}일 전 ${DateFormat('HH:mm').format(dt)}';
    return DateFormat('yyyy년 M월 d일 HH:mm').format(dt);
  }

  void _confirmDelete() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('메모 삭제', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: const Text('이 메모를 삭제할까요?', style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              '취소',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (_note.id != null) {
                await DatabaseHelper.instance.deleteNote(_note.id!);
              }
              if (mounted) {
                Navigator.of(context).pop();
                widget.onDeleted?.call();
              }
            },
            child: Text('삭제', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}
