// lib/main.dart

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/router.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/firebase_options.dart';
import 'package:tapsense/services/fcm_service.dart';

// ── Background message handler (must be top-level, not a class method) ────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialised by the time this runs.
  // Nothing to do here — the notification is shown automatically by FCM.
  // You can add local DB writes here later if needed.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Supabase ────────────────────────────────────────────────────────────────
  await Supabase.initialize(
    url: 'https://wtyyodplhdvzjrnwqeuk.supabase.co',
    anonKey: 'sb_publishable_cxI7J6h-L95tyj3wtHnouw_dpkt3n4B',
  );

  // ── Firebase ────────────────────────────────────────────────────────────────
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Register FCM token with Supabase once the user is signed in.
  // FcmService listens to auth state changes and handles this automatically.
  FcmService.init();

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