// lib/app/router.dart  — Day 10 update
// Added: /transactions, /wallet-events, /rename-wallet

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
// ── new screens ──
import 'package:tapsense/screens/transactions/transactions_screen.dart';
import 'package:tapsense/screens/wallet_events/wallet_events_screen.dart';
import 'package:tapsense/widgets/rename_wallet_dialog.dart';
import 'package:tapsense/screens/goals/goals_screen.dart';
import 'package:tapsense/services/fcm_service.dart';

final _auth = Supabase.instance.client.auth;

final appRouter = GoRouter(
  initialLocation: '/login',
  refreshListenable: GoRouterRefreshStream(_auth.onAuthStateChange),
  navigatorKey: FcmService.navigatorKey,
  redirect: (context, state) {
    final session = _auth.currentSession;
    final onAuth = state.matchedLocation == '/login' ||
        state.matchedLocation == '/signup';
    if (session == null && !onAuth) return '/login';
    if (session != null && onAuth) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login',        builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/signup',       builder: (_, __) => const SignupScreen()),
    GoRoute(path: '/onboarding',   builder: (_, __) => const OnboardingScreen()),
    GoRoute(path: '/home',         builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/pairing',      builder: (_, __) => const PairingScreen()),
    GoRoute(path: '/scanner',      builder: (_, __) => const ScannerScreen()),
    GoRoute(path: '/insights',     builder: (_, __) => const InsightsScreen()),
    GoRoute(path: '/settings',     builder: (_, __) => const SettingsScreen()),
    // ── Day 10 ──────────────────────────────────────────────────────────────
    GoRoute(path: '/transactions', builder: (_, __) => const TransactionsScreen()),
    GoRoute(path: '/wallet-events',builder: (_, __) => const WalletEventsScreen()),
    GoRoute(path: '/rename-wallet',builder: (_, __) => const RenameWalletScreen()),
    GoRoute(path: '/goals', builder: (_, __) => const GoalsScreen()),
    // ────────────────────────────────────────────────────────────────────────
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
        return const ConfirmLogScreen();
      },
    ),
  ],
);

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<AuthState> stream) {
    stream.listen((_) => notifyListeners());
  }
}