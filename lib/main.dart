// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/router.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/config/env.dart';
import 'package:tapsense/firebase_options.dart';
import 'package:tapsense/services/debug_log.dart';
import 'package:tapsense/services/fcm_service.dart';
import 'package:tapsense/services/wallet_activity.dart';

// ── Background message handler (must be top-level, not a class method) ────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialised by the time this runs.
  // Nothing to do here — the notification is shown automatically by FCM.
  // You can add local DB writes here later if needed.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Firebase (first, so Crashlytics can catch errors from everything after) ─
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ── Crashlytics ─────────────────────────────────────────────────────────────
  // Off in debug runs so your own testing doesn't flood the dashboard.
  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!kDebugMode);

  // Last debug-log lines get attached to each crash report.
  DebugLog.instance.onLine = FirebaseCrashlytics.instance.log;

  // Flutter framework errors (widget build errors, etc.)
  FlutterError.onError = (details) {
    dlogError('FLUTTER', details.exception, details.stack);
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  // Uncaught async errors
  PlatformDispatcher.instance.onError = (error, stack) {
    dlogError('UNCAUGHT', error, stack);
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // ── Config check ────────────────────────────────────────────────────────────
  if (Env.missing.isNotEmpty) {
    dlog('ENV', 'Missing: ${Env.missing.join(', ')} — '
        'did you run with --dart-define-from-file=env.json ?');
  }

  // ── Supabase ────────────────────────────────────────────────────────────────
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
  );

  WalletActivity.instance.start();
  // ── Push (FCM) ──────────────────────────────────────────────────────────────
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Register FCM token with Supabase once the user is signed in.
  // FcmService listens to auth state changes and handles this automatically.
  FcmService.init();

  dlog('APP', 'started on ${defaultTargetPlatform.name}');

  runApp(const TapSenseApp());
}

class TapSenseApp extends StatefulWidget {
  const TapSenseApp({super.key});

  @override
  State<TapSenseApp> createState() => _TapSenseAppState();
}

class _TapSenseAppState extends State<TapSenseApp> {
  @override
  void initState() {
    super.initState();
    themeNotifier.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TapSense',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeNotifier.mode,
      routerConfig: appRouter,
    );
  }
}