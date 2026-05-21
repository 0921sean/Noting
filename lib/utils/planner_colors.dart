import 'package:flutter/material.dart';

// COLOR_12 파스텔 팔레트 — 원본 Python hazel_nut_story.py의 COLOR_12와 동일
const List<Color> kPlannerColors = [
  Color(0xFFFA7D7C),
  Color(0xFFF9AE7D),
  Color(0xFFF7FC7F),
  Color(0xFF7DF97E),
  Color(0xFF80E0FA),
  Color(0xFF7D7DFA),
  Color(0xFFCA7CFA),
  Color(0xFFCD7D7E),
  Color(0xFFC5967B),
  Color(0xFFCDCD7D),
  Color(0xFF7FCD7F),
  Color(0xFF80BDCD),
];

Color plannerColorAt(int index) =>
    kPlannerColors[index % kPlannerColors.length];
