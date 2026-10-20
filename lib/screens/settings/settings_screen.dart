import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/services/auth_service.dart';

// ── Currency list ─────────────────────────────────────────────────────────────
class CurrencyOption {
  final String code;
  final String symbol;
  final String name;
  const CurrencyOption(this.code, this.symbol, this.name);
}

const kCurrencies = [
  CurrencyOption('SGD', 'S\$', 'Singapore Dollar'),
  CurrencyOption('USD', '\$',  'US Dollar'),
  CurrencyOption('EUR', '€',   'Euro'),
  CurrencyOption('GBP', '£',   'British Pound'),
  CurrencyOption('INR', '₹',   'Indian Rupee'),
  CurrencyOption('MYR', 'RM',  'Malaysian Ringgit'),
  CurrencyOption('IDR', 'Rp',  'Indonesian Rupiah'),
  CurrencyOption('THB', '฿',   'Thai Baht'),
  CurrencyOption('PHP', '₱',   'Philippine Peso'),
  CurrencyOption('AUD', 'A\$', 'Australian Dollar'),
  CurrencyOption('JPY', '¥',   'Japanese Yen'),
  CurrencyOption('CNY', '¥',   'Chinese Yuan'),
  CurrencyOption('HKD', 'HK\$','Hong Kong Dollar'),
];

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameCtrl     = TextEditingController();
  final _incomeCtrl   = TextEditingController();
  final _budgetCtrl   = TextEditingController();
  final _goalNameCtrl = TextEditingController();
  final _goalAmtCtrl  = TextEditingController();

  String _currency = 'SGD';
  String _goalMonth = '';
  bool _saving = false;
  bool _loading = true;

  // Categories
  List<Map<String, dynamic>> _categories = [];
  final _newCatCtrl = TextEditingController();
  String _newCatColor = '#FF8C42';

  static const _colorOptions = [
    '#FF8C42', '#22C55E', '#3B82F6', '#A78BFA',
    '#F43F5E', '#F59E0B', '#06B6D4', '#EC4899',
    '#14B8A6', '#8B5CF6', '#EF4444', '#64748B',
  ];

  static const _months = [
    '', 'January', 'February', 'March', 'April',
    'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Replace the _load() method with this:
Future<void> _load() async {
  final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
  try {
    final profile = await Supabase.instance.client
        .from('profiles').select().eq('id', userId).single();
    final catsRaw = await Supabase.instance.client
        .from('categories').select().eq('user_id', userId);

    List<Map<String, dynamic>> cats = (catsRaw as List)
        .map((c) => {
              'name':   c['name'] as String,
              'color':  c['color'] as String? ?? '#FF8C42',
              'budget': c['budget'] ?? 0,
            })
        .toList();

    // If no categories in Supabase, seed from hardcoded defaults
    if (cats.isEmpty) {
      cats = _defaultCategories();
      // Write them to Supabase so they persist
      await Supabase.instance.client.from('categories').insert(
        cats.map((c) => {
          'user_id': userId,
          'name':    c['name'],
          'color':   c['color'],
          'budget':  0,
        }).toList(),
      );
    }

    if (mounted) {
      setState(() {
        _nameCtrl.text   = profile['name']   ?? '';
        _incomeCtrl.text = profile['income']?.toString() ?? '';
        _budgetCtrl.text = profile['budget']?.toString() ?? '';
        _currency        = profile['currency'] ?? 'SGD';
        _categories      = cats;
        _loading         = false;
      });
    }
  } catch (_) {
    // Profile may not exist yet — still show default categories
    if (mounted) {
      setState(() {
        _categories = _defaultCategories();
        _loading    = false;
      });
    }
  }
}

// Add this helper method to _SettingsScreenState:
List<Map<String, dynamic>> _defaultCategories() => [
  {'name': 'Food',          'color': '#FF8C42', 'budget': 0},
  {'name': 'Transport',     'color': '#22C55E', 'budget': 0},
  {'name': 'Shopping',      'color': '#A78BFA', 'budget': 0},
  {'name': 'Groceries',     'color': '#3B82F6', 'budget': 0},
  {'name': 'Health',        'color': '#F43F5E', 'budget': 0},
  {'name': 'Bills',         'color': '#F59E0B', 'budget': 0},
  {'name': 'Entertainment', 'color': '#06B6D4', 'budget': 0},
  {'name': 'Other',         'color': '#64748B', 'budget': 0},
];

  // 50-30-20 calculation
  double get _income => double.tryParse(_incomeCtrl.text) ?? 0;
  String get _symbol =>
      kCurrencies.firstWhere((c) => c.code == _currency,
          orElse: () => kCurrencies.first).symbol;

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _incomeCtrl.text.trim().isEmpty ||
        _budgetCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Fill in name, income and budget'),
        backgroundColor: kError,
      ));
      return;
    }

    setState(() => _saving = true);
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';

    try {
      // Update profile
      await Supabase.instance.client.from('profiles').update({
        'name':     _nameCtrl.text.trim(),
        'income':   int.tryParse(_incomeCtrl.text) ?? 0,
        'budget':   int.tryParse(_budgetCtrl.text) ?? 0,
        'currency': _currency,
      }).eq('id', userId);

      // Sync categories
      await Supabase.instance.client
          .from('categories').delete().eq('user_id', userId);
      if (_categories.isNotEmpty) {
        await Supabase.instance.client.from('categories').insert(
          _categories.map((c) => {
            'user_id': userId,
            'name':    c['name'],
            'color':   c['color'],
            'budget':  c['budget'] ?? 0,
          }).toList(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Settings saved ✓'),
          backgroundColor: kSuccess,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: kError,
        ));
      }
    }

    if (mounted) setState(() => _saving = false);
  }

  void _addCategory() {
    final name = _newCatCtrl.text.trim();
    if (name.isEmpty) return;
    if (_categories.any((c) =>
        c['name'].toString().toLowerCase() == name.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Category already exists'),
        backgroundColor: kError,
      ));
      return;
    }
    setState(() {
      _categories.add({'name': name, 'color': _newCatColor, 'budget': 0});
      _newCatCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Settings'),
        leading: BackButton(
            color: kTextPrimary,
            onPressed: () => Navigator.pop(context)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kAccent))
                : const Text('Save',
                    style: TextStyle(
                        color: kAccent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kAccent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
              children: [

                // ── Profile ─────────────────────────────────────
                _SectionHeader('Profile'),
                _Field('Name', _nameCtrl, hint: 'Your name'),
                const SizedBox(height: 12),
                _Field('Monthly Income', _incomeCtrl,
                    hint: '0.00', numeric: true,
                    onChanged: (_) => setState(() {})),
                const SizedBox(height: 12),
                _Field('Monthly Budget', _budgetCtrl,
                    hint: '0.00', numeric: true),

                // 50-30-20 tip
                if (_income > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kAccent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kAccent.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('50-30-20 Guide',
                          style: TextStyle(
                            color: kAccent, fontSize: 12,
                            fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _TipTile('Needs 50%',
                                '$_symbol${(_income * 0.5).toStringAsFixed(0)}'),
                            _TipTile('Wants 30%',
                                '$_symbol${(_income * 0.3).toStringAsFixed(0)}'),
                            _TipTile('Savings 20%',
                                '$_symbol${(_income * 0.2).toStringAsFixed(0)}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                // ── Currency ─────────────────────────────────────
                _SectionHeader('Currency'),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _currency,
                      dropdownColor: kSurface,
                      style: const TextStyle(color: kTextPrimary),
                      isExpanded: true,
                      items: kCurrencies.map((c) => DropdownMenuItem(
                        value: c.code,
                        child: Text('${c.symbol}  ${c.name} (${c.code})',
                          style: const TextStyle(
                            color: kTextPrimary, fontSize: 14)),
                      )).toList(),
                      onChanged: (v) =>
                          setState(() => _currency = v ?? 'SGD'),
                    ),
                  ),
                ),

                // ── Savings Goal ─────────────────────────────────
                _SectionHeader('Savings Goal'),
                _Field('Goal Name', _goalNameCtrl,
                    hint: 'e.g. New laptop'),
                const SizedBox(height: 12),
                _Field('Target Amount', _goalAmtCtrl,
                    hint: '0.00', numeric: true),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _goalMonth,
                      dropdownColor: kSurface,
                      isExpanded: true,
                      items: _months.map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(
                          m.isEmpty ? 'Target month (optional)' : m,
                          style: TextStyle(
                            color: m.isEmpty ? kTextMuted : kTextPrimary,
                            fontSize: 14)),
                      )).toList(),
                      onChanged: (v) =>
                          setState(() => _goalMonth = v ?? ''),
                    ),
                  ),
                ),

                // ── Categories ───────────────────────────────────
                _SectionHeader('Categories'),

                // Add new category
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _newCatCtrl,
                      style: const TextStyle(color: kTextPrimary),
                      decoration: InputDecoration(
                        hintText: 'New category name',
                        hintStyle: const TextStyle(color: kTextMuted),
                        filled: true,
                        fillColor: kSurface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _addCategory,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kAccent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                    ),
                    child: const Text('Add'),
                  ),
                ]),

                // Colour picker for new category
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8,
                  children: _colorOptions.map((hex) {
                    final selected = _newCatColor == hex;
                    return GestureDetector(
                      onTap: () => setState(() => _newCatColor = hex),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: Color(
                              int.parse('FF${hex.substring(1)}', radix: 16)),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),

                // Category list
                ..._categories.asMap().entries.map((entry) {
                  final i = entry.key;
                  final cat = entry.value;
                  final catColor = Color(int.parse(
                      'FF${(cat['color'] as String).substring(1)}',
                      radix: 16));
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kBorder),
                    ),
                    child: Row(children: [
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                            color: catColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(cat['name'],
                        style: const TextStyle(
                          color: kTextPrimary, fontSize: 14))),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                            color: kTextPrimary, fontSize: 13),
                          decoration: const InputDecoration(
                            hintText: 'budget',
                            hintStyle: TextStyle(
                              color: kTextMuted, fontSize: 12),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          controller: TextEditingController(
                              text: cat['budget']?.toString() ?? ''),
                          onChanged: (v) => _categories[i]['budget'] =
                              int.tryParse(v) ?? 0,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: kTextMuted, size: 18),
                        onPressed: () => setState(
                            () => _categories.removeAt(i)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ]),
                  );
                }),

                // ── Danger zone ──────────────────────────────────
                _SectionHeader('Danger Zone'),
                OutlinedButton.icon(
                  onPressed: () => _confirmAction(
                    'Sign out?',
                    'You will need to log in again.',
                    () async {
                      await AuthService.signOut();
                      if (context.mounted) context.go('/login');
                    },
                  ),
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kWarning,
                    side: const BorderSide(color: kWarning),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _confirmAction(
                    'Delete all transactions?',
                    'This cannot be undone.',
                    () async {
                      final userId = Supabase.instance.client
                          .auth.currentUser?.id ?? '';
                      await Supabase.instance.client
                          .from('transactions')
                          .delete()
                          .eq('user_id', userId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('All transactions deleted'),
                            backgroundColor: kSuccess,
                          ),
                        );
                      }
                    },
                  ),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Clear All Transactions'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kError,
                    side: const BorderSide(color: kError),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
    );
  }

  void _confirmAction(String title, String body, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(color: kTextPrimary)),
        content: Text(body,
            style: const TextStyle(color: kTextSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: kTextSecondary)),
          ),
          TextButton(
            onPressed: () { Navigator.pop(context); onConfirm(); },
            child: const Text('Confirm',
                style: TextStyle(color: kError)),
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Text(title,
      style: const TextStyle(
        color: kTextSecondary, fontSize: 11,
        fontWeight: FontWeight.w700, letterSpacing: 1)),
  );
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String hint;
  final bool numeric;
  final ValueChanged<String>? onChanged;

  const _Field(this.label, this.ctrl, {
    this.hint = '', this.numeric = false, this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label,
        style: const TextStyle(
          color: kTextMuted, fontSize: 11,
          fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      TextField(
        controller: ctrl,
        onChanged: onChanged,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: const TextStyle(color: kTextPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: kTextMuted),
          filled: true,
          fillColor: kSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kAccent),
          ),
        ),
      ),
    ],
  );
}

class _TipTile extends StatelessWidget {
  final String label;
  final String value;
  const _TipTile(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value,
      style: const TextStyle(
        color: kTextPrimary, fontWeight: FontWeight.w700,
        fontSize: 14)),
    Text(label,
      style: const TextStyle(color: kTextMuted, fontSize: 10)),
  ]);
}