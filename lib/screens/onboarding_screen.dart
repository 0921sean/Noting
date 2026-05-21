import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingPage(
      emoji: '✦',
      title: '생각을 바로 기록해요',
      description: '아래 입력창에 지금 드는 생각을 적어요.\n나중에 알림으로 다시 만나게 될 거예요.',
      highlight: null,
    ),
    _OnboardingPage(
      emoji: '☑',
      title: '오늘 할 일을 관리해요',
      description: '투두 탭에서 할 일을 추가하고\n드래그로 순서를 바꿀 수 있어요.',
      highlight: null,
    ),
    _OnboardingPage(
      emoji: '▶',
      title: '타이머로 시간을 기록해요',
      description: '할 일 옆 ▶ 를 누르면 지금 시각이 시작시간으로 기록돼요.\n다시 누르면 종료시간까지 자동으로 저장해요.',
      highlight: '09:23~ +14분',
    ),
    _OnboardingPage(
      emoji: '🗓',
      title: '오늘의 플래너를 확인해요',
      description: '날짜 옆 "플래너" 버튼을 누르면\n색깔 시간표가 생성돼요.\n공유 버튼으로 인스타 스토리에 바로 올릴 수 있어요.',
      highlight: null,
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 상단 Skip
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isLast)
                    TextButton(
                      onPressed: _finish,
                      child: Text(
                        '건너뛰기',
                        style: TextStyle(
                          fontSize: 14,
                          color: cs.onSurface.withOpacity(0.4),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 페이지 내용
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _buildPage(_pages[i], cs),
              ),
            ),

            // 하단 영역: 점 + 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  // 점 인디케이터
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _page == i ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _page == i
                              ? cs.primary
                              : cs.onSurface.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  // 다음 / 시작 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: () {
                        if (isLast) {
                          _finish();
                        } else {
                          _controller.nextPage(
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        isLast ? '시작하기' : '다음',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            page.emoji,
            style: TextStyle(
              fontSize: 64,
              color: cs.primary.withOpacity(0.85),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              letterSpacing: -0.5,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: cs.onSurface.withOpacity(0.55),
              height: 1.65,
            ),
          ),
          if (page.highlight != null) ...[
            const SizedBox(height: 24),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF9AE7D).withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                page.highlight!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFD4843A),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OnboardingPage {
  final String emoji;
  final String title;
  final String description;
  final String? highlight;

  const _OnboardingPage({
    required this.emoji,
    required this.title,
    required this.description,
    required this.highlight,
  });
}
