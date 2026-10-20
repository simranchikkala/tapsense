// lib/screens/confirm_log/confirm_log_screen.dart
//
// Debit-only: credit toggle removed entirely.
// Amount stored as negative (spend convention).
// After save → BudgetService.checkAndNotify triggers BLE buzz + in-app banner.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/models/category.dart';
import 'package:tapsense/models/transaction.dart';
import 'package:tapsense/services/budget_service.dart';
import 'package:tapsense/services/transaction_service.dart';

class ConfirmLogScreen extends StatefulWidget {
  const ConfirmLogScreen({super.key});
  @override
  State<ConfirmLogScreen> createState() => _ConfirmLogScreenState();
}

class _ConfirmLogScreenState extends State<ConfirmLogScreen> {
  // ── controllers ──────────────────────────────────────────────────────────
  final _amountCtrl = TextEditingController();
  final _merchantCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  // ── state ─────────────────────────────────────────────────────────────────
  String _categoryId = 'other';
  bool _saving = false;
  String? _err;

  // ── extras passed from previous screen ───────────────────────────────────
  String? _triggerType;
  String? _rawQr;
  String? _voiceTranscript;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    if (extra != null && _triggerType == null) {
      _triggerType = extra['triggerType'] as String? ?? 'manual';
      _rawQr       = extra['rawQr'] as String?;
      _voiceTranscript = extra['voiceTranscript'] as String?;

      final merchant = extra['merchantName'] as String?;
      if (merchant != null && merchant.isNotEmpty) {
        _merchantCtrl.text = merchant;
      }

      final amount = extra['amount'];
      if (amount != null) {
        final raw = amount is double ? amount : double.tryParse(amount.toString());
        if (raw != null) {
          _amountCtrl.text = raw.abs().toStringAsFixed(2);
        }
      }
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // ── save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final rawText = _amountCtrl.text.trim();
    final rawAmount = double.tryParse(rawText);
    if (rawAmount == null || rawAmount <= 0) {
      setState(() => _err = 'Enter a valid amount greater than 0');
      return;
    }

    setState(() { _saving = true; _err = null; });

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() { _saving = false; _err = 'Not signed in'; });
      return;
    }

    // Always debit — negative sign = spend
    final signedAmount = -rawAmount.abs();

    final tx = Transaction(
      userId:       userId,
      amount:       signedAmount,
      categoryId:   _categoryId,
      merchantName: _merchantCtrl.text.trim().isEmpty
          ? null
          : _merchantCtrl.text.trim(),
      note:         _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      triggerType:  _triggerType ?? 'manual',
      rawQr:        _rawQr,
      paymentMode:  _rawQr != null ? 'sgqr' : 'manual',
      txType:       'debit',
    );

    try {
      await TransactionService.save(tx);

      // ── Budget check → BLE buzz + in-app banner ──────────────────────────
      if (mounted) {
        await BudgetService.checkAndNotify(
          context:    context,
          userId:     userId,
          categoryId: _categoryId,
        );
      }

      if (mounted) context.pop();
    } catch (e) {
      setState(() { _saving = false; _err = 'Save failed: $e'; });
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final bg      = dark ? kBg      : kBgLight;
    final surface = dark ? kSurface : kSurfaceLight;
    final border  = dark ? kBorder  : kBorderLight;
    final textP   = dark ? kTextPrimary   : kTextPrimaryLight;
    final textS   = dark ? kTextSecondary : kTextSecondaryLight;
    final textM   = dark ? kTextMuted     : kTextMutedLight;

    InputDecoration fieldDec(String hint, {String? prefix}) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: textM),
      prefixText: prefix,
      prefixStyle: TextStyle(color: textM, fontSize: 15),
      filled: true,
      fillColor: dark ? kBg : kBgLight,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kError, width: 1.5)),
    );

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: BackButton(color: textP),
        title: Text('Log Spend',
            style: TextStyle(
                color: textP, fontSize: 20, fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Voice transcript badge ────────────────────────────────────
            if (_voiceTranscript != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: kOrange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kOrange.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.mic, color: kOrange, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '"$_voiceTranscript"',
                      style: TextStyle(
                          color: kOrange, fontSize: 12,
                          fontStyle: FontStyle.italic),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            // ── Debit badge (always) ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kError.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kError.withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.arrow_downward, color: kError, size: 13),
                const SizedBox(width: 5),
                Text('Spend',
                    style: TextStyle(
                        color: kError, fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ]),
            ),

            const SizedBox(height: 20),

            // ── Amount ────────────────────────────────────────────────────
            _Label('Amount (S\$)', textM),
            const SizedBox(height: 6),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                  color: kError, fontSize: 28, fontWeight: FontWeight.w800),
              decoration: fieldDec('0.00', prefix: 'S\$ '),
              onChanged: (_) => setState(() => _err = null),
            ),

            const SizedBox(height: 16),

            // ── Merchant ──────────────────────────────────────────────────
            _Label('Merchant / Payee (optional)', textM),
            const SizedBox(height: 6),
            TextField(
              controller: _merchantCtrl,
              style: TextStyle(color: textP),
              decoration: fieldDec('e.g. 7-Eleven, Grab'),
              textCapitalization: TextCapitalization.words,
            ),

            const SizedBox(height: 16),

            // ── Category ──────────────────────────────────────────────────
            _Label('Category', textM),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kCategories.map((cat) {
                final selected = _categoryId == cat.id;
                return GestureDetector(
                  onTap: () => setState(() => _categoryId = cat.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? cat.color.withOpacity(0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? cat.color : border,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(cat.icon,
                          color: selected ? cat.color : textS,
                          size: 14),
                      const SizedBox(width: 6),
                      Text(cat.name,
                          style: TextStyle(
                            color: selected ? cat.color : textS,
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                          )),
                    ]),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // ── Note ──────────────────────────────────────────────────────
            _Label('Note (optional)', textM),
            const SizedBox(height: 6),
            TextField(
              controller: _noteCtrl,
              style: TextStyle(color: textP),
              decoration: fieldDec('Add a note…'),
              maxLines: 2,
            ),

            // ── Error ─────────────────────────────────────────────────────
            if (_err != null) ...[
              const SizedBox(height: 12),
              Text(_err!,
                  style: TextStyle(
                      color: dark ? kError : kErrorLight, fontSize: 12)),
            ],

            const SizedBox(height: 24),

            // ── Save button ───────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kError,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Log Spend',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── helper widgets ─────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  final Color color;
  const _Label(this.text, this.color);
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w600));
}