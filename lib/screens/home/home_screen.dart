import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/models/category.dart';
import 'package:tapsense/models/transaction.dart';
import 'package:tapsense/services/auth_service.dart';
import 'package:tapsense/services/bluetooth_service.dart';
import 'package:tapsense/services/transaction_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Transaction> _recent = [];
  double _todayTotal = 0;
  int _todayCount = 0;
  bool _loading = true;
  String _userName = '';
  String _currencyCode = 'SGD';

  @override
  void initState() {
    super.initState();
    walletBluetooth.events.listen((event) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Wallet: ${event.label}'),
        backgroundColor: kAccent,
        duration: const Duration(seconds: 2),
      ));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final user = Supabase.instance.client.auth.currentUser;
    final userId = user?.id ?? '';
    _userName = user?.userMetadata?['name'] ?? 'there';

    // Load currency from profile
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('currency')
          .eq('id', userId)
          .single();
      _currencyCode = profile['currency'] ?? 'SGD';
    } catch (_) {}

    final results = await Future.wait([
      TransactionService.fetchRecent(userId),
      TransactionService.todayTotal(userId),
    ]);

    final recent = results[0] as List<Transaction>;
    final total = results[1] as double;

    // Count today's transactions
    final today = DateTime.now();
    final todayCount = recent.where((tx) {
      final d = tx.createdAt.toLocal();
      return d.year == today.year &&
             d.month == today.month &&
             d.day == today.day;
    }).length;

    if (mounted) {
      setState(() {
        _recent     = recent;
        _todayTotal = total;
        _todayCount = todayCount;
        _loading    = false;
      });
    }
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
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hey, $_userName 👋',
            style: const TextStyle(
              color: kTextSecondary, fontSize: 13,
              fontWeight: FontWeight.w400)),
          const Text('TapSense',
            style: TextStyle(
              color: kTextPrimary, fontSize: 20,
              fontWeight: FontWeight.w800)),
        ]),
        titleSpacing: 20,
        toolbarHeight: 64,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: kTextSecondary),
            onPressed: () => context.push('/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: kTextSecondary),
            onPressed: () async {
              await AuthService.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: kAccent,
        backgroundColor: kSurface,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kAccent))
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                children: [

                  // ── Today's spend card ──────────────────────────
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
                        const Text('Spent today',
                          style: TextStyle(
                            color: kTextSecondary, fontSize: 13)),
                        const SizedBox(height: 8),
                        Text(
                          '${_symbol(_currencyCode)} ${_todayTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: kTextPrimary, fontSize: 36,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1),
                        ),
                        const SizedBox(height: 16),
                        Row(children: [
                          _StatPill(
                            label: '$_todayCount transaction${_todayCount == 1 ? '' : 's'} today',
                            icon: Icons.receipt_long,
                          ),
                        ]),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Wallet status ───────────────────────────────
                  _WalletCard(),

                  const SizedBox(height: 20),

                  // ── Action buttons ──────────────────────────────
                  Row(children: [
                    Expanded(child: _ActionBtn(
                      icon: Icons.qr_code_scanner,
                      label: 'Scan QR',
                      color: kAccent,
                      onTap: () => context.push('/scanner'),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _ActionBtn(
                      icon: Icons.add_circle_outline,
                      label: 'Manual',
                      color: kSuccess,
                      onTap: () => context.push('/confirm-log', extra: {
                        'triggerType': 'manual',
                        'merchantName': null,
                        'merchantUen': null,
                        'amount': null,
                        'rawQr': null,
                      }),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _ActionBtn(
                      icon: Icons.bar_chart_rounded,
                      label: 'Insights',
                      color: kInfo,
                      onTap: () => context.push('/insights'),
                    )),
                  ]),

                  const SizedBox(height: 20),

                  // ── Mock wallet events ──────────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('🧪 Mock Wallet Events',
                          style: TextStyle(
                            color: kTextSecondary, fontSize: 11,
                            fontWeight: FontWeight.w600)),
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
                          Expanded(child: OutlinedButton.icon(
                            onPressed: () => context.push('/confirm-log',
                              extra: {
                                'triggerType': 'button_press',
                                'merchantName': null,
                                'merchantUen': null,
                                'amount': null,
                                'rawQr': null,
                              }),
                            icon: const Icon(
                              Icons.radio_button_checked, size: 14),
                            label: const Text('Button',
                              style: TextStyle(fontSize: 12)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kInfo,
                              side: const BorderSide(color: kInfo),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            ),
                          )),
                        ]),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Recent transactions ─────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Recent',
                        style: TextStyle(
                          color: kTextPrimary, fontSize: 16,
                          fontWeight: FontWeight.w700)),
                      TextButton(
                        onPressed: () => context.push('/insights'),
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
                        color: kSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kBorder),
                      ),
                      child: const Column(children: [
                        Icon(Icons.receipt_long,
                          color: kTextMuted, size: 36),
                        SizedBox(height: 12),
                        Text('No transactions yet',
                          style: TextStyle(color: kTextSecondary)),
                        SizedBox(height: 4),
                        Text('Scan a QR or log manually',
                          style: TextStyle(
                            color: kTextMuted, fontSize: 12)),
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

// ── Wallet status card ────────────────────────────────────────────────────────
class _WalletCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final connected = walletBluetooth.isConnected;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: connected ? kSuccess.withOpacity(0.4) : kBorder),
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
              style: const TextStyle(
                color: kTextPrimary, fontWeight: FontWeight.w600,
                fontSize: 14)),
            Text(
              connected
                ? 'Listening for payment events'
                : 'Pair your TapSense wallet',
              style: const TextStyle(color: kTextSecondary, fontSize: 12)),
          ],
        )),
        if (!connected)
          ElevatedButton(
            onPressed: () => context.push('/pairing'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: kTextPrimary,
              padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
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

// ── Transaction tile ──────────────────────────────────────────────────────────
class _TxTile extends StatelessWidget {
  final Transaction tx;
  final String symbol;
  const _TxTile({required this.tx, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final cat = categoryById(tx.categoryId);
    final fmt = DateFormat('d MMM, h:mm a');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
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
            Text(
              tx.merchantName ?? cat.name,
              style: const TextStyle(
                color: kTextPrimary, fontWeight: FontWeight.w600,
                fontSize: 14),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            Text(fmt.format(tx.createdAt.toLocal()),
              style: const TextStyle(color: kTextMuted, fontSize: 11)),
          ],
        )),
        Text(
          '$symbol ${tx.amount.toStringAsFixed(2)}',
          style: const TextStyle(
            color: kTextPrimary, fontWeight: FontWeight.w700,
            fontSize: 15),
        ),
      ]),
    );
  }
}

// ── Stat pill ─────────────────────────────────────────────────────────────────
class _StatPill extends StatelessWidget {
  final String label;
  final IconData icon;
  const _StatPill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: kAccent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: kAccent, size: 12),
        const SizedBox(width: 4),
        Text(label,
          style: const TextStyle(color: kAccent, fontSize: 11)),
      ]),
    );
  }
}

// ── Action button ─────────────────────────────────────────────────────────────
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
              color: color, fontSize: 12,
              fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}