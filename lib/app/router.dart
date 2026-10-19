import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/screens/auth/login_screen.dart';
import 'package:tapsense/screens/auth/signup_screen.dart';
import 'package:tapsense/screens/home/home_screen.dart';
import 'package:tapsense/screens/onboarding/onboarding_screen.dart';
import 'package:tapsense/screens/pairing/pairing_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final isAuth = session != null;
    final isAuthRoute = state.matchedLocation == '/login' ||
                        state.matchedLocation == '/signup';

    if (!isAuth && !isAuthRoute && state.matchedLocation != '/onboarding') {
      return '/login';
    }
    if (isAuth && isAuthRoute) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/', redirect: (_, __) => '/login'),
    GoRoute(path: '/login',      builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/signup',     builder: (_, __) => const SignupScreen()),
    GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
    GoRoute(path: '/home',       builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/pairing', builder: (_, __) => const PairingScreen()),
  ],
);