// lib/screens/wallet_events/wallet_events_screen.dart
//
// Wallet Activity — two tabs:
//   Events        → what the TapSense wallet did in the last 24 h (card taps,
//                   card removed, button presses, buzzes sent). Comes from
//                   Supabase `wallet_events`, written by WalletActivity.
//   Notifications → Supabase `wallet_notifications`, written by AppNotifications.
//
// Debug menu (debug runs / DEBUG_MENU=true): simulate wallet events and buzzes
// so this screen can be tested without the firmware.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/config/env.dart';
import 'package:tapsense/services/app_notifications.dart';
import 'package:tapsense/services/bluetooth_service.dart';
import 'package:tapsense/services/wallet_activity.dart';

class WalletEventsScreen extends StatefulWidget {
  const WalletEventsScreen({super.key});

  @override
  State<WalletEventsScreen> createState() => _WalletEventsScreenState();
}

class _WalletEventsScreenState extends State<WalletEventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _sb = Supabase.instance.client;

  // Wallet activity (last 24 h)
  List<ActivityItem> _events = [];
  bool _loadingEvents = true;

  // Notifications
  List<Map<String, dynamic>> _notifs = [];
  bool _loadingNotifs = true;

  bool get _showDebug => !kReleaseMode || Env.debugMenu;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {}); // refresh app-bar actions per tab
      });
    WalletActivity.instance.changes.addListener(_loadEvents);
    AppNotifications.changes.addListener(_loadNotifs);
    _loadEvents();
    _loadNotifs();
  }

  @override
  void dispose() {
    WalletActivity.instance.changes.removeListener(_loadEvents);
    AppNotifications.changes.removeListener(_loadNotifs);
    _tabs.dispose();
    super.dispose();
  }

  // ── Events ──────────────────────────────────────────────────────────────────

  Future<void> _loadEvents() async {
    try {
      final items = await WalletActivity.instance.load(hours: 24);
      if (mounted) {
        setState(() {
          _events = items;
          _loadingEvents = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingEvents = false);
    }
  }

  // ── Notifications ───────────────────────────────────────────────────────────

  Future<void> _loadNotifs() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _loadingNotifs = false);
        return;
      }
      final res = await _sb
          .from('wallet_notifications')
          .select()
          .eq('user_id', uid)
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
    if (uid == null) return;
    await _sb
        .from('wallet_notifications')
        .update({'read': true})
        .eq('user_id', uid)
        .eq('read', false);
    _loadNotifs();
  }

  // ── Debug simulation ────────────────────────────────────────────────────────

  void _simulate(String action) {
    switch (action) {
      case 'tap':
        walletBluetooth.debugSimulateEvent(0x02);
      case 'removed':
        walletBluetooth.debugSimulateEvent(0x01);
      case 'button':
        walletBluetooth.debugSimulateEvent(0x03);
      case 'buzz1':
        walletBluetooth.debugSimulateBuzz(WalletBluetooth.kBuzzNormal);
      case 'buzz3':
        walletBluetooth.debugSimulateBuzz(WalletBluetooth.kBuzzOverLimit);
    }
  }

  // ── build ───────────────────────────────────────────────────────────────────

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
                icon: Icon(Icons.refresh, color: textS),
                onPressed: _loadEvents),
          if (_tabs.index == 0 && _showDebug)
            PopupMenuButton<String>(
              tooltip: 'Simulate (testing)',
              icon: Icon(Icons.science_outlined, color: textS),
              color: surface,
              onSelected: _simulate,
              itemBuilder: (_) => [
                _menuItem('tap', 'Simulate card tap', textP),
                _menuItem('removed', 'Simulate card removed', textP),
                _menuItem('button', 'Simulate button press', textP),
                _menuItem('buzz1', 'Simulate buzz (normal)', textP),
                _menuItem('buzz3', 'Simulate buzz (over limit)', textP),
              ],
            ),
          if (_tabs.index == 1 && unread > 0)
            TextButton(
                onPressed: _markAllRead,
                child: const Text('Mark all read',
                    style: TextStyle(color: kAccent, fontSize: 12))),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildEvents(border, textP, textS, textM),
          _buildNotifs(border, textP, textS, textM),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, String label, Color textP) =>
      PopupMenuItem(
        value: value,
        child: Text(label, style: TextStyle(color: textP, fontSize: 14)),
      );

  // ── Events tab ──────────────────────────────────────────────────────────────

  ({IconData icon, Color color}) _styleFor(String type) => switch (type) {
        'terminalTap' => (icon: Icons.contactless_outlined, color: kAccent),
        'cardRemoved' => (icon: Icons.credit_card_off_outlined, color: kWarning),
        'buttonPressed' ||
        'buttonReleased' =>
          (icon: Icons.touch_app_outlined, color: kInfo),
        'buzz' => (icon: Icons.vibration, color: kOrange),
        _ => (icon: Icons.help_outline, color: kTextMuted),
      };

  Widget _buildEvents(Color border, Color textP, Color textS, Color textM) {
    if (_loadingEvents) {
      return const Center(child: CircularProgressIndicator(color: kAccent));
    }

    final connected = walletBluetooth.isConnected;

    if (_events.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadEvents,
        child: ListView(
          children: [
            const SizedBox(height: 140),
            Icon(connected ? Icons.contactless_outlined : Icons.bluetooth_disabled,
                color: textM, size: 52),
            const SizedBox(height: 14),
            Text('No wallet activity in the last 24 hours',
                textAlign: TextAlign.center,
                style: TextStyle(color: textM, fontSize: 14)),
            const SizedBox(height: 6),
            Text(
                connected
                    ? 'Tap a card on your wallet to see it here.'
                    : 'Wallet not connected — pair it from Home.',
                textAlign: TextAlign.center,
                style: TextStyle(color: textM, fontSize: 12)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEvents,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _events.length,
        separatorBuilder: (_, __) => Divider(color: border, height: 1),
        itemBuilder: (ctx, i) {
          final e = _events[i];
          final style = _styleFor(e.type);
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: style.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(style.icon, color: style.color, size: 22),
            ),
            title: Text(e.label,
                style: TextStyle(
                    color: textP, fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(DateFormat('d MMM').format(e.at),
                style: TextStyle(color: textM, fontSize: 11)),
            trailing: Text(DateFormat('HH:mm').format(e.at),
                style: TextStyle(color: textS, fontSize: 12)),
          );
        },
      ),
    );
  }

  // ── Notifications tab ───────────────────────────────────────────────────────

  Widget _buildNotifs(Color border, Color textP, Color textS, Color textM) {
    if (_loadingNotifs) {
      return const Center(child: CircularProgressIndicator(color: kAccent));
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

    return RefreshIndicator(
      onRefresh: _loadNotifs,
      child: ListView.separated(
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
                      decoration: const BoxDecoration(
                          color: kAccent, shape: BoxShape.circle),
                    ),
                  if (dt != null) ...[
                    const SizedBox(height: 4),
                    Text(DateFormat('dd MMM, HH:mm').format(dt),
                        style: TextStyle(color: textM, fontSize: 10)),
                  ],
                ],
              ),
              onTap: read ? null : () => _markRead(n['id'].toString()),
            ),
          );
        },
      ),
    );
  }
}