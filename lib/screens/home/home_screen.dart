// lib/screens/home/home_screen.dart
//
// Changes vs previous version:
//   1. Action row: 4 buttons — Scan QR / Manual / Goals / Insights
//   2. Mock Wallet Events: "Button" → VoiceLogButton (mic + STT)
//   3. Budget warning pill: shows when any category is over cap this month
//   4. _TxTile: correct sign + red/green colour for debit/credit

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/models/category.dart';
import 'package:tapsense/models/transaction.dart';
import 'package:tapsense/services/bluetooth_service.dart';
import 'package:tapsense/services/transaction_service.dart';
import 'package:tapsense/services/budget_service.dart';
import 'package:tapsense/widgets/voice_log_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Transaction> _recent = [];
  double _todayTotal = 0;
  int    _todayCount = 0;
  bool   _loading    = true;
  String _userName   = '';
  String _currencyCode = 'SGD';

  // Budget warnings — full results for over-cap and near-cap categories this month
  List<BudgetCheckResult> _overBudgetResults  = [];
  List<BudgetCheckResult> _nearBudgetResults  = [];
  List<String> get _overBudgetCats => _overBudgetResults.map((r) => r.categoryId).toList();

  StreamSubscription<WalletEvent>? _walletSub;

  @override
  void initState() {
    super.initState();
    _walletSub = walletBluetooth.events.listen((event) {
      if (!mounted) return;
      // Card taps already show the "Device tapped by card activation" banner
      // (AppNotifications) — don't show a second message for them.
      if (event.type == WalletEventType.terminalTap) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Wallet: ${event.label}'),
        backgroundColor: kAccent,
        duration: const Duration(seconds: 2),
      ));
    });
  }

  @override
  void dispose() {
    _walletSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user   = Supabase.instance.client.auth.currentUser;
    final userId = user?.id ?? '';
    _userName    = user?.userMetadata?['name'] ?? 'there';

    // Name + currency come from Settings (profiles table).
    // Falls back to the sign-up name above if Settings has no name.
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('currency, name')
          .eq('id', userId)
          .single();
      _currencyCode = profile['currency'] ?? 'SGD';
      final profileName = (profile['name'] as String?)?.trim();
      if (profileName != null && profileName.isNotEmpty) {
        _userName = profileName;
      }
    } catch (_) {}

    final results = await Future.wait([
      TransactionService.fetchRecent(userId),
      TransactionService.todayTotal(userId),
    ]);

    final recent = results[0] as List<Transaction>;
    final total  = results[1] as double;

    final today      = DateTime.now();
    final todayCount = recent.where((tx) {
      final d = tx.createdAt.toLocal();
      return d.year  == today.year &&
             d.month == today.month &&
             d.day   == today.day   &&
             tx.amount < 0 &&
             tx.sharedWith != 'they_owe'; // exclude incoming
    }).length;

    // ── Budget check ──────────────────────────────────────────────────────
    final overBudgetResults = <BudgetCheckResult>[];
    final nearBudgetResults = <BudgetCheckResult>[];
    try {
      final spendMap = await TransactionService.monthTotalByCategory(userId);
      for (final entry in spendMap.entries) {
        final result = await BudgetService.checkCategory(
          userId:     userId,
          categoryId: entry.key,
        );
        if (result == null) continue;
        if (result.overBudget) {
          overBudgetResults.add(result);
        } else if (result.nearBudget) {
          nearBudgetResults.add(result);
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _recent             = recent;
        _todayTotal         = total;
        _todayCount         = todayCount;
        _overBudgetResults  = overBudgetResults;
        _nearBudgetResults  = nearBudgetResults;
        _loading            = false;
      });
    }
  }

  void _showOverBudgetSheet(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? kSurface : kSurfaceLight;
    final border  = dark ? kBorder  : kBorderLight;
    final textP   = dark ? kTextPrimary   : kTextPrimaryLight;
    final textS   = dark ? kTextSecondary : kTextSecondaryLight;
    final textM   = dark ? kTextMuted     : kTextMutedLight;
    final fmt     = NumberFormat.currency(symbol: 'S\$', decimalDigits: 2);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: kError.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.warning_amber_rounded,
                    color: kError, size: 18),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Over Budget',
                    style: TextStyle(
                        color: textP, fontSize: 17,
                        fontWeight: FontWeight.w700)),
                Text('${_overBudgetResults.length} ${_overBudgetResults.length == 1 ? 'category' : 'categories'} exceeded this month',
                    style: TextStyle(color: textM, fontSize: 12)),
              ]),
            ]),
            const SizedBox(height: 16),
            ..._overBudgetResults.map((r) {
              final catLabel = BudgetService.catLabel(r.categoryId);
              final pct = (r.fraction * 100).round();
              final overage = r.spent - r.cap;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kError.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kError.withOpacity(0.25)),
                ),
                child: Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(catLabel,
                          style: TextStyle(
                              color: textP, fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('${fmt.format(r.spent)} spent · cap ${fmt.format(r.cap)}',
                          style: TextStyle(color: textS, fontSize: 12)),
                    ],
                  )),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('$pct%',
                        style: const TextStyle(
                            color: kError, fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    Text('+${fmt.format(overage)} over',
                        style: TextStyle(color: textM, fontSize: 11)),
                  ]),
                ]),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/goals');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: kAccent,
                  side: const BorderSide(color: kAccent),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('View Goals'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNearBudgetSheet(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? kSurface : kSurfaceLight;
    final border  = dark ? kBorder  : kBorderLight;
    final textP   = dark ? kTextPrimary   : kTextPrimaryLight;
    final textS   = dark ? kTextSecondary : kTextSecondaryLight;
    final textM   = dark ? kTextMuted     : kTextMutedLight;
    final fmt     = NumberFormat.currency(symbol: 'S\$', decimalDigits: 2);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: kWarning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.info_outline,
                    color: kWarning, size: 18),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Approaching Limit',
                    style: TextStyle(
                        color: textP, fontSize: 17,
                        fontWeight: FontWeight.w700)),
                Text('${_nearBudgetResults.length} ${_nearBudgetResults.length == 1 ? 'category' : 'categories'} above 80%',
                    style: TextStyle(color: textM, fontSize: 12)),
              ]),
            ]),
            const SizedBox(height: 16),
            ..._nearBudgetResults.map((r) {
              final catLabel = BudgetService.catLabel(r.categoryId);
              final pct      = (r.fraction * 100).round();
              final remaining = r.cap - r.spent;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kWarning.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kWarning.withOpacity(0.25)),
                ),
                child: Row(children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(catLabel,
                          style: TextStyle(
                              color: textP, fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('${fmt.format(r.spent)} spent · cap ${fmt.format(r.cap)}',
                          style: TextStyle(color: textS, fontSize: 12)),
                    ],
                  )),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('$pct%',
                        style: const TextStyle(
                            color: kWarning, fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    Text('${fmt.format(remaining)} left',
                        style: TextStyle(color: textM, fontSize: 11)),
                  ]),
                ]),
              );
            }),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/goals');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: kAccent,
                  side: const BorderSide(color: kAccent),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('View Goals'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _symbol(String code) {
    const map = {
      'SGD': 'S\$', 'USD': '\$',  'EUR': '€',  'GBP': '£',
      'INR': '₹',   'MYR': 'RM',  'IDR': 'Rp', 'THB': '฿',
      'PHP': '₱',   'AUD': 'A\$', 'JPY': '¥',  'CNY': '¥',
      'HKD': 'HK\$',
    };
    return map[code] ?? code;
  }

  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final bg      = dark ? kBg      : kBgLight;
    final surface = dark ? kSurface : kSurfaceLight;
    final border  = dark ? kBorder  : kBorderLight;
    final textP   = dark ? kTextPrimary    : kTextPrimaryLight;
    final textS   = dark ? kTextSecondary  : kTextSecondaryLight;
    final textM   = dark ? kTextMuted      : kTextMutedLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        toolbarHeight: 72,
        titleSpacing: 20,
        title: Row(children: [
          // App icon (same image as the launcher icon)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/images/app_icon.png', // ← change to your icon's file name
              width: 40, height: 40,
              fit: BoxFit.cover,
              // If the image is missing, show a plain icon instead of an error
              errorBuilder: (_, __, ___) => Container(
                width: 40, height: 40,
                color: kAccent,
                child: const Icon(Icons.wallet, color: Colors.white, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TapSense',
              style: TextStyle(
                color: textP, fontSize: 22,
                fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            Text('Hey, $_userName',
              style: TextStyle(
                color: textS, fontSize: 12, fontWeight: FontWeight.w400)),
          ]),
        ]),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_outlined, color: textS),
            onPressed: () => context.push('/wallet-events'),
          ),
          IconButton(
            icon: Icon(Icons.settings_outlined, color: textS),
            // Reload when coming back so a new name/currency shows right away
            onPressed: () async {
              await context.push('/settings');
              if (mounted) _load();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: kAccent,
        backgroundColor: surface,
        onRefresh: _load,
        child: _loading
            ? Center(child: CircularProgressIndicator(color: kAccent))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                children: [

                  // ── Today's spend card ──────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          kAccent.withOpacity(0.25),
                          kAccent.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kAccent.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Spent today',
                          style: TextStyle(color: textS, fontSize: 13)),
                        const SizedBox(height: 8),
                        Text(
                          '${_symbol(_currencyCode)} ${_todayTotal.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: textP, fontSize: 36,
                            fontWeight: FontWeight.w800, letterSpacing: -1),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _StatPill(
                              label: '$_todayCount transaction${_todayCount == 1 ? '' : 's'} today',
                              icon: Icons.receipt_long,
                              color: kAccent,
                            ),
                            // ── Over-budget warning pill ──────────────────
                            if (_overBudgetCats.isNotEmpty)
                              _StatPill(
                                label: '⚠ ${_overBudgetCats.length} ${_overBudgetCats.length == 1 ? 'category' : 'categories'} over budget',
                                icon: Icons.warning_amber_rounded,
                                color: kError,
                                onTap: () => _showOverBudgetSheet(context),
                              ),
                            // ── Near-budget amber pill ────────────────────
                            if (_nearBudgetResults.isNotEmpty)
                              _StatPill(
                                label: '${_nearBudgetResults.length} ${_nearBudgetResults.length == 1 ? 'category' : 'categories'} near limit',
                                icon: Icons.info_outline,
                                color: kWarning,
                                onTap: () => _showNearBudgetSheet(context),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  _WalletCard(),
                  const SizedBox(height: 20),

                  // ── Action buttons (4) ──────────────────────────────────
                  Row(children: [
                    Expanded(child: _ActionBtn(
                      icon: Icons.qr_code_scanner,
                      label: 'Scan QR',
                      color: kAccent,
                      onTap: () => context.push('/scanner'),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionBtn(
                      icon: Icons.add_circle_outline,
                      label: 'Manual',
                      color: kTextMuted,
                      onTap: () => context.push('/confirm-log', extra: {
                        'triggerType': 'manual',
                        'merchantName': null,
                        'merchantUen': null,
                        'amount': null,
                        'rawQr': null,
                      }),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionBtn(
                      icon: Icons.flag_outlined,
                      label: 'Goals',
                      color: kWarning,
                      onTap: () => context.push('/goals'),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionBtn(
                      icon: Icons.bar_chart_rounded,
                      label: 'Insights',
                      color: kInfo,
                      onTap: () => context.push('/insights'),
                    )),
                  ]),

                  const SizedBox(height: 20),

                  // ── Quick actions ───────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Quick Actions',
                              style: TextStyle(
                                color: textM, fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5)),
                            GestureDetector(
                              onTap: () => context.push('/wallet-events'),
                              child: Text('Wallet events',
                                style: TextStyle(
                                  color: kAccent, fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: OutlinedButton.icon(
                            onPressed: () => context.push('/confirm-log',
                              extra: {
                                'triggerType': 'card_removed',
                                'merchantName': null,
                                'merchantUen': null,
                                'amount': null,
                                'rawQr': null,
                              }),
                            icon: const Icon(Icons.credit_card, size: 14),
                            label: const Text('Card Out',
                              style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kWarning,
                              side: const BorderSide(color: kWarning),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            ),
                          )),
                          const SizedBox(width: 8),
                          const VoiceLogButton(),
                        ]),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Recent transactions ─────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Recent',
                        style: TextStyle(
                          color: textP, fontSize: 16,
                          fontWeight: FontWeight.w700)),
                      TextButton(
                        onPressed: () => context.push('/transactions'),
                        child: const Text('See all',
                          style: TextStyle(color: kAccent, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_recent.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: Column(children: [
                        Icon(Icons.receipt_long, color: textM, size: 36),
                        const SizedBox(height: 12),
                        Text('No transactions yet',
                          style: TextStyle(color: textS)),
                        const SizedBox(height: 4),
                        Text('Scan a QR or log manually',
                          style: TextStyle(color: textM, fontSize: 12)),
                      ]),
                    )
                  else
                    ...(_recent.take(10).map((tx) =>
                        _TxTile(tx: tx, symbol: _symbol(_currencyCode)))),
                ],
              ),
      ),
    );
  }
}

// ── Wallet status card ─────────────────────────────────────────────────────────

class _WalletCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? kSurface : kSurfaceLight;
    final border  = dark ? kBorder  : kBorderLight;
    final textP   = dark ? kTextPrimary   : kTextPrimaryLight;
    final textS   = dark ? kTextSecondary : kTextSecondaryLight;

    final connected = walletBluetooth.isConnected;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: connected ? kSuccess.withOpacity(0.4) : border),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: (connected ? kSuccess : kAccent).withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
            color: connected ? kSuccess : kAccent,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(connected ? 'Wallet Connected' : 'No Wallet Paired',
              style: TextStyle(
                color: textP, fontWeight: FontWeight.w600, fontSize: 14)),
            Text(
              connected
                ? 'Listening for payment events'
                : 'Pair your TapSense wallet',
              style: TextStyle(color: textS, fontSize: 12)),
          ],
        )),
        if (!connected)
          ElevatedButton(
            onPressed: () => context.push('/pairing'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Pair', style: TextStyle(fontSize: 13)),
          ),
        if (connected)
          IconButton(
            icon: const Icon(Icons.vibration, color: kSuccess),
            onPressed: walletBluetooth.testBuzz,
          ),
      ]),
    );
  }
}

// ── Transaction tile ───────────────────────────────────────────────────────────

class _TxTile extends StatelessWidget {
  final Transaction tx;
  final String symbol;
  const _TxTile({required this.tx, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? kSurface : kSurfaceLight;
    final border  = dark ? kBorder  : kBorderLight;
    final textP   = dark ? kTextPrimary : kTextPrimaryLight;
    final textM   = dark ? kTextMuted   : kTextMutedLight;

    final cat = kCategories.firstWhere(
      (c) => c.id == tx.categoryId,
      orElse: () => kCategories.firstWhere((c) => c.id == 'other'),
    );

    // "They owe" = money coming back → show positive/green regardless of stored sign
    final theyOwe      = tx.sharedWith == 'they_owe';
    final displayAmt   = theyOwe ? tx.amount.abs() : tx.amount;
    final isPositive   = displayAmt >= 0;
    final amtColor     = isPositive
        ? (dark ? kSuccess : kSuccessLight)
        : (dark ? kError   : kErrorLight);
    final amtLabel     = isPositive
        ? '+$symbol ${displayAmt.toStringAsFixed(2)}'
        : '-$symbol ${displayAmt.abs().toStringAsFixed(2)}';

    final label = (tx.merchantName?.isNotEmpty == true)
        ? tx.merchantName!
        : cat.name;

    final fmt = DateFormat('d MMM, h:mm a');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: cat.color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(cat.icon, color: cat.color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                  color: textP, fontWeight: FontWeight.w600,
                  fontSize: 14),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(fmt.format(tx.createdAt.toLocal()),
                style: TextStyle(color: textM, fontSize: 11)),
          ],
        )),
        Text(amtLabel,
            style: TextStyle(
                color: amtColor, fontWeight: FontWeight.w700,
                fontSize: 15)),
      ]),
    );
  }
}

// ── Stat pill ──────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _StatPill({
    required this.label,
    required this.icon,
    this.color = kAccent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ]),
      ),
    );
  }
}

// ── Action button ──────────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon, required this.label,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 5),
          Text(label,
            style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}