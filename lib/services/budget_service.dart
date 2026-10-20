// lib/services/budget_service.dart
//
// Checks category / monthly budget caps after every transaction save.
// Also wires the BLE buzz level, in-app banner, and background push notification.
//
// Usage (call from confirm_log_screen.dart after Supabase insert):
//
//   await BudgetService.checkAndNotify(
//     context: context,
//     userId:  _userId,
//     categoryId: tx.categoryId,
//   );

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/services/bluetooth_service.dart';
import 'package:tapsense/services/transaction_service.dart';

class BudgetCheckResult {
  final String categoryId;
  final double cap;
  final double spent;
  final double fraction; // spent / cap
  final bool overBudget;
  final bool nearBudget; // fraction > 0.80

  const BudgetCheckResult({
    required this.categoryId,
    required this.cap,
    required this.spent,
    required this.fraction,
    required this.overBudget,
    required this.nearBudget,
  });
}

class BudgetService {
  BudgetService._();

  // ── Core check ──────────────────────────────────────────────────────────────

  /// Returns null if no category-cap goal exists for this category this month.
  static Future<BudgetCheckResult?> checkCategory({
    required String userId,
    required String categoryId,
  }) async {
    final sb  = Supabase.instance.client;
    final now = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    // Find matching category-cap goal
    final goals = await sb
        .from('goals')
        .select()
        .eq('user_id', userId)
        .eq('type', 'category')
        .eq('month', month);

    final list = List<Map<String, dynamic>>.from(goals as List);
    final goal = list.firstWhere(
      (g) => (g['category'] as String?)?.toLowerCase() ==
          categoryId.toLowerCase(),
      orElse: () => <String, dynamic>{},
    );

    if (goal.isEmpty) return null;

    final cap = (goal['target'] as num?)?.toDouble() ?? 0;
    if (cap <= 0) return null;

    // Get actual month spend for this category
    final spendMap = await TransactionService.monthTotalByCategory(userId);
    final spent    = spendMap[categoryId] ?? 0.0;
    final fraction = spent / cap;

    return BudgetCheckResult(
      categoryId: categoryId,
      cap:        cap,
      spent:      spent,
      fraction:   fraction,
      overBudget: spent > cap,
      nearBudget: fraction > 0.80 && spent <= cap,
    );
  }

  // ── Combined check + notify ────────────────────────────────────────────────

  /// Call after a transaction is saved.
  /// Triggers BLE buzz + shows in-app banner + sends background push when
  /// over / near limit.
  static Future<void> checkAndNotify({
    required BuildContext context,
    required String userId,
    required String categoryId,
  }) async {
    try {
      final result = await checkCategory(
        userId: userId,
        categoryId: categoryId,
      );

      if (result == null) {
        // No cap configured — normal confirm buzz
        await walletBluetooth.sendBuzzLevel(WalletBluetooth.kBuzzNormal);
        return;
      }

      // ── BLE buzz ─────────────────────────────────────────────────────────
      await walletBluetooth.sendBuzzForBudget(result.fraction);

      // ── Build alert strings ───────────────────────────────────────────────
      final String pushTitle;
      final String pushBody;
      final Color  bannerColor;
      final IconData bannerIcon;

      if (result.overBudget) {
        pushTitle  = '⚠ Over ${_catLabel(categoryId)} budget!';
        pushBody   = 'S\$${result.spent.toStringAsFixed(0)} spent of '
                     'S\$${result.cap.toStringAsFixed(0)} cap';
        bannerColor = kError;
        bannerIcon  = Icons.warning_amber_rounded;
      } else if (result.nearBudget) {
        final pct = (result.fraction * 100).round();
        pushTitle  = '$pct% of ${_catLabel(categoryId)} budget used';
        pushBody   = 'S\$${(result.cap - result.spent).toStringAsFixed(0)} '
                     'remaining this month';
        bannerColor = kWarning;
        bannerIcon  = Icons.info_outline;
      } else {
        return; // under 80% — no alert needed
      }

      // ── In-app banner (when app is in foreground) ─────────────────────────
      if (context.mounted) {
        _showBanner(
          context:  context,
          message:  '$pushTitle — $pushBody',
          color:    bannerColor,
          icon:     bannerIcon,
        );
      }

      // ── Background push via Supabase Edge Function ────────────────────────
      // Fires even when app is foregrounded — FCM will suppress the system
      // notification if the app is open (foreground handler handles it there).
      _sendPush(userId: userId, title: pushTitle, body: pushBody);

    } catch (_) {
      // Budget check is non-fatal; transaction already saved.
    }
  }

  // ── Push via Edge Function ─────────────────────────────────────────────────

  /// Calls the `send-budget-notification` Supabase Edge Function.
  /// Fire-and-forget — failures are swallowed so the UX isn't affected.
  static Future<void> _sendPush({
    required String userId,
    required String title,
    required String body,
  }) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-budget-notification',
        body: {
          'userId': userId,
          'title':  title,
          'body':   body,
        },
      );
    } catch (_) {
      // Non-fatal
    }
  }

  // ── In-app banner ──────────────────────────────────────────────────────────

  static void _showBanner({
    required BuildContext context,
    required String message,
    required Color color,
    required IconData icon,
  }) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _BudgetBanner(
        message: message,
        color:   color,
        icon:    icon,
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
    // Auto-dismiss after 4 s
    Future.delayed(const Duration(seconds: 4), () {
      if (entry.mounted) entry.remove();
    });
  }

  static String _catLabel(String id) {
    const labels = {
      'food':          'Food',
      'transport':     'Transport',
      'shopping':      'Shopping',
      'health':        'Health',
      'bills':         'Bills',
      'entertainment': 'Entertainment',
      'travel':        'Travel',
      'other':         'Other',
    };
    return labels[id] ?? id;
  }
}

// ── Banner widget ──────────────────────────────────────────────────────────────

class _BudgetBanner extends StatefulWidget {
  final String message;
  final Color  color;
  final IconData icon;
  final VoidCallback onDismiss;

  const _BudgetBanner({
    required this.message,
    required this.color,
    required this.icon,
    required this.onDismiss,
  });

  @override
  State<_BudgetBanner> createState() => _BudgetBannerState();
}

class _BudgetBannerState extends State<_BudgetBanner>
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
              color: widget.color.withOpacity(0.95),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(children: [
              Icon(widget.icon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: widget.onDismiss,
                child: const Icon(Icons.close, color: Colors.white70, size: 16),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}