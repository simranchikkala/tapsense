// lib/screens/transactions/transactions_screen.dart
//
// Redesigned: card/tile list layout (not spreadsheet).
// Features:
//   • Running balance shown in header
//   • Category filter chips (horizontal scroll)
//   • Each tile: category icon + merchant + date + amount (red/green)
//   • "You owe / They owe" toggle — persisted to Supabase `shared_with` column
//     - "They owe" flips the display amount to positive (money coming back to you)
//   • Swipe-to-delete with confirmation
//
// ── SQL migration (run once in Supabase SQL editor) ──────────────────────────
//
//   ALTER TABLE transactions
//     ADD COLUMN IF NOT EXISTS shared_with text
//     CHECK (shared_with IN ('you_owe', 'they_owe'));
//
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/models/category.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});
  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _txns = [];
  bool _loading = true;
  String _filterCategoryId = 'all';

  // You-owe tracking: txn id → 'you_owe' | 'they_owe' | null
  final Map<String, String?> _sharedWith = {};

  // Track which ids are currently being saved (to show micro-spinner)
  final Set<String> _saving = {};

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

      // Seed _sharedWith from DB values
      final Map<String, String?> sw = {};
      for (final t in txns) {
        final id = t['id']?.toString();
        if (id != null) {
          sw[id] = t['shared_with'] as String?;
        }
      }

      setState(() {
        _txns       = txns;
        _sharedWith.clear();
        _sharedWith.addAll(sw);
        _loading    = false;
      });
    } catch (e) {
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

  /// Persist shared_with for a single transaction.
  /// [value] is 'you_owe', 'they_owe', or null (clear).
  Future<void> _setSharedWith(String id, String? value) async {
    // Optimistic update
    setState(() {
      _sharedWith[id] = value;
      _saving.add(id);
    });

    try {
      await _sb
          .from('transactions')
          .update({'shared_with': value})
          .eq('id', id);
    } catch (_) {
      // Revert on failure
      setState(() => _sharedWith[id] = null);
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  List<Map<String, dynamic>> get _filtered => _filterCategoryId == 'all'
      ? _txns
      : _txns
          .where((t) =>
              (t['category_id'] as String?)?.toLowerCase() ==
              _filterCategoryId.toLowerCase())
          .toList();

  // Running balance: sum all amounts in filtered list (negative = spend)
  double get _balance =>
      _filtered.fold(0.0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0));

  double get _totalSpent =>
      _filtered.fold(0.0, (s, t) {
        final v = (t['amount'] as num?)?.toDouble() ?? 0;
        return v < 0 ? s + v.abs() : s;
      });

  // All unique category ids in txns
  List<String> get _catIds {
    final ids = <String>{'all'};
    for (final t in _txns) {
      final c = t['category_id'] as String?;
      if (c != null) ids.add(c);
    }
    return ids.toList();
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

    final rows   = _filtered;
    final fmt    = NumberFormat.currency(symbol: 'S\$', decimalDigits: 2);
    final catIds = _catIds;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: BackButton(color: textP),
        title: Text('Transactions',
            style: TextStyle(
                color: textP, fontSize: 20, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: textS),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: kAccent))
          : Column(
              children: [

                // ── Summary header ─────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  color: surface,
                  child: Row(
                    children: [
                      _SummaryTile(
                        label: 'Transactions',
                        value: rows.length.toString(),
                        color: kAccent,
                        dark:  dark,
                      ),
                      const SizedBox(width: 20),
                      _SummaryTile(
                        label: 'Total spent',
                        value: fmt.format(_totalSpent),
                        color: dark ? kError : kErrorLight,
                        dark:  dark,
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Running balance',
                              style: TextStyle(
                                  color: textM, fontSize: 10,
                                  letterSpacing: 0.5)),
                          Text(
                            '${_balance < 0 ? '-' : '+'}${fmt.format(_balance.abs())}',
                            style: TextStyle(
                              color: _balance <= 0
                                  ? (dark ? kError : kErrorLight)
                                  : (dark ? kSuccess : kSuccessLight),
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── Category filter chips ──────────────────────────────────
                Container(
                  height: 44,
                  color: surface,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    itemCount: catIds.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final id = catIds[i];
                      final selected = id == _filterCategoryId;
                      final cat = id == 'all'
                          ? null
                          : kCategories.firstWhere(
                              (c) => c.id == id,
                              orElse: () => kCategories.firstWhere(
                                  (c) => c.id == 'other'));
                      final color = cat?.color ?? kAccent;

                      return GestureDetector(
                        onTap: () =>
                            setState(() => _filterCategoryId = id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: selected
                                ? color.withOpacity(0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected ? color : border,
                              width: selected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (cat != null) ...[
                                Icon(cat.icon,
                                    color: selected ? color : textS,
                                    size: 12),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                id == 'all' ? 'All' : (cat?.name ?? id),
                                style: TextStyle(
                                  color: selected ? color : textS,
                                  fontSize: 12,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ── Tx list ────────────────────────────────────────────────
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_long_outlined,
                                  color: textM, size: 48),
                              const SizedBox(height: 12),
                              Text('No transactions',
                                  style: TextStyle(
                                      color: textM, fontSize: 14)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          color: kAccent,
                          backgroundColor: surface,
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                                16, 12, 16, 100),
                            itemCount: rows.length,
                            itemBuilder: (ctx, i) {
                              final id = rows[i]['id']?.toString() ?? '';
                              return _TxCard(
                                row:        rows[i],
                                dark:       dark,
                                sharedWith: _sharedWith[id],
                                saving:     _saving.contains(id),
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
                                                style: TextStyle(
                                                    color: textS))),
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Delete',
                                                style: TextStyle(
                                                    color: kError))),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    _delete(id);
                                  }
                                },
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

// ── Transaction card ───────────────────────────────────────────────────────────

class _TxCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool dark;
  final String? sharedWith; // 'you_owe' | 'they_owe' | null
  final bool saving;
  final void Function(String?) onSetShared;
  final VoidCallback onDelete;

  const _TxCard({
    required this.row,
    required this.dark,
    required this.sharedWith,
    required this.saving,
    required this.onSetShared,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final surface = dark ? kSurface : kSurfaceLight;
    final border  = dark ? kBorder  : kBorderLight;
    final textP   = dark ? kTextPrimary   : kTextPrimaryLight;
    final textM   = dark ? kTextMuted     : kTextMutedLight;

    final catId = row['category_id'] as String? ?? 'other';
    final cat   = kCategories.firstWhere(
        (c) => c.id == catId,
        orElse: () => kCategories.firstWhere((c) => c.id == 'other'));

    final rawAmount = (row['amount'] as num?)?.toDouble() ?? 0;

    // "They owe" means money is coming back — flip display to positive.
    // The stored amount is unchanged; this is display only.
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
    final dateStr = dt != null
        ? DateFormat('d MMM, h:mm a').format(dt)
        : '—';

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
      confirmDismiss: (_) async {
        onDelete();
        return false; // deletion handled manually
      },
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
            // ── Main row ──────────────────────────────────────────────────
            Row(children: [
              // Category icon
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: cat.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(cat.icon, color: cat.color, size: 18),
              ),
              const SizedBox(width: 12),
              // Merchant + date
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
              // Amount — flips to green + positive when they_owe
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(amtLabel,
                      style: TextStyle(
                          color: amtColor, fontWeight: FontWeight.w800,
                          fontSize: 15)),
                  if (theyOwe)
                    Text('to collect',
                        style: TextStyle(
                            color: dark ? kSuccess : kSuccessLight,
                            fontSize: 9,
                            fontWeight: FontWeight.w500)),
                ],
              ),
            ]),

            // ── You-owe / They-owe row ─────────────────────────────────────
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

// ── You-owe / They-owe toggle ──────────────────────────────────────────────────

class _OweToggle extends StatelessWidget {
  final String? sharedWith;
  final bool saving;
  final void Function(String?) onSet;
  final bool dark;

  const _OweToggle({
    required this.sharedWith,
    required this.saving,
    required this.onSet,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    final textM = dark ? kTextMuted : kTextMutedLight;

    if (saving) {
      return SizedBox(
        width: 14, height: 14,
        child: CircularProgressIndicator(
            strokeWidth: 1.5, color: kAccent),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _OweChip(
          label:  'You owe',
          active: sharedWith == 'you_owe',
          color:  kError,
          onTap:  () => onSet(sharedWith == 'you_owe' ? null : 'you_owe'),
          dark:   dark,
        ),
        const SizedBox(width: 6),
        _OweChip(
          label:  'They owe',
          active: sharedWith == 'they_owe',
          color:  kSuccess,
          onTap:  () => onSet(sharedWith == 'they_owe' ? null : 'they_owe'),
          dark:   dark,
        ),
        if (sharedWith != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => onSet(null),
            child: Icon(Icons.close, color: textM, size: 12),
          ),
        ],
      ],
    );
  }
}

class _OweChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  final bool dark;

  const _OweChip({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
    required this.dark,
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
          border: Border.all(
            color: active ? color : border,
            width: active ? 1.5 : 1,
          ),
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: dark ? kTextMuted : kTextMutedLight,
                fontSize: 10, letterSpacing: 0.5)),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }
}