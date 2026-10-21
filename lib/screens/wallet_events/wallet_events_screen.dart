// lib/screens/wallet_events/wallet_events_screen.dart
//
// Shows BLE wallet events from the last 24 h, grouped by hour.
// Combined with an in-app notification bell – notifications come from
// Supabase table `wallet_notifications` (user_id, title, body, read,
// created_at).  The screen has two tabs: Events | Notifications.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/theme.dart';

// ─── simple data model ───────────────────────────────────────────────────────

class WalletEvent {
  final String deviceName;
  final String deviceId;
  final int rssi;
  final DateTime seenAt;

  const WalletEvent({
    required this.deviceName,
    required this.deviceId,
    required this.rssi,
    required this.seenAt,
  });
}

// ─── screen ──────────────────────────────────────────────────────────────────

class WalletEventsScreen extends StatefulWidget {
  const WalletEventsScreen({super.key});

  @override
  State<WalletEventsScreen> createState() => _WalletEventsScreenState();
}

class _WalletEventsScreenState extends State<WalletEventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _sb = Supabase.instance.client;

  // BLE events collected in last 24 h
  final List<WalletEvent> _events = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _scanning = false;

  // Notifications
  List<Map<String, dynamic>> _notifs = [];
  bool _loadingNotifs = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _startBle();
    _loadNotifs();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // ── BLE scan (continuous, 24 h window) ─────────────────────────────────────

  Future<void> _startBle() async {
    if (!await FlutterBluePlus.isAvailable) return;
    setState(() => _scanning = true);

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(hours: 24));
      final fresh = <WalletEvent>[];

      for (final r in results) {
        final name = r.device.platformName;
        fresh.add(WalletEvent(
          deviceName: name.isEmpty ? 'Unknown' : name,
          deviceId: r.device.remoteId.str,
          rssi: r.rssi,
          seenAt: now,
        ));
      }

      if (!mounted) return;
      setState(() {
        // merge: keep unique by id, drop older than 24 h
        final map = <String, WalletEvent>{
          for (final e in _events) e.deviceId: e,
          for (final e in fresh) e.deviceId: e,
        };
        _events
          ..clear()
          ..addAll(
              map.values.where((e) => e.seenAt.isAfter(cutoff)).toList()
                ..sort((a, b) => b.seenAt.compareTo(a.seenAt)));
      });
    });
  }

  Future<void> _rescan() async {
    await FlutterBluePlus.stopScan();
    setState(() => _scanning = true);
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    Future.delayed(const Duration(seconds: 15),
        () => mounted ? setState(() => _scanning = false) : null);
  }

  // ── Notifications ───────────────────────────────────────────────────────────

  Future<void> _loadNotifs() async {
    setState(() => _loadingNotifs = true);
    try {
      final uid = _sb.auth.currentUser?.id;
      final res = await _sb
          .from('wallet_notifications')
          .select()
          .eq('user_id', uid!)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _notifs = List<Map<String, dynamic>>.from(res as List);
          _loadingNotifs = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingNotifs = false);
    }
  }

  Future<void> _markRead(String id) async {
    await _sb
        .from('wallet_notifications')
        .update({'read': true}).eq('id', id);
    _loadNotifs();
  }

  Future<void> _markAllRead() async {
    final uid = _sb.auth.currentUser?.id;
    await _sb
        .from('wallet_notifications')
        .update({'read': true})
        .eq('user_id', uid!)
        .eq('read', false);
    _loadNotifs();
  }

  // ── build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? kBg : kBgLight;
    final surface = dark ? kSurface : kSurfaceLight;
    final border = dark ? kBorder : kBorderLight;
    final textP = dark ? kTextPrimary : kTextPrimaryLight;
    final textS = dark ? kTextSecondary : kTextSecondaryLight;
    final textM = dark ? kTextMuted : kTextMutedLight;
    final unread = _notifs.where((n) => n['read'] == false).length;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: BackButton(color: textP),
        title: Text('Wallet Activity',
            style: TextStyle(
                color: textP, fontSize: 20, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabs,
          labelColor: kAccent,
          unselectedLabelColor: textS,
          indicatorColor: kAccent,
          tabs: [
            const Tab(text: 'Events'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Notifications'),
                  if (unread > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: kAccent,
                          borderRadius: BorderRadius.circular(10)),
                      child: Text('$unread',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_tabs.index == 0)
            IconButton(
                icon: _scanning
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: kAccent))
                    : Icon(Icons.refresh, color: textS),
                onPressed: _scanning ? null : _rescan),
          if (_tabs.index == 1 && unread > 0)
            TextButton(
                onPressed: _markAllRead,
                child: Text('Mark all read',
                    style: TextStyle(color: kAccent, fontSize: 12))),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildEvents(bg, surface, border, textP, textS, textM),
          _buildNotifs(bg, surface, border, textP, textS, textM),
        ],
      ),
    );
  }

  Widget _buildEvents(Color bg, Color surface, Color border, Color textP,
      Color textS, Color textM) {
    if (_events.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_searching, color: textM, size: 52),
            const SizedBox(height: 14),
            Text('Scanning for TapSense devices…',
                style: TextStyle(color: textM, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _events.length,
      separatorBuilder: (_, __) => Divider(color: border, height: 1),
      itemBuilder: (ctx, i) {
        final e = _events[i];
        final rssiColor = e.rssi > -60
            ? kSuccess
            : e.rssi > -80
                ? kWarning
                : kError;

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: kAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.credit_card, color: kAccent, size: 22),
          ),
          title: Text(e.deviceName,
              style: TextStyle(
                  color: textP,
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          subtitle: Text(e.deviceId,
              style: TextStyle(color: textM, fontSize: 11)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.signal_wifi_4_bar, color: rssiColor, size: 14),
                  const SizedBox(width: 4),
                  Text('${e.rssi} dBm',
                      style: TextStyle(
                          color: rssiColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('HH:mm').format(e.seenAt),
                style: TextStyle(color: textM, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotifs(Color bg, Color surface, Color border, Color textP,
      Color textS, Color textM) {
    if (_loadingNotifs) {
      return Center(child: CircularProgressIndicator(color: kAccent));
    }
    if (_notifs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_outlined, color: textM, size: 52),
            const SizedBox(height: 14),
            Text('No notifications yet',
                style: TextStyle(color: textM, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _notifs.length,
      separatorBuilder: (_, __) => Divider(color: border, height: 1),
      itemBuilder: (ctx, i) {
        final n = _notifs[i];
        final read = n['read'] == true;
        DateTime? dt;
        try {
          dt = DateTime.parse(n['created_at'].toString()).toLocal();
        } catch (_) {}

        return Dismissible(
          key: ValueKey(n['id']),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: kError.withOpacity(0.15),
            child: const Icon(Icons.delete_outline, color: kError),
          ),
          onDismissed: (_) async {
            await _sb
                .from('wallet_notifications')
                .delete()
                .eq('id', n['id'].toString());
            _loadNotifs();
          },
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: read
                      ? border.withOpacity(0.5)
                      : kAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.notifications_outlined,
                  color: read ? textM : kAccent, size: 22),
            ),
            title: Text(n['title']?.toString() ?? '—',
                style: TextStyle(
                    color: textP,
                    fontWeight: read ? FontWeight.w400 : FontWeight.w700,
                    fontSize: 14)),
            subtitle: Text(n['body']?.toString() ?? '',
                style: TextStyle(color: textS, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!read)
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        const BoxDecoration(color: kAccent, shape: BoxShape.circle),
                  ),
                if (dt != null) ...[
                  const SizedBox(height: 4),
                  Text(DateFormat('dd MMM').format(dt),
                      style: TextStyle(color: textM, fontSize: 10)),
                ],
              ],
            ),
            onTap: read ? null : () => _markRead(n['id'].toString()),
          ),
        );
      },
    );
  }
}