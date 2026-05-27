import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/todo.dart';
import '../models/time_record.dart';
import '../utils/planner_colors.dart';

const _kBg = Color(0xFFF0EFF8);

// 분 단위 시각을 10분 단위로 반올림 (플래너 셀 경계 정렬 → 경계 겹침 방지)
int _round10(int minutes) => ((minutes + 5) ~/ 10) * 10;

class PlannerScreen extends StatefulWidget {
  final DateTime date;
  final List<Todo> todos;
  // todoId → 해당 투두의 모든 시간 기록
  final Map<int, List<TimeRecord>> timeRecords;

  const PlannerScreen({
    super.key,
    required this.date,
    required this.todos,
    this.timeRecords = const {},
  });

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  final _plannerKey = GlobalKey();
  bool _saving = false;

  Future<void> _exportImage() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final boundary = _plannerKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null || !mounted) return;

      if (kIsWeb) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('스크린샷으로 저장해줘요!'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      final mm = widget.date.month.toString().padLeft(2, '0');
      final dd = widget.date.day.toString().padLeft(2, '0');
      final filePath =
          '${dir.path}/planner_${widget.date.year}$mm$dd.png';
      await File(filePath).writeAsBytes(bytes.buffer.asUint8List());

      await Share.shareXFiles([XFile(filePath)]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공유에 실패했어요.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: Colors.white54),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white54),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.ios_share_rounded,
                  size: 20, color: Colors.white54),
              onPressed: _exportImage,
              tooltip: '공유',
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: 375,
            height: 667, // 고정 9:16 사이즈 — FittedBox가 화면에 맞게 스케일
            child: RepaintBoundary(
              key: _plannerKey,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(28, 35, 28, 52),
                child: _buildCard(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── 메인 카드 ───────────────────────────────────────────────────────────────
  Widget _buildCard() {
    final colorMap = <int, Color>{};
    for (int i = 0; i < widget.todos.length; i++) {
      final id = widget.todos[i].id;
      if (id != null) colorMap[id] = plannerColorAt(i);
    }

    // 모든 시간 범위 수집: TimeRecord 기반 + todo.startTime/endTime (레거시)
    final ranges = <_TimeRange>[];
    for (final todo in widget.todos) {
      final id = todo.id;
      if (id == null) continue;
      // TimeRecord 기반 (타이머 기록)
      final records = widget.timeRecords[id] ?? [];
      for (final r in records) {
        // 시작·끝을 10분 단위로 반올림해서 셀 경계에서 색이 겹치지 않게 함
        final s = _round10(r.startMinutes);
        final e = _round10(r.endMinutes ?? r.startMinutes + 60);
        if (e > s) ranges.add(_TimeRange(id, s, e));
      }
      // 레거시: todo.startTime/endTime (수동 입력, TimeRecord 없을 때만)
      if (records.isEmpty && todo.startMinutes != null) {
        final s = _round10(todo.startMinutes!);
        final e = _round10(todo.endMinutes ?? todo.startMinutes! + 60);
        if (e > s) ranges.add(_TimeRange(id, s, e));
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.fromLTRB(22, 17, 22, 55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 좌측 열: 체크리스트 + 새벽 그리드 (0~5시)
                Expanded(
                  flex: 50,
                  child: Column(
                    children: [
                      Expanded(
                        flex: 67,
                        child: _buildChecklist(colorMap),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        flex: 33,
                        child: _buildTimeGrid(
                          const [0, 1, 2, 3, 4, 5],
                          colorMap,
                          ranges,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 우측 열: 낮 그리드 (6~17시) + 저녁 그리드 (18~23시)
                Expanded(
                  flex: 50,
                  child: Column(
                    children: [
                      Expanded(
                        flex: 67,
                        child: _buildTimeGrid(
                          const [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17],
                          colorMap,
                          ranges,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        flex: 33,
                        child: _buildTimeGrid(
                          const [18, 19, 20, 21, 22, 23],
                          colorMap,
                          ranges,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 날짜 헤더 ───────────────────────────────────────────────────────────────
  Widget _buildDateHeader() {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final wd = weekdays[widget.date.weekday - 1];
    final mm = widget.date.month.toString().padLeft(2, '0');
    final dd = widget.date.day.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        '$wd $mm.$dd.',
        style: const TextStyle(
          fontFamily: 'Samanco',
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A2E),
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  // ─── 체크리스트 (12슬롯 고정) ────────────────────────────────────────────────
  Widget _buildChecklist(Map<int, Color> colorMap) {
    const maxSlots = 12;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rowH = constraints.maxHeight / maxSlots;
          return Column(
            children: List.generate(maxSlots, (i) {
              return SizedBox(
                height: rowH,
                child: i < widget.todos.length
                    ? _buildCheckRow(
                        widget.todos[i],
                        plannerColorAt(i),
                      )
                    : _buildEmptyRow(),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildCheckRow(Todo todo, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          todo.done ? Icons.check_box : Icons.check_box_outline_blank,
          size: 15,
          color:
              todo.done ? const Color(0xFF333333) : const Color(0xFFCCCCCC),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            todo.text,
            style: TextStyle(
              fontFamily: 'Samanco',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: todo.done
                  ? const Color(0xFF888888)
                  : const Color(0xFF1A1A1A),
              height: 1.2,
              decoration:
                  todo.done ? TextDecoration.lineThrough : TextDecoration.none,
              decorationColor: const Color(0xFFAAAAAA),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ],
    );
  }

  Widget _buildEmptyRow() {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.check_box_outline_blank,
            size: 15, color: Color(0xFFDDDDDD)),
      ],
    );
  }

  // ─── 시간 그리드 ─────────────────────────────────────────────────────────────
  Widget _buildTimeGrid(
    List<int> hours,
    Map<int, Color> colorMap,
    List<_TimeRange> ranges,
  ) {
    final showHint = ranges.isEmpty && hours.contains(9);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CustomPaint(
          painter: _GridPainter(
            hours: hours,
            ranges: ranges,
            colorMap: colorMap,
            showHint: showHint,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

// 시간 범위 단순 데이터 클래스
class _TimeRange {
  final int todoId;
  final int start; // 분 단위
  final int end;   // 분 단위
  const _TimeRange(this.todoId, this.start, this.end);
}

// ─── 그리드 페인터 ────────────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  final List<int> hours;
  final List<_TimeRange> ranges;
  final Map<int, Color> colorMap;
  final bool showHint;

  const _GridPainter({
    required this.hours,
    required this.ranges,
    required this.colorMap,
    this.showHint = false,
  });

  static String _label(int h) {
    if (h == 0) return '12';
    if (h <= 12) return '$h';
    return '${h - 12}';
  }

  @override
  void paint(Canvas canvas, Size size) {
    const double labelW = 22;
    final double gridW = size.width - labelW;
    final double rowH = size.height / hours.length;
    final double colW = gridW / 6; // 10분 단위
    final double barH = rowH * 0.76;
    final double barOff = (rowH - barH) / 2;

    final linePaint = Paint()
      ..color = const Color(0xFFE5E4F0)
      ..strokeWidth = 0.5;

    // 가로선
    for (int i = 0; i <= hours.length; i++) {
      final y = i * rowH;
      canvas.drawLine(Offset(labelW, y), Offset(size.width, y), linePaint);
    }

    // 세로선
    for (int c = 0; c <= 6; c++) {
      final x = labelW + c * colW;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }

    // 시간 레이블
    for (int i = 0; i < hours.length; i++) {
      final label = _label(hours[i]);
      final y = i * rowH;
      final pb = ui.ParagraphBuilder(
        ui.ParagraphStyle(textAlign: TextAlign.right, maxLines: 1),
      )
        ..pushStyle(ui.TextStyle(
          color: const Color(0xFFBBBBCC),
          fontSize: 8,
          fontWeight: ui.FontWeight.w400,
        ))
        ..addText(label);
      final para = pb.build()
        ..layout(const ui.ParagraphConstraints(width: 19));
      canvas.drawParagraph(para, Offset(0, y + rowH / 2 - 5));
    }

    // 작업 블록 — 모든 _TimeRange를 그림 (같은 todoId라도 여러 세션 가능)
    for (final range in ranges) {
      final color = colorMap[range.todoId] ?? kPlannerColors[0];

      int s = range.start;
      while (s < range.end) {
        final ch = s ~/ 60;
        final rowIdx = hours.indexOf(ch);
        if (rowIdx == -1) {
          s = (ch + 1) * 60;
          continue;
        }
        final cm = s % 60;
        final nextH = (ch + 1) * 60;
        final segEnd = math.min(range.end, nextH);
        final sc = cm ~/ 10;
        final em = segEnd % 60;
        final ec = (em == 0 && segEnd > s) ? 6 : ((em + 9) ~/ 10);

        if (ec > sc) {
          final x1 = labelW + sc * colW;
          final x2 = labelW + ec * colW;
          final y = rowIdx * rowH + barOff;
          final r = math.min(barH / 2, (x2 - x1) / 2);

          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x1 + 1, y, x2 - x1 - 2, barH),
              Radius.circular(r),
            ),
            Paint()..color = color,
          );
        }
        s = segEnd;
      }
    }

    // 시간 기록이 없는 메인 그리드에 힌트 표시
    if (showHint) {
      final pb = ui.ParagraphBuilder(
        ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 2),
      )
        ..pushStyle(ui.TextStyle(
          color: const Color(0xFFCCCCDD),
          fontSize: 9,
          fontWeight: ui.FontWeight.w400,
        ))
        ..addText('▶ 탭하면\n시간 기록');
      final para = pb.build()
        ..layout(ui.ParagraphConstraints(width: gridW));
      canvas.drawParagraph(
        para,
        Offset(labelW, size.height / 2 - 12),
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.hours.length != hours.length ||
      old.ranges.length != ranges.length ||
      old.showHint != showHint;
}
