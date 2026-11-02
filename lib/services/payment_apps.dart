// lib/services/payment_apps.dart
//
// "Pay with…" after a QR scan: open the user's bank / payment app so they can
// pay, the way Android asks which browser to use for a link.
//   - First time: a chooser lists the phone's apps (likely bank/pay apps first)
//     with "Just once" / "Always".
//   - "Always" is remembered; change or clear it in Settings → Payment app.
//
// Android only. iPhones don't let apps see which other apps are installed,
// so on iOS [supported] is false and nothing is shown.
//
// Android side: MainActivity.kt channel "tapsense/apps" + <queries> LAUNCHER
// entry in AndroidManifest.xml.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapsense/app/theme.dart';

import 'debug_log.dart';

class InstalledApp {
  InstalledApp({required this.package, required this.label, this.icon});
  final String package;
  final String label;
  final Uint8List? icon;
}

class PaymentAppChoice {
  PaymentAppChoice(this.package, this.label);
  final String package;
  final String label;
}

class PaymentApps {
  PaymentApps._();

  static const _channel = MethodChannel('tapsense/apps');
  static const _pkgKey = 'payment_app_package_v1';
  static const _labelKey = 'payment_app_label_v1';

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// The remembered app ("Always"), or null = ask every time.
  static final ValueNotifier<PaymentAppChoice?> saved =
      ValueNotifier<PaymentAppChoice?>(null);

  static List<InstalledApp>? _cache;

  /// Call once at startup (main.dart).
  static Future<void> load() async {
    if (!supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final pkg = prefs.getString(_pkgKey);
      final label = prefs.getString(_labelKey);
      saved.value = pkg == null ? null : PaymentAppChoice(pkg, label ?? pkg);
    } catch (e, st) {
      dlogError('PAYAPP', e, st);
    }
  }

  static Future<void> remember(PaymentAppChoice? choice) async {
    saved.value = choice;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (choice == null) {
        await prefs.remove(_pkgKey);
        await prefs.remove(_labelKey);
      } else {
        await prefs.setString(_pkgKey, choice.package);
        await prefs.setString(_labelKey, choice.label);
      }
    } catch (e, st) {
      dlogError('PAYAPP', e, st);
    }
  }

  /// Apps that can be opened, with likely bank / payment apps first.
  static Future<List<InstalledApp>> installedApps({bool refresh = false}) async {
    if (!supported) return [];
    if (_cache != null && !refresh) return _cache!;
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('listLaunchableApps');
      final apps = (raw ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((m) => InstalledApp(
                package: m['package'] as String,
                label: m['label'] as String? ?? m['package'] as String,
                icon: m['icon'] as Uint8List?,
              ))
          .toList();
      _cache = apps;
      dlog('PAYAPP', '${apps.length} apps found, '
          '${apps.where(looksLikePaymentApp).length} look like bank/pay apps');
      return apps;
    } catch (e, st) {
      dlogError('PAYAPP', e, st);
      return [];
    }
  }

  /// Rough guess used only to sort the list — the user can pick any app.
  static bool looksLikePaymentApp(InstalledApp a) {
    final s = '${a.package} ${a.label}'.toLowerCase();
    const hints = [
      'bank', 'pay', 'wallet', 'dbs', 'posb', 'ocbc', 'uob', 'citi', 'hsbc',
      'maybank', 'standardchartered', 'trust', 'gxs', 'revolut', 'youtrip',
      'wise', 'grab', 'shopee', 'lazada', 'dash', 'favepay', 'boost',
      'finance', 'money', 'cash',
    ];
    return hints.any(s.contains);
  }

  static Future<bool> launch(String package) async {
    if (!supported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('launchApp', {'package': package}) ?? false;
      dlog('PAYAPP', ok ? 'opened $package' : 'could not open $package');
      return ok;
    } catch (e, st) {
      dlogError('PAYAPP', e, st);
      return false;
    }
  }

  /// After a QR spend is logged: open the remembered app, or ask which one.
  static Future<void> offerAfterScan(BuildContext context) async {
    if (!supported) return;
    final remembered = saved.value;
    if (remembered != null) {
      if (await launch(remembered.package)) return;
      // Uninstalled since → forget it and ask again.
      await remember(null);
    }
    if (!context.mounted) return;
    final pick = await showPaymentAppPicker(context);
    if (pick == null) return;
    if (pick.always) {
      await remember(PaymentAppChoice(pick.app.package, pick.app.label));
    }
    await launch(pick.app.package);
  }
}

class PaymentAppPick {
  PaymentAppPick(this.app, this.always);
  final InstalledApp app;
  final bool always;
}

/// Bottom-sheet chooser like Android's "Open with": tap an app, then
/// "Just once" or "Always". With [settingsMode] there's a single "Use this
/// app" button (always remembered) instead.
Future<PaymentAppPick?> showPaymentAppPicker(BuildContext context,
    {bool settingsMode = false}) {
  return showModalBottomSheet<PaymentAppPick>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaymentAppSheet(settingsMode: settingsMode),
  );
}

class _PaymentAppSheet extends StatefulWidget {
  const _PaymentAppSheet({required this.settingsMode});
  final bool settingsMode;

  @override
  State<_PaymentAppSheet> createState() => _PaymentAppSheetState();
}

class _PaymentAppSheetState extends State<_PaymentAppSheet> {
  late final Future<List<InstalledApp>> _apps = PaymentApps.installedApps();
  InstalledApp? _selected;
  String _query = '';
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? kSurface : kSurfaceLight;
    final bg = dark ? kBg : kBgLight;
    final textP = dark ? kTextPrimary : kTextPrimaryLight;
    final textM = dark ? kTextMuted : kTextMutedLight;
    const accent = kAccent;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: textM.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(children: [
              Expanded(
                child: Text(
                    widget.settingsMode ? 'Choose your payment app' : 'Pay with…',
                    style: TextStyle(
                        color: textP, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              if (!widget.settingsMode)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Not now', style: TextStyle(color: textM)),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              style: TextStyle(color: textP),
              decoration: InputDecoration(
                hintText: 'Search apps',
                hintStyle: TextStyle(color: textM),
                prefixIcon: Icon(Icons.search, color: textM, size: 20),
                filled: true,
                fillColor: bg,
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<InstalledApp>>(
              future: _apps,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(
                      child: CircularProgressIndicator(color: accent));
                }
                final all = snap.data ?? [];
                if (all.isEmpty) {
                  return Center(
                    child: Text('Could not list apps on this phone.',
                        style: TextStyle(color: textM)),
                  );
                }
                final matches = all
                    .where((a) =>
                        _query.isEmpty ||
                        a.label.toLowerCase().contains(_query) ||
                        a.package.toLowerCase().contains(_query))
                    .toList();
                final suggested =
                    matches.where(PaymentApps.looksLikePaymentApp).toList();
                final others = matches
                    .where((a) => !PaymentApps.looksLikePaymentApp(a))
                    .toList();
                final showOthers = _showAll || _query.isNotEmpty || suggested.isEmpty;

                return ListView(
                  controller: scroll,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    if (suggested.isNotEmpty) _header('Bank & payment apps', textM),
                    ...suggested.map((a) => _tile(a, textP, accent)),
                    if (showOthers && others.isNotEmpty) _header('Other apps', textM),
                    if (showOthers) ...others.map((a) => _tile(a, textP, accent)),
                    if (!showOthers && others.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _showAll = true),
                        child: Text('Show all apps (${others.length} more)',
                            style: const TextStyle(color: accent)),
                      ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: widget.settingsMode
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _selected == null
                            ? null
                            : () => Navigator.pop(
                                context, PaymentAppPick(_selected!, true)),
                        style: _btnStyle(accent),
                        child: const Text('Use this app'),
                      ),
                    )
                  : Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _selected == null
                              ? null
                              : () => Navigator.pop(
                                  context, PaymentAppPick(_selected!, false)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accent,
                            side: const BorderSide(color: accent),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Just once'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _selected == null
                              ? null
                              : () => Navigator.pop(
                                  context, PaymentAppPick(_selected!, true)),
                          style: _btnStyle(accent),
                          child: const Text('Always'),
                        ),
                      ),
                    ]),
            ),
          ),
        ]),
      ),
    );
  }

  ButtonStyle _btnStyle(Color accent) => ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _header(String text, Color textM) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                color: textM,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      );

  Widget _tile(InstalledApp a, Color textP, Color accent) {
    final selected = _selected?.package == a.package;
    return ListTile(
      onTap: () => setState(() => _selected = a),
      selected: selected,
      selectedTileColor: accent.withOpacity(0.12),
      leading: a.icon == null
          ? const Icon(Icons.apps, size: 36)
          : Image.memory(a.icon!, width: 36, height: 36, gaplessPlayback: true),
      title: Text(a.label, style: TextStyle(color: textP, fontSize: 14)),
      trailing: selected ? Icon(Icons.check_circle, color: accent) : null,
    );
  }
}