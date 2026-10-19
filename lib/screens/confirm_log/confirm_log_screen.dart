import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/models/category.dart';
import 'package:tapsense/models/transaction.dart';
import 'package:tapsense/services/transaction_service.dart';

class ConfirmLogScreen extends StatefulWidget {
  final Map<String, dynamic> data;
  const ConfirmLogScreen({super.key, required this.data});

  @override
  State<ConfirmLogScreen> createState() => _ConfirmLogScreenState();
}

class _ConfirmLogScreenState extends State<ConfirmLogScreen> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl   = TextEditingController();
  String _selectedCategory = 'food';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill amount if QR had it
    final amt = widget.data['amount'];
    if (amt != null) _amountCtrl.text = amt.toStringAsFixed(2);
  }

  String get _triggerLabel => switch (widget.data['triggerType']) {
    'qr_scan'      => '📷 QR Scan',
    'card_removed' => '💳 Card Removed',
    'button_press' => '🔘 Button Press',
    _              => '✏️ Manual',
  };

  Future<void> _save() async {
    final amountText = _amountCtrl.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount'),
            backgroundColor: Color(0xFFFF6B6B)));
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount'),
            backgroundColor: Color(0xFFFF6B6B)));
      return;
    }

    setState(() => _saving = true);

    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final tx = Transaction(
      userId: userId,
      amount: amount,
      categoryId: _selectedCategory,
      merchantName: widget.data['merchantName'],
      merchantUen: widget.data['merchantUen'],
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      triggerType: widget.data['triggerType'],
      rawQr: widget.data['rawQr'],
    );

    final success = await TransactionService.save(tx);

    if (mounted) {
      setState(() => _saving = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction logged ✓'),
              backgroundColor: Color(0xFF22C55E)));
        context.go('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save. Saved locally.'),
              backgroundColor: Color(0xFFFF9F43)));
        context.go('/home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text('Log Transaction',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Trigger badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.4)),
            ),
            child: Text(_triggerLabel,
              style: const TextStyle(color: Color(0xFF6C63FF), fontSize: 13)),
          ),

          // Merchant name if present
          if (widget.data['merchantName'] != null) ...[
            const SizedBox(height: 16),
            Text(widget.data['merchantName'],
              style: const TextStyle(color: Colors.white,
                  fontSize: 20, fontWeight: FontWeight.w700)),
            if (widget.data['merchantUen'] != null)
              Text('UEN: ${widget.data['merchantUen']}',
                style: const TextStyle(color: Color(0xFF9E9EBE), fontSize: 12)),
          ],

          const SizedBox(height: 28),

          // Amount field
          const Text('Amount (SGD)',
            style: TextStyle(color: Color(0xFF9E9EBE),
                fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white, fontSize: 28,
                fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              prefixText: 'S\$ ',
              prefixStyle: const TextStyle(color: Color(0xFF9E9EBE),
                  fontSize: 28, fontWeight: FontWeight.w400),
              filled: true,
              fillColor: const Color(0xFF1A1A2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF6C63FF)),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Category picker
          const Text('Category',
            style: TextStyle(color: Color(0xFF9E9EBE),
                fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8,
            children: kCategories.map((cat) {
              final selected = _selectedCategory == cat.id;
              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = cat.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? cat.color.withOpacity(0.2)
                        : const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? cat.color
                          : const Color(0xFF2A2A4A),
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(cat.icon,
                        color: selected ? cat.color
                            : const Color(0xFF9E9EBE),
                        size: 16),
                    const SizedBox(width: 6),
                    Text(cat.name,
                      style: TextStyle(
                        color: selected ? cat.color
                            : const Color(0xFF9E9EBE),
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600 : FontWeight.w400,
                      )),
                  ]),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Note field
          const Text('Note (optional)',
            style: TextStyle(color: Color(0xFF9E9EBE),
                fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            style: const TextStyle(color: Colors.white),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'e.g. Lunch with team',
              hintStyle: const TextStyle(color: Color(0xFF6B6B8A)),
              filled: true,
              fillColor: const Color(0xFF1A1A2E),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF6C63FF)),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Save button
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Transaction',
                      style: TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}