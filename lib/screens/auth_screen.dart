import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/analytics_service.dart';
import 'home_screen.dart';
import 'reset_password_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;
  String? _error;

  static const _redirectUrl = 'io.supabase.noting://login-callback/';

  @override
  void initState() {
    super.initState();
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.signedIn) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
      // 비밀번호 재설정 링크 클릭 후 앱으로 돌아왔을 때
      if (data.event == AuthChangeEvent.passwordRecovery) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pw = _pwCtrl.text;
    if (email.isEmpty || pw.isEmpty) {
      setState(() => _error = '이메일과 비밀번호를 입력해줘요');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (_isLogin) {
        await Supabase.instance.client.auth
            .signInWithPassword(email: email, password: pw);
      } else {
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: pw,
          emailRedirectTo: _redirectUrl,
        );
        // 가입 이벤트는 메일 확인 전이라도 발송 (가입 의도 자체를 추적)
        unawaited(AnalyticsService.signUp());
      }
      if (!mounted) return;
      // 이메일 인증이 켜져 있으면 signUp 직후엔 세션이 없다.
      // 그땐 홈으로 보내지 말고 "확인 메일을 보냈어요" 안내 후 로그인 화면 유지.
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        setState(() => _isLogin = true); // 로그인 화면으로 전환
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('$email 로 확인 메일을 보냈어요.\n메일을 열어 링크를 눌러주세요.'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 6),
          ),
        );
        return;
      }
      // 로그인 / 가입+자동인증 성공 → PostHog identify
      unawaited(AnalyticsService.identify(session.user.id));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } on AuthException catch (e) {
      setState(() => _error = _koreanError(e.message));
    } catch (_) {
      setState(() => _error = '오류가 발생했어요. 다시 시도해봐요.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = '이메일을 먼저 입력해줘요');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: _redirectUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$email 로 비밀번호 재설정 메일을 보냈어요'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (_) {
      setState(() => _error = '메일 전송에 실패했어요. 이메일을 확인해줘요.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _koreanError(String msg) {
    if (msg.contains('Invalid login')) return '이메일 또는 비밀번호가 틀렸어요';
    if (msg.contains('already registered')) return '이미 가입된 이메일이에요. 로그인해봐요';
    if (msg.contains('not confirmed')) return '이메일 인증이 필요해요. 받은편지함을 확인해줘요';
    if (msg.contains('Password should be')) return '비밀번호는 8자 이상이어야 해요';
    if (msg.contains('valid email')) return '올바른 이메일 형식이 아니에요';
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 36),
              // 작은 브랜드
              Center(
                child: Text('Noting',
                    style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(0.4),
                      letterSpacing: 0.5,
                    )),
              ),
              const SizedBox(height: 24),
              // 상단 세그먼티드 탭 (로그인 / 회원가입)
              _buildModeTabs(cs),
              const SizedBox(height: 28),
              // 큰 모드 헤딩 + 서브카피
              Text(
                _isLogin ? '돌아왔어요?' : '새 계정 만들기',
                style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700,
                  color: cs.onSurface, letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _isLogin
                    ? '이메일과 비밀번호로 로그인해요.'
                    : '확인 메일을 보내드릴게요. 메일함을 열어주세요.',
                style: TextStyle(
                    fontSize: 13, color: cs.onSurface.withOpacity(0.55),
                    height: 1.5),
              ),
              const SizedBox(height: 28),

              // 이메일
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: '이메일',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 12),

              // 비밀번호
              TextField(
                controller: _pwCtrl,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  helperText: _isLogin ? null : '8자 이상',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),

              // 비밀번호 찾기
              if (_isLogin)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _loading ? null : _forgotPassword,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('비밀번호를 잊으셨나요?',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.primary.withOpacity(0.7))),
                  ),
                ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(fontSize: 13, color: cs.error)),
              ],
              const SizedBox(height: 20),

              // 메인 액션 버튼 — 모드별 색/아이콘 차별화
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        _isLogin ? cs.primary : cs.onSurface.withOpacity(0.88),
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _loading
                      ? const SizedBox.shrink()
                      : Icon(
                          _isLogin ? Icons.login_rounded : Icons.person_add_alt_1_rounded,
                          size: 18,
                        ),
                  label: _loading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_isLogin ? '로그인' : '회원가입',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 상단 세그먼티드 탭 ────────────────────────────────────────────────────
  Widget _buildModeTabs(ColorScheme cs) {
    Widget tab(String label, bool isLogin) {
      final selected = _isLogin == isLogin;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (_loading) return;
            setState(() {
              _isLogin = isLogin;
              _error = null;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? cs.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.07),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? cs.onSurface
                      : cs.onSurface.withOpacity(0.45),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [tab('로그인', true), tab('회원가입', false)]),
    );
  }
}
