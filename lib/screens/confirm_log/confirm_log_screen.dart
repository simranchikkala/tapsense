import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/models/category.dart';
import 'package:tapsense/models/transaction.dart' as model;
import 'package:tapsense/services/transaction_service.dart';

class ConfirmLogScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  const ConfirmLogScreen({super.key, required this.data});

  @override
  State<ConfirmLogScreen> createState() => _ConfirmLogScreenState();
}

class _ConfirmLogScreenState extends State<ConfirmLogScreen> {
  late TextEditingController _amountCtrl;
  late TextEditingController _noteCtrl;
  String _selectedCategoryId = 'other';
  String? _paymentMode;
  DateTime _txDate = DateTime.now();
  bool _saving = false;
  String _currencyCode = 'SGD';

  @override
  void initState() {
    super.initState();
    final amount = widget.data['amount'];
    _amountCtrl = TextEditingController(
      text: amount != null ? amount.toString() : '',
    );
    _noteCtrl = TextEditingController(
      text: widget.data['merchantName'] ?? '',
    );

    // Auto-set payment mode based on trigger
    final trigger = widget.data['triggerType'] ?? 'manual';
    if (trigger == 'qr_scan')      _paymentMode = 'paynow';
    if (trigger == 'card_removed') _paymentMode = 'card';
    if (trigger == 'button_press') _paymentMode = 'card';

    _loadCurrency();
  }

  Future<void> _loadCurrency() async {
    final userId =
        Supabase.instance.client.auth.currentUser?.id ?? '';
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('currency')
          .eq('id', userId)
          .single();
      if (mounted) {
        setState(() => _currencyCode = profile['currency'] ?? 'SGD');
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final amountStr = _amountCtrl.text.trim();
    if (amountStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter an amount'),
        backgroundColor: kError,
      ));
      return;
    }
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a valid amount'),
        backgroundColor: kError,
      ));
      return;
    }

    setState(() => _saving = true);

    final userId =
        Supabase.instance.client.auth.currentUser?.id ?? '';

    final now = DateTime.now();
    final tx = model.Transaction(
      userId: userId,
      amount: amount,
      categoryId: _selectedCategoryId,
      note: _noteCtrl.text.trim(),
      merchantName: widget.data['merchantName'] ?? '',
      triggerType: widget.data['triggerType'] ?? 'manual',
      paymentMode: _paymentMode,
      createdAt: DateTime(
        _txDate.year, _txDate.month, _txDate.day,
        now.hour, now.minute,
      ),
    );

    await TransactionService.save(tx);

    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Transaction logged ✓'),
        backgroundColor: kSuccess,
      ));
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = kCategories;
    final isManual =
        (widget.data['triggerType'] ?? 'manual') == 'manual';

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Log Transaction'),
        leading: BackButton(
          color: kTextPrimary,
          onPressed: () => context.go('/home'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [

          // Trigger badge
          if (widget.data['triggerType'] != null) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _triggerColor(widget.data['triggerType'])
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _triggerColor(widget.data['triggerType'])
                        .withOpacity(0.4),
                  ),
                ),
                child: Text(
                  _triggerLabel(widget.data['triggerType']),
                  style: TextStyle(
                    color: _triggerColor(widget.data['triggerType']),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Merchant name
          if ((widget.data['merchantName'] as String? ?? '')
              .isNotEmpty) ...[
            Text(
              widget.data['merchantName'],
              style: const TextStyle(
                color: kTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            if ((widget.data['merchantUen'] as String? ?? '')
                .isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'UEN: ${widget.data['merchantUen']}',
                  style: const TextStyle(
                      color: kTextMuted, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 24),
          ],

          // Amount
          Text('Amount ($_currencyCode)',
            style: const TextStyle(
              color: kTextMuted, fontSize: 11,
              fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              color: kTextPrimary, fontSize: 28,
              fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: const TextStyle(
                  color: kTextMuted, fontSize: 28),
              filled: true,
              fillColor: kSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kAccent)),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Text(_currencySymbol(_currencyCode),
                  style: const TextStyle(
                    color: kTextSecondary, fontSize: 24,
                    fontWeight: FontWeight.w400)),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),

          const SizedBox(height: 24),

          // Category
          const Text('CATEGORY',
            style: TextStyle(color: kTextMuted, fontSize: 11,
                fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: categories.map((cat) {
              final selected = _selectedCategoryId == cat.id;
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedCategoryId = cat.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? cat.color.withOpacity(0.2) : kSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? cat.color : kBorder,
                      width: selected ? 1.5 : 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(cat.icon, size: 14,
                          color: selected
                              ? cat.color : kTextSecondary),
                      const SizedBox(width: 6),
                      Text(cat.name,
                        style: TextStyle(
                          color: selected
                              ? cat.color : kTextSecondary,
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600 : FontWeight.w400)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Payment mode
          const Text('PAYMENT MODE',
            style: TextStyle(color: kTextMuted, fontSize: 11,
                fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: ['cash', 'card', 'paynow', 'grabpay', 'other']
                .map((mode) {
              final selected = _paymentMode == mode;
              return GestureDetector(
                onTap: () => setState(() => _paymentMode = mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? kAccent.withOpacity(0.2) : kSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? kAccent : kBorder,
                      width: selected ? 1.5 : 1),
                  ),
                  child: Text(_modeLabel(mode),
                    style: TextStyle(
                      color: selected ? kAccent : kTextSecondary,
                      fontSize: 13,
                      fontWeight: selected
                          ? FontWeight.w600 : FontWeight.w400)),
                ),
              );
            }).toList(),
          ),

          // Date picker — manual only
          if (isManual) ...[
            const SizedBox(height: 24),
            const Text('DATE',
              style: TextStyle(color: kTextMuted, fontSize: 11,
                  fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _txDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  builder: (context, child) => Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: kAccent,
                        surface: kSurface,
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (picked != null) {
                  setState(() => _txDate = picked);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: kSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorder),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today,
                      color: kTextSecondary, size: 16),
                  const SizedBox(width: 10),
                  Text(DateFormat('d MMM yyyy').format(_txDate),
                    style: const TextStyle(
                        color: kTextPrimary, fontSize: 14)),
                ]),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Note
          const Text('NOTE',
            style: TextStyle(color: kTextMuted, fontSize: 11,
                fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _noteCtrl,
            style: const TextStyle(color: kTextPrimary),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Optional note…',
              hintStyle: const TextStyle(color: kTextMuted),
              filled: true,
              fillColor: kSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kAccent)),
            ),
          ),

          const SizedBox(height: 36),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                disabledBackgroundColor:
                    kAccent.withOpacity(0.4),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white))
                  : const Text('Log Transaction',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  String _triggerLabel(String type) {
    switch (type) {
      case 'card_removed': return '💳 Card Tap Detected';
      case 'button_press': return '🔘 Button Press';
      case 'qr_scan':      return '📷 QR Scanned';
      default:             return '✏️ Manual Entry';
    }
  }

  Color _triggerColor(String type) {
    switch (type) {
      case 'card_removed': return kAccent;
      case 'button_press': return kInfo;
      case 'qr_scan':      return kSuccess;
      default:             return kTextSecondary;
    }
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'cash':    return '💵 Cash';
      case 'card':    return '💳 Card';
      case 'paynow':  return '📱 PayNow';
      case 'grabpay': return '🟢 GrabPay';
      default:        return '• Other';
    }
  }

  String _currencySymbol(String code) {
    const map = {
      'SGD': 'S\$', 'USD': '\$',  'EUR': '€',  'GBP': '£',
      'INR': '₹',   'MYR': 'RM',  'IDR': 'Rp', 'THB': '฿',
      'PHP': '₱',   'AUD': 'A\$', 'JPY': '¥',  'CNY': '¥',
      'HKD': 'HK\$',
    };
    return map[code] ?? code;
  }
}