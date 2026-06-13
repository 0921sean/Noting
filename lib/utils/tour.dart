import 'package:flutter/foundation.dart';

/// 설정 → 사용법에서 코치마크 투어를 재개하려고 쓰는 글로벌 트리거.
///
/// 단순 String이 아니라 (kind, seq)를 쓰는 이유:
/// ValueNotifier는 동일 값이면 리스너를 안 부른다. 사용자가 같은 투어를
/// 두 번 연속 요청해도 매번 동작하게 시퀀스를 같이 넣는다.
class TourRequest {
  final String kind; // 'memo' | 'todo'
  final int seq;
  const TourRequest(this.kind, this.seq);
}

class TourTrigger {
  static int _counter = 0;
  static final ValueNotifier<TourRequest?> notifier =
      ValueNotifier<TourRequest?>(null);

  static void start(String kind) {
    _counter++;
    notifier.value = TourRequest(kind, _counter);
  }
}
