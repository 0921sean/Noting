import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:showcaseview/showcaseview.dart';

/// 앱 테마 색상 + Noto Sans KR 폰트로 스타일을 통일한 코치마크(Showcase).
/// 홈/투두 등 여러 화면에서 동일한 룩으로 쓰기 위한 헬퍼.
Showcase buildCoachMark({
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
  final cs = Theme.of(context).colorScheme;
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
}
