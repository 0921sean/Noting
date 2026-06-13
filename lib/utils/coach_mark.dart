import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:showcaseview/showcaseview.dart';

/// 앱 테마 색상 + Noto Sans KR 폰트로 스타일을 통일한 코치마크(Showcase).
/// 홈/투두 등 여러 화면에서 동일한 룩으로 쓰기 위한 헬퍼.
/// 배경(barrier) 어디를 탭해도 다음 단계로 넘어간다.
///
/// 주의: `Builder`로 감싸서 inner context가 ShowCaseWidget 아래에 위치하도록
/// 한다. 그래야 `ShowCaseWidget.of(ctx)` 호출이 ancestor lookup으로
/// ShowCaseWidget을 찾을 수 있다. (HomeScreen State의 context는 위에
/// 있어서 못 찾았던 게 메모 가이드의 onBarrierClick이 안 먹던 원인.)
Widget buildCoachMark({
  required BuildContext context,
  required GlobalKey key,
  required String title,
  required String description,
  required Widget child,
  ShapeBorder targetShapeBorder = const RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  ),
  EdgeInsets targetPadding = EdgeInsets.zero,
}) {
  return Builder(builder: (ctx) {
    final cs = Theme.of(ctx).colorScheme;
    return Showcase(
      key: key,
      title: title,
      description: description,
      targetShapeBorder: targetShapeBorder,
      targetPadding: targetPadding,
      tooltipBackgroundColor: cs.surface,
      textColor: cs.onSurface,
      tooltipBorderRadius: BorderRadius.circular(14),
      tooltipPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      onBarrierClick: () {
        try {
          ShowCaseWidget.of(ctx).next();
        } catch (_) {}
      },
      titleTextStyle: GoogleFonts.notoSansKr(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
        letterSpacing: -0.2,
      ),
      descTextStyle: GoogleFonts.notoSansKr(
        fontSize: 13,
        height: 1.5,
        color: cs.onSurface.withOpacity(0.7),
      ),
      child: child,
    );
  });
}
