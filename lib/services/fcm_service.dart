// lib/services/fcm_service.dart
//
// Handles FCM token registration and foreground notification display.
//
// Flow:
//   1. On app start, FcmService.init() is called from main.dart.
//   2. It listens to Supabase auth state — when a user signs in, it requests
//      notification permission and saves the FCM token to the `profiles` table.
//   3. Token refreshes are also saved automatically.
//   4. Foreground messages show a banner via onMessage stream.
//
// Supabase table requirement:
//   ALTER TABLE profiles
//     ADD COLUMN IF NOT EXISTS fcm_token text;
//
// (Run this once in the Supabase SQL editor.)

//
// iOS note: push needs an APNs token, which a FREE Apple ID build never gets.
// _saveToken() checks for it first and skips push quietly instead of failing.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/services/debug_log.dart';
import 'package:tapsense/services/platform_caps.dart';

class FcmService {
  FcmService._();

  static final _fcm = FirebaseMessaging.instance;
  static final _sb  = Supabase.instance.client;

  // Call once from main() after Firebase.initializeApp()
  static void init() {
    // Save token whenever auth state changes (sign-in / token refresh)
    _sb.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (user != null) {
        _saveToken(user.id);
      }
    });

    // Token may rotate — keep it fresh in Supabase
    _fcm.onTokenRefresh.listen((token) {
      final uid = _sb.auth.currentUser?.id;
      if (uid != null) _upsertToken(uid, token);
    });

    // Show banner for foreground messages
    FirebaseMessaging.onMessage.listen(_handleForeground);
  }

  // ── Token management ────────────────────────────────────────────────────────

  // Supabase fires several auth events at startup (initial session, signed in,
  // token refreshed) — remember what we saved so it only happens once.
  static String? _savedKey;
  static bool _saving = false;

  static Future<void> _saveToken(String userId) async {
    if (_saving || _savedKey?.startsWith('$userId:') == true) return;
    _saving = true;
    try {
      // Request permission (Android 13+ / iOS)
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      dlog('PUSH', 'permission: ${settings.authorizationStatus.name}');
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // iOS: getToken() fails without an APNs token (free Apple ID / simulator).
      if (PlatformCaps.isIOS && !await _hasApnsToken()) {
        dlog('PUSH',
            'No APNs token (free Apple ID or simulator) — push disabled on this build');
        return;
      }

      final token = await _fcm.getToken();
      if (token == null) return;

      await _upsertToken(userId, token);
      _savedKey = '$userId:$token';
      dlog('PUSH', 'FCM token saved');
    } catch (e, st) {
      // Non-fatal — app works without push
      dlogError('PUSH', e, st);
    } finally {
      _saving = false;
    }
  }

  /// The APNs token can arrive a moment after launch on real iPhones,
  /// so check twice before giving up.
  static Future<bool> _hasApnsToken() async {
    var apns = await _fcm.getAPNSToken();
    if (apns == null) {
      await Future<void>.delayed(const Duration(seconds: 3));
      apns = await _fcm.getAPNSToken();
    }
    return apns != null;
  }

  static Future<void> _upsertToken(String userId, String token) async {
    try {
      // profiles PK is 'id' (= auth user id), not 'user_id'
      await _sb.from('profiles').upsert(
        {'id': userId, 'fcm_token': token},
        onConflict: 'id',
      );
    } catch (e) {
      // Log for debugging — check Supabase SQL: SELECT id, fcm_token FROM profiles
      dlog('PUSH', 'token upsert failed: $e');
    }
  }

  // ── Foreground message handler ──────────────────────────────────────────────

  static void _handleForeground(RemoteMessage message) {
    final title = message.notification?.title ?? '';
    final body  = message.notification?.body  ?? '';
    if (title.isEmpty && body.isEmpty) return;

    // Find the current overlay context via the navigator key
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    _showOverlayBanner(context, title: title, body: body);
  }

  /// Show the in-app banner from anywhere (used by AppNotifications).
  static void showBanner(String title, {String body = ''}) {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    _showOverlayBanner(context, title: title, body: body);
  }

  static void _showOverlayBanner(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FcmBanner(
        title:     title,
        body:      body,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 5), () {
      if (entry.mounted) entry.remove();
    });
  }

  // navigatorKey must be passed to GoRouter's navigatorKey so FcmService
  // can find the overlay context for foreground banners.
  // In router.dart: GoRouter(navigatorKey: FcmService.navigatorKey, ...)
  static final navigatorKey = GlobalKey<NavigatorState>();
  static GlobalKey<NavigatorState> get _navigatorKey => navigatorKey;
}

// ── Foreground notification banner ────────────────────────────────────────────

class _FcmBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onDismiss;

  const _FcmBanner({
    required this.title,
    required this.body,
    required this.onDismiss,
  });

  @override
  State<_FcmBanner> createState() => _FcmBannerState();
}

class _FcmBannerState extends State<_FcmBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Positioned(
      top: top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.notifications_outlined,
                    color: kAccent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.title.isNotEmpty)
                      Text(widget.title,
                          style: const TextStyle(
                              color: kTextPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    if (widget.body.isNotEmpty)
                      Text(widget.body,
                          style: const TextStyle(
                              color: kTextSecondary, fontSize: 12)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: widget.onDismiss,
                child: const Icon(Icons.close,
                    color: kTextMuted, size: 16),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}