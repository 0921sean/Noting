import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/todo.dart';

// 타임라인에 사용할 색상 팔레트
const _colors = [
  Color(0xFFD4843A),
  Color(0xFF7C5C3E),
  Color(0xFF8B8070),
  Color(0xFF6B8F71),
  Color(0xFF7B6EA6),
  Color(0xFFB85C38),
  Color(0xFF5B7FA6),
  Color(0xFFA67B5B),
  Color(0xFF4A8FA8),
  Color(0xFF9A7B4B),
  Color(0xFF6B7FA8),
  Color(0xFF8FA86B),
];

class PlannerScreen extends StatefulWidget {
  final DateTime date;
  final List<Todo> todos;

  const PlannerScreen({super.key, required this.date, required this.todos});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  final _plannerKey = GlobalKey();

  List<Todo> get _scheduled =>
      widget.todos.where((t) => t.startTime != null).toList();

  int get _minHour {
    if (_scheduled.isEmpty) return 9;
    return (_scheduled
            .map((t) => (t.startMinutes ?? 540) ~/ 60)
            .reduce(math.min) -
        1)
        .clamp(0, 23);
  }

  int get _maxHour {
    if (_scheduled.isEmpty) return 22;
    return (_scheduled
            .map((t) => ((t.endMinutes ?? t.startMinutes ?? 0) + 59) ~/ 60)
            .reduce(math.max) +
        1)
        .clamp(1, 24);
  }

  Future<void> _exportImage() async {
    try {
      final boundary = _plannerKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final bytes =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('이미지 저장은 준비 중이에요. 스크린샷으로 저장해줘요!'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 18,
              color:
                  Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '${widget.date.month}월 ${widget.date.day}일 플래너',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.download_outlined,
                size: 20,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            onPressed: _exportImage,
            tooltip: '이미지로 저장',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        child: RepaintBoundary(
          key: _plannerKey,
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                if (widget.todos.isNotEmpty) ...[
                  _buildChecklist(),
                  const SizedBox(height: 20),
                ],
                if (_scheduled.isNotEmpty) ...[
                  _buildTimeline(),
                  const SizedBox(height: 20),
                ],
                if (widget.todos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Text('이날 할 일이 없어요',
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.35),
                          )),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    const weekdayKo = ['월', '화', '수', '목', '금', '토', '일'];
    final wd = weekdayKo[widget.date.weekday - 1];
    final done = widget.todos.where((t) => t.done).length;
    final total = widget.todos.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.date.month}월 ${widget.date.day}일 $wd요일',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                total == 0
                    ? '할 일 없음'
                    : '$done / $total 완료',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.45),
                ),
              ),
            ],
          ),
          const Spacer(),
          if (total > 0)
            SizedBox(
              width: 48,
              height: 48,
              child: CustomPaint(
                painter: _DonutPainter(
                  done: done,
                  total: total,
                  color: Theme.of(context).colorScheme.primary,
                  bg: Theme.of(context).colorScheme.onSurface.withOpacity(0.1),
                ),
                child: Center(
                  child: Text(
                    total == 0 ? '' : '${(done / total * 100).round()}%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChecklist() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('할 일',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
                letterSpacing: 0.8,
              )),
          const SizedBox(height: 10),
          ...widget.todos.asMap().entries.map((e) {
            final todo = e.value;
            final color = _colors[e.key % _colors.length];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  // 색상 원
                  Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 10),
                  // 체크/미체크 아이콘
                  Icon(
                    todo.done
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    size: 16,
                    color: todo.done
                        ? color
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.3),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      todo.text,
                      style: TextStyle(
                        fontSize: 14,
                        color: todo.done
                            ? Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4)
                            : Theme.of(context).colorScheme.onSurface,
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
                  if (todo.startTime != null)
                    Text(
                      '${todo.startTime}${todo.endTime != null ? ' ~ ${todo.endTime}' : ''}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.4),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final minH = _minHour;
    final maxH = _maxHour;
    const rowH = 52.0;
    const labelW = 48.0;
    final totalH = (maxH - minH) * rowH;

    // 투두 인덱스 → 색상 매핑
    final colorMap = <int, Color>{};
    for (int i = 0; i < widget.todos.length; i++) {
      final id = widget.todos[i].id;
      if (id != null) colorMap[id] = _colors[i % _colors.length];
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('시간표',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
                letterSpacing: 0.8,
              )),
          const SizedBox(height: 10),
          SizedBox(
            height: totalH,
            child: CustomPaint(
              size: Size.infinite,
              painter: _TimelinePainter(
                todos: _scheduled,
                minHour: minH,
                maxHour: maxH,
                rowHeight: rowH,
                labelWidth: labelW,
                colorMap: colorMap,
                labelColor: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.4),
                lineColor: Theme.of(context).dividerColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 도넛 차트 ───────────────────────────────────────────────────────────────
class _DonutPainter extends CustomPainter {
  final int done;
  final int total;
  final Color color;
  final Color bg;

  const _DonutPainter(
      {required this.done,
      required this.total,
      required this.color,
      required this.bg});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.18;
    final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2),
        radius: size.width / 2 - stroke / 2);

    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false,
        Paint()
          ..color = bg
          ..strokeWidth = stroke
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);

    if (total > 0 && done > 0) {
      canvas.drawArc(
          rect,
          -math.pi / 2,
          math.pi * 2 * done / total,
          false,
          Paint()
            ..color = color
            ..strokeWidth = stroke
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.done != done || old.total != total;
}

// ─── 타임라인 페인터 ─────────────────────────────────────────────────────────
class _TimelinePainter extends CustomPainter {
  final List<Todo> todos;
  final int minHour;
  final int maxHour;
  final double rowHeight;
  final double labelWidth;
  final Map<int, Color> colorMap;
  final Color labelColor;
  final Color lineColor;

  const _TimelinePainter({
    required this.todos,
    required this.minHour,
    required this.maxHour,
    required this.rowHeight,
    required this.labelWidth,
    required this.colorMap,
    required this.labelColor,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barArea = size.width - labelWidth - 8;
    final totalMin = (maxHour - minHour) * 60.0;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5;

    final labelStyle = ui.ParagraphStyle(
      textAlign: TextAlign.right,
      maxLines: 1,
    );

    // 시간 선 + 레이블
    for (int h = minHour; h <= maxHour; h++) {
      final y = (h - minHour) * rowHeight;
      canvas.drawLine(
          Offset(labelWidth, y), Offset(size.width, y), linePaint);

      final pb = ui.ParagraphBuilder(labelStyle)
        ..pushStyle(ui.TextStyle(
          color: labelColor,
          fontSize: 11,
          fontWeight: ui.FontWeight.w400,
        ))
        ..addText('${h.toString().padLeft(2, '0')}:00');
      final para = pb.build()..layout(ui.ParagraphConstraints(width: labelWidth - 8));
      canvas.drawParagraph(para, Offset(0, y - 7));
    }

    // 투두 막대 (겹침 방지 레이어 계산)
    final lanes = <List<_Seg>>[];
    for (final todo in todos) {
      if (todo.id == null) continue;
      final s = todo.startMinutes ?? 0;
      final e = todo.endMinutes ?? (s + 60);
      if (e <= s) continue;

      final seg = _Seg(s, e, todo.id!, todo.text);
      int lane = 0;
      while (lane < lanes.length &&
          lanes[lane].any((existing) => existing.overlaps(seg))) {
        lane++;
      }
      if (lane == lanes.length) lanes.add([]);
      lanes[lane].add(seg);
    }

    final laneW = lanes.isEmpty ? barArea : barArea / lanes.length;

    for (int li = 0; li < lanes.length; li++) {
      for (final seg in lanes[li]) {
        final color = colorMap[seg.id] ?? const Color(0xFFD4843A);
        final sy = (seg.start - minHour * 60) / totalMin * size.height;
        final ey = (seg.end - minHour * 60) / totalMin * size.height;
        final x1 = labelWidth + 8 + li * laneW + 2;
        final x2 = x1 + laneW - 4;
        final h = (ey - sy).clamp(4.0, double.infinity);
        final r = math.min(6.0, h / 2);

        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x1, sy, x2 - x1, h),
          Radius.circular(r),
        );
        canvas.drawRRect(rrect, Paint()..color = color.withOpacity(0.85));

        // 텍스트 (충분히 길 때만)
        if (h > 20 && (x2 - x1) > 30) {
          final tp = ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 1))
            ..pushStyle(ui.TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: ui.FontWeight.w600,
            ))
            ..addText(seg.label);
          final para = tp.build()
            ..layout(ui.ParagraphConstraints(width: x2 - x1 - 6));
          canvas.drawParagraph(para, Offset(x1 + 4, sy + 4));
        }
      }
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => true;
}

class _Seg {
  final int start;
  final int end;
  final int id;
  final String label;
  const _Seg(this.start, this.end, this.id, this.label);
  bool overlaps(_Seg other) => start < other.end && end > other.start;
}
