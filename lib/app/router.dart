import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/screens/auth/login_screen.dart';
import 'package:tapsense/screens/auth/signup_screen.dart';
import 'package:tapsense/screens/onboarding/onboarding_screen.dart';
import 'package:tapsense/screens/home/home_screen.dart';
import 'package:tapsense/screens/pairing/pairing_screen.dart';
import 'package:tapsense/screens/scanner/scanner_screen.dart';
import 'package:tapsense/screens/confirm_log/confirm_log_screen.dart';
import 'package:tapsense/screens/insights/insights_screen.dart';
import 'package:tapsense/screens/settings/settings_screen.dart';

final _auth = Supabase.instance.client.auth;

final appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: GoRouterRefreshStream(_auth.onAuthStateChange),
  redirect: (context, state) {
    final session = _auth.currentSession;
    final onAuth = state.matchedLocation == '/login' ||
        state.matchedLocation == '/signup';
    if (session == null && !onAuth) return '/login';
    if (session != null && onAuth) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login',      builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/signup',     builder: (_, __) => const SignupScreen()),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    GoRoute(path: '/home',       builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/pairing',    builder: (_, __) => const PairingScreen()),
    GoRoute(path: '/scanner',    builder: (_, __) => const ScannerScreen()),
    GoRoute(path: '/insights',   builder: (_, __) => const InsightsScreen()),
    GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    GoRoute(
      path: '/confirm-log',
      builder: (_, state) {
        final data = state.extra as Map<String, dynamic>? ?? {
          'triggerType': 'manual',
          'merchantName': null,
          'merchantUen': null,
          'amount': null,
          'rawQr': null,
        };
        return ConfirmLogScreen(data: data);
      },
    ),
  ],
);

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<AuthState> stream) {
    stream.listen((_) => notifyListeners());
  }
}