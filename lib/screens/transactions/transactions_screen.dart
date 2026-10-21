// lib/screens/transactions/transactions_screen.dart
//
// Features:
//   • Running balance + total spent in header
//   • Multi-select filters: date range, payment mode, shared/owed, category
//   • Owed summary banner (you owe / they owe / net)
//   • You-owe / They-owe toggle on each card (persisted to Supabase)
//   • "They owe" flips amount display to positive green + "to collect" label
//   • Swipe-to-delete with confirmation
//   • Payment modes match confirm_log_screen: manual/sgqr/nfc/card/cash/other
//   • + FAB navigates to ConfirmLogScreen

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/models/category.dart';
import 'package:tapsense/screens/confirm_log/confirm_log_screen.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});
  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _txns = [];
  bool _loading = true;

  // You-owe tracking: txn id → 'you_owe' | 'they_owe' | null
  final Map<String, String?> _sharedWith = {};
  final Set<String> _saving = {};

  // ── Multi-select filters ─────────────────────────────────────────────────────
  final Set<String> _filterCategories = {};   // empty = all
  final Set<String> _filterDateRanges = {};   // 'today' | 'week' | 'month'
  final Set<String> _filterModes      = {};   // 'manual'|'sgqr'|'nfc'|'card'|'cash'|'other'
  final Set<String> _filterShared     = {};   // 'you_owe' | 'they_owe' | 'none'

  static const _allModes = ['manual', 'sgqr', 'nfc', 'card', 'cash', 'other'];
  static const _modeIcons = <String, IconData>{
    'manual': Icons.edit_outlined,
    'sgqr':   Icons.qr_code,
    'nfc':    Icons.contactless_outlined,
    'card':   Icons.credit_card,
    'cash':   Icons.payments_outlined,
    'other':  Icons.more_horiz,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _sb.auth.currentUser?.id;
      final res = await _sb
          .from('transactions')
          .select()
          .eq('user_id', uid!)
          .order('created_at', ascending: false);

      final txns = List<Map<String, dynamic>>.from(res as List);
      final Map<String, String?> sw = {};
      for (final t in txns) {
        final id = t['id']?.toString();
        if (id != null) sw[id] = t['shared_with'] as String?;
      }
      setState(() {
        _txns = txns;
        _sharedWith
          ..clear()
          ..addAll(sw);
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _delete(String id) async {
    await _sb.from('transactions').delete().eq('id', id);
    setState(() {
      _txns.removeWhere((t) => t['id'].toString() == id);
      _sharedWith.remove(id);
    });
  }

  Future<void> _setSharedWith(String id, String? value) async {
    setState(() { _sharedWith[id] = value; _saving.add(id); });
    try {
      await _sb.from('transactions').update({'shared_with': value}).eq('id', id);
    } catch (_) {
      setState(() => _sharedWith[id] = null);
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  // ── Filtered list ────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    final now = DateTime.now();
    return _txns.where((t) {
      // Category (multi-select)
      if (_filterCategories.isNotEmpty) {
        final catId = (t['category_id'] as String?) ?? 'other';
        if (!_filterCategories.contains(catId)) return false;
      }

      // Date range (multi-select — any match passes)
      if (_filterDateRanges.isNotEmpty) {
        DateTime? dt;
        try { dt = DateTime.parse(t['created_at'].toString()).toLocal(); } catch (_) {}
        if (dt == null) return false;
        bool dateOk = false;
        for (final r in _filterDateRanges) {
          final cutoff = switch (r) {
            'today' => DateTime(now.year, now.month, now.day),
            'week'  => now.subtract(const Duration(days: 7)),
            'month' => DateTime(now.year, now.month, 1),
            _       => DateTime(2000),
          };
          if (!dt.isBefore(cutoff)) { dateOk = true; break; }
        }
        if (!dateOk) return false;
      }

      // Payment mode (multi-select)
      if (_filterModes.isNotEmpty) {
        final mode = ((t['payment_mode'] as String?) ?? '').toLowerCase();
        if (!_filterModes.contains(mode)) return false;
      }

      // Shared/owed (multi-select)
      if (_filterShared.isNotEmpty) {
        final id  = t['id']?.toString() ?? '';
        final sw  = _sharedWith[id] ?? (t['shared_with'] as String?);
        bool ok = false;
        if (_filterShared.contains('you_owe')  && sw == 'you_owe')  ok = true;
        if (_filterShared.contains('they_owe') && sw == 'they_owe') ok = true;
        if (_filterShared.contains('none')     && sw == null)       ok = true;
        if (!ok) return false;
      }

      return true;
    }).toList();
  }

  bool get _hasActiveFilter =>
      _filterCategories.isNotEmpty || _filterDateRanges.isNotEmpty ||
      _filterModes.isNotEmpty      || _filterShared.isNotEmpty;

  void _clearFilters() => setState(() {
    _filterCategories.clear(); _filterDateRanges.clear();
    _filterModes.clear();      _filterShared.clear();
  });

  // ── Owed totals ──────────────────────────────────────────────────────────────
  double _oweTotal(String key) => _filtered.fold(0.0, (s, t) {
    final id = t['id']?.toString() ?? '';
    final sw = _sharedWith[id] ?? (t['shared_with'] as String?);
    if (sw != key) return s;
    return s + ((t['amount'] as num?)?.toDouble().abs() ?? 0);
  });

  bool get _hasOwed => _txns.any((t) {
    final id = t['id']?.toString() ?? '';
    final sw = _sharedWith[id] ?? (t['shared_with'] as String?);
    return sw == 'you_owe' || sw == 'they_owe';
  });

  double get _totalSpent => _filtered.fold(0.0, (s, t) {
    final v = (t['amount'] as num?)?.toDouble() ?? 0;
    return v < 0 ? s + v.abs() : s;
  });

  double get _balance =>
      _filtered.fold(0.0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0));

  // ── Filter sheet helper ──────────────────────────────────────────────────────
  void _showMultiSheet<T>(
    BuildContext ctx,
    bool dark, Color surface, Color border, Color textP, Color textM,
    String title,
    List<T> options,
    String Function(T) label,
    Set<String> activeSet,
    String Function(T) key,
    {Widget Function(T)? leading}
  ) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx2, setS) => Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: border, borderRadius: BorderRadius.circular(2)),
              )),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Text(title, style: TextStyle(
                    color: textP, fontSize: 16, fontWeight: FontWeight.w700))),
                if (activeSet.isNotEmpty)
                  TextButton(
                    onPressed: () { setState(() => activeSet.clear()); Navigator.pop(ctx2); },
                    child: const Text('Clear', style: TextStyle(color: kAccent, fontSize: 12)),
                  ),
              ]),
              const SizedBox(height: 8),
              Text('Tap to select multiple',
                  style: TextStyle(color: textM, fontSize: 11)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: options.map((opt) {
                  final k = key(opt);
                  final active = activeSet.contains(k);
                  return GestureDetector(
                    onTap: () {
                      setS(() {
                        setState(() {
                          if (active) activeSet.remove(k);
                          else        activeSet.add(k);
                        });
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? kAccent.withOpacity(0.15) : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: active ? kAccent : border,
                            width: active ? 1.5 : 1),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (leading != null) ...[leading(opt), const SizedBox(width: 5)],
                        if (active) ...[
                          Icon(Icons.check, color: kAccent, size: 12),
                          const SizedBox(width: 4),
                        ],
                        Text(label(opt),
                            style: TextStyle(
                                color: active ? kAccent : textM,
                                fontSize: 12,
                                fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
                      ]),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final bg      = dark ? kBg      : kBgLight;
    final surface = dark ? kSurface : kSurfaceLight;
    final border  = dark ? kBorder  : kBorderLight;
    final textP   = dark ? kTextPrimary   : kTextPrimaryLight;
    final textS   = dark ? kTextSecondary : kTextSecondaryLight;
    final textM   = dark ? kTextMuted     : kTextMutedLight;

    final rows    = _filtered;
    final fmt     = NumberFormat.currency(symbol: 'S\$', decimalDigits: 2);
    final youOwe  = _oweTotal('you_owe');
    final theyOwe = _oweTotal('they_owe');

    // Category list for filter sheet (only categories that appear in txns)
    final usedCatIds = <String>{};
    for (final t in _txns) {
      final c = t['category_id'] as String?;
      if (c != null) usedCatIds.add(c);
    }
    final usedCats = kCategories.where((c) => usedCatIds.contains(c.id)).toList();

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: FloatingActionButton(
        backgroundColor: kAccent,
        foregroundColor: dark ? kTextPrimary : Colors.white,
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ConfirmLogScreen()));
          _load();
        },
        child: const Icon(Icons.add),
      ),
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: BackButton(color: textP),
        title: Text('Transactions',
            style: TextStyle(
                color: textP, fontSize: 20, fontWeight: FontWeight.w700)),
        actions: [
          if (_hasActiveFilter)
            TextButton(
              onPressed: _clearFilters,
              child: const Text('Clear all',
                  style: TextStyle(color: kAccent, fontSize: 12)),
            ),
          IconButton(
            icon: Icon(Icons.refresh, color: textS),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: kAccent))
          : Column(children: [

              // ── Summary header ───────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                color: surface,
                child: Column(children: [
                  Row(children: [
                    _SummaryTile(
                      label: 'Transactions',
                      value: rows.length.toString(),
                      color: kAccent, dark: dark,
                    ),
                    const SizedBox(width: 20),
                    _SummaryTile(
                      label: 'Total spent',
                      value: fmt.format(_totalSpent),
                      color: dark ? kError : kErrorLight, dark: dark,
                    ),
                    const Spacer(),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Running balance',
                          style: TextStyle(
                              color: textM, fontSize: 10, letterSpacing: 0.5)),
                      Text(
                        '${_balance < 0 ? '-' : '+'}${fmt.format(_balance.abs())}',
                        style: TextStyle(
                          color: _balance <= 0
                              ? (dark ? kError : kErrorLight)
                              : (dark ? kSuccess : kSuccessLight),
                          fontSize: 15, fontWeight: FontWeight.w800,
                        ),
                      ),
                    ]),
                  ]),

                  // ── Owed banner ────────────────────────────────────────
                  if (_hasOwed) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: border),
                      ),
                      child: Row(children: [
                        Icon(Icons.handshake_outlined, color: kAccent, size: 15),
                        const SizedBox(width: 8),
                        Expanded(child: Wrap(
                          spacing: 14, runSpacing: 4,
                          children: [
                            if (youOwe > 0)
                              Text('You owe: ${fmt.format(youOwe)}',
                                  style: TextStyle(
                                      color: dark ? kError : kErrorLight,
                                      fontSize: 11, fontWeight: FontWeight.w600)),
                            if (theyOwe > 0)
                              Text('They owe: ${fmt.format(theyOwe)}',
                                  style: TextStyle(
                                      color: dark ? kSuccess : kSuccessLight,
                                      fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        )),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('Net', style: TextStyle(color: textM, fontSize: 9)),
                          Text(
                            '${theyOwe >= youOwe ? '+' : '-'}${fmt.format((theyOwe - youOwe).abs())}',
                            style: TextStyle(
                              color: theyOwe >= youOwe
                                  ? (dark ? kSuccess : kSuccessLight)
                                  : (dark ? kError   : kErrorLight),
                              fontSize: 12, fontWeight: FontWeight.w700,
                            ),
                          ),
                        ]),
                      ]),
                    ),
                  ],
                ]),
              ),

              // ── Filter chips ─────────────────────────────────────────────
              Container(
                color: surface,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    // Date
                    _FilterChip(
                      label: _filterDateRanges.isEmpty
                          ? 'Date'
                          : _filterDateRanges.map((r) => switch (r) {
                              'today' => 'Today',
                              'week'  => 'Week',
                              'month' => 'Month',
                              _       => r,
                            }).join(', '),
                      active: _filterDateRanges.isNotEmpty,
                      icon: Icons.calendar_today_outlined,
                      dark: dark,
                      onTap: () => _showMultiSheet(
                        context, dark, surface, border, textP, textM,
                        'Date range',
                        ['today', 'week', 'month'],
                        (r) => switch (r) {
                          'today' => 'Today',
                          'week'  => 'This week',
                          'month' => 'This month',
                          _       => r,
                        },
                        _filterDateRanges,
                        (r) => r,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Payment mode
                    _FilterChip(
                      label: _filterModes.isEmpty
                          ? 'Payment'
                          : _filterModes.map((m) =>
                              m[0].toUpperCase() + m.substring(1)).join(', '),
                      active: _filterModes.isNotEmpty,
                      icon: Icons.payment_outlined,
                      dark: dark,
                      onTap: () => _showMultiSheet(
                        context, dark, surface, border, textP, textM,
                        'Payment mode',
                        _allModes,
                        (m) => m[0].toUpperCase() + m.substring(1),
                        _filterModes,
                        (m) => m,
                        leading: (m) => Icon(
                            _modeIcons[m] ?? Icons.more_horiz,
                            size: 13, color: textM),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Shared/owed
                    _FilterChip(
                      label: _filterShared.isEmpty
                          ? 'Shared'
                          : _filterShared.map((s) => switch (s) {
                              'you_owe'  => 'You owe',
                              'they_owe' => 'They owe',
                              'none'     => 'Not shared',
                              _          => s,
                            }).join(', '),
                      active: _filterShared.isNotEmpty,
                      icon: Icons.people_outline,
                      dark: dark,
                      onTap: () => _showMultiSheet(
                        context, dark, surface, border, textP, textM,
                        'Shared expenses',
                        ['you_owe', 'they_owe', 'none'],
                        (s) => switch (s) {
                          'you_owe'  => 'You owe',
                          'they_owe' => 'They owe',
                          'none'     => 'Not shared',
                          _          => s,
                        },
                        _filterShared,
                        (s) => s,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Categories (multi-select chips inline)
                    ...usedCats.map((cat) {
                      final selected = _filterCategories.contains(cat.id);
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() {
                            if (selected) _filterCategories.remove(cat.id);
                            else          _filterCategories.add(cat.id);
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: selected
                                  ? cat.color.withOpacity(0.15)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: selected ? cat.color : border,
                                  width: selected ? 1.5 : 1),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(cat.icon,
                                  color: selected ? cat.color : textM, size: 13),
                              const SizedBox(width: 5),
                              Text(cat.name,
                                  style: TextStyle(
                                      color: selected ? cat.color : textM,
                                      fontSize: 11,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w400)),
                            ]),
                          ),
                        ),
                      );
                    }),
                  ]),
                ),
              ),

              // ── Tx list ──────────────────────────────────────────────────
              Expanded(
                child: rows.isEmpty
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              color: textM, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _hasActiveFilter
                                ? 'No transactions match filters'
                                : 'No transactions yet',
                            style: TextStyle(color: textM, fontSize: 14)),
                        ],
                      ))
                    : RefreshIndicator(
                        color: kAccent,
                        backgroundColor: surface,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          itemCount: rows.length,
                          itemBuilder: (ctx, i) {
                            final id = rows[i]['id']?.toString() ?? '';
                            return _TxCard(
                              row:         rows[i],
                              dark:        dark,
                              sharedWith:  _sharedWith[id] ??
                                           (rows[i]['shared_with'] as String?),
                              saving:      _saving.contains(id),
                              onSetShared: (v) => _setSharedWith(id, v),
                              onDelete: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    backgroundColor: surface,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16)),
                                    title: Text('Delete transaction?',
                                        style: TextStyle(color: textP)),
                                    content: Text('Cannot be undone.',
                                        style: TextStyle(color: textS)),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text('Cancel',
                                            style:
                                                TextStyle(color: textS)),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('Delete',
                                            style: TextStyle(
                                                color: kError)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) _delete(id);
                              },
                            );
                          },
                        ),
                      ),
              ),
            ]),
    );
  }
}

// ── Transaction card ───────────────────────────────────────────────────────────

class _TxCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool dark;
  final String? sharedWith;
  final bool saving;
  final void Function(String?) onSetShared;
  final VoidCallback onDelete;

  const _TxCard({
    required this.row, required this.dark,
    required this.sharedWith, required this.saving,
    required this.onSetShared, required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final surface = dark ? kSurface : kSurfaceLight;
    final border  = dark ? kBorder  : kBorderLight;
    final textP   = dark ? kTextPrimary : kTextPrimaryLight;
    final textM   = dark ? kTextMuted   : kTextMutedLight;

    final catId = (row['category_id'] as String?) ?? 'other';
    final cat   = kCategories.firstWhere(
        (c) => c.id == catId,
        orElse: () =>
            kCategories.firstWhere((c) => c.id == 'other'));

    final rawAmount    = (row['amount'] as num?)?.toDouble() ?? 0;
    final theyOwe      = sharedWith == 'they_owe';
    final displayAmount = theyOwe ? rawAmount.abs() : rawAmount;
    final isPositive   = displayAmount >= 0;

    final amtColor = isPositive
        ? (dark ? kSuccess : kSuccessLight)
        : (dark ? kError   : kErrorLight);

    final amtLabel = isPositive
        ? '+S\$ ${displayAmount.toStringAsFixed(2)}'
        : '-S\$ ${displayAmount.abs().toStringAsFixed(2)}';

    final merchant = (row['merchant_name'] as String?)?.isNotEmpty == true
        ? row['merchant_name'] as String
        : cat.name;

    DateTime? dt;
    try {
      dt = DateTime.parse(row['created_at'].toString()).toLocal();
    } catch (_) {}
    final dateStr =
        dt != null ? DateFormat('d MMM, h:mm a').format(dt) : '—';

    final mode = row['payment_mode'] as String?;

    return Dismissible(
      key: ValueKey(row['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: kError.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: kError),
      ),
      confirmDismiss: (_) async { onDelete(); return false; },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Main row ────────────────────────────────────────────────
            Row(children: [
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
                  Text(merchant,
                      style: TextStyle(
                          color: textP, fontWeight: FontWeight.w600,
                          fontSize: 14),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text(dateStr,
                        style: TextStyle(color: textM, fontSize: 11)),
                    if (mode != null && mode.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: kAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(mode.toUpperCase(),
                            style: TextStyle(
                                color: kAccent, fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ]),
                ],
              )),
              // Amount — flips green/positive when they_owe
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(amtLabel,
                    style: TextStyle(
                        color: amtColor, fontWeight: FontWeight.w800,
                        fontSize: 15)),
                if (theyOwe)
                  Text('to collect',
                      style: TextStyle(
                          color: dark ? kSuccess : kSuccessLight,
                          fontSize: 9, fontWeight: FontWeight.w500)),
              ]),
            ]),

            // ── You-owe / They-owe toggle ────────────────────────────────
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.people_outline, color: textM, size: 13),
              const SizedBox(width: 6),
              Text('Shared:',
                  style: TextStyle(color: textM, fontSize: 11)),
              const SizedBox(width: 8),
              _OweToggle(
                sharedWith: sharedWith,
                saving:     saving,
                onSet:      onSetShared,
                dark:       dark,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Owe toggle ─────────────────────────────────────────────────────────────────

class _OweToggle extends StatelessWidget {
  final String? sharedWith;
  final bool saving;
  final void Function(String?) onSet;
  final bool dark;

  const _OweToggle({
    required this.sharedWith, required this.saving,
    required this.onSet, required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final textM = dark ? kTextMuted : kTextMutedLight;
    if (saving) {
      return SizedBox(
        width: 14, height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: kAccent),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _OweChip(
        label: 'You owe', active: sharedWith == 'you_owe',
        color: dark ? kError : kErrorLight, dark: dark,
        onTap: () => onSet(sharedWith == 'you_owe' ? null : 'you_owe'),
      ),
      const SizedBox(width: 6),
      _OweChip(
        label: 'They owe', active: sharedWith == 'they_owe',
        color: dark ? kSuccess : kSuccessLight, dark: dark,
        onTap: () => onSet(sharedWith == 'they_owe' ? null : 'they_owe'),
      ),
      if (sharedWith != null) ...[
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => onSet(null),
          child: Icon(Icons.close, color: textM, size: 12),
        ),
      ],
    ]);
  }
}

class _OweChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final bool dark;

  const _OweChip({
    required this.label, required this.active,
    required this.color, required this.onTap, required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final border = dark ? kBorder : kBorderLight;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? color : border,
              width: active ? 1.5 : 1),
        ),
        child: Text(label,
            style: TextStyle(
                color: active ? color : (dark ? kTextMuted : kTextMutedLight),
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
      ),
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final IconData icon;
  final bool dark;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label, required this.active,
    required this.icon, required this.dark, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = dark ? kSurface : kSurfaceLight;
    final border  = dark ? kBorder  : kBorderLight;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? kAccent.withOpacity(0.15) : surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? kAccent : border, width: active ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              color: active ? kAccent : (dark ? kTextMuted : kTextMutedLight),
              size: 13),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: active ? kAccent : (dark ? kTextMuted : kTextMutedLight),
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    );
  }
}

// ── Summary tile ───────────────────────────────────────────────────────────────

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool dark;

  const _SummaryTile({
    required this.label, required this.value,
    required this.color, required this.dark,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(
          color: dark ? kTextMuted : kTextMutedLight,
          fontSize: 10, letterSpacing: 0.5)),
      Text(value, style: TextStyle(
          color: color, fontSize: 13, fontWeight: FontWeight.w700)),
    ],
  );
}