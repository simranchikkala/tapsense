// lib/screens/goals/goals_screen.dart
//
// Three goal types:
//   1. savings  – save a fixed amount by a target date
//   2. monthly  – stay under a total monthly spend limit
//   3. category – keep a specific category under a monthly cap
//
// Fix: _AddGoalSheet now uses kCategories chip picker (stores category_id)
//      instead of a free-text TextField. _GoalCard displays the category
//      name by looking up kCategories by the stored id.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/models/category.dart';

// ─── model ───────────────────────────────────────────────────────────────────

enum GoalType { savings, monthly, category }

class Goal {
  final String id;
  final GoalType type;
  final String name;
  final double target;
  final double current;     // filled from transactions at load time
  final String? category;   // for GoalType.category — stores category_id
  final DateTime? deadline; // for GoalType.savings
  final String month;       // 'YYYY-MM' for monthly / category goals

  const Goal({
    required this.id,
    required this.type,
    required this.name,
    required this.target,
    required this.current,
    this.category,
    this.deadline,
    required this.month,
  });

  double get progress => target <= 0 ? 0 : (current / target).clamp(0, 1);
  bool get achieved => current >= target;
}

// ─── screen ──────────────────────────────────────────────────────────────────

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final _sb = Supabase.instance.client;
  List<Goal> _goals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── data ───────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) { setState(() => _loading = false); return; }

    try {
      final rawGoals = await _sb
          .from('goals')
          .select()
          .eq('user_id', uid)
          .order('created_at');

      // Fetch this month's transactions for progress calc
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
      final rawTxns = await _sb
          .from('transactions')
          .select('amount, category, created_at')
          .eq('user_id', uid)
          .gte('created_at', monthStart);

      final txns = List<Map<String, dynamic>>.from(rawTxns as List);
      final totalSpent = txns.fold(0.0, (s, t) {
        final v = (t['amount'] as num?)?.toDouble() ?? 0;
        return s + v.abs();
      });

      final List<Goal> goals = [];
      for (final g in (rawGoals as List)) {
        final type = switch (g['type'] as String? ?? 'savings') {
          'monthly'  => GoalType.monthly,
          'category' => GoalType.category,
          _          => GoalType.savings,
        };

        double current = 0;
        if (type == GoalType.monthly) {
          current = totalSpent;
        } else if (type == GoalType.category) {
          final cat = g['category'] as String? ?? '';
          current = txns
              .where((t) =>
                  (t['category'] as String?)?.toLowerCase() ==
                  cat.toLowerCase())
              .fold(0.0, (s, t) =>
                  s + ((t['amount'] as num?)?.toDouble().abs() ?? 0));
        } else {
          // savings – read from manual 'current' column
          current = (g['current'] as num?)?.toDouble() ?? 0;
        }

        DateTime? deadline;
        if (g['deadline'] != null) {
          try { deadline = DateTime.parse(g['deadline'] as String); } catch (_) {}
        }

        goals.add(Goal(
          id:       g['id'].toString(),
          type:     type,
          name:     g['name'] as String? ?? 'Goal',
          target:   (g['target'] as num?)?.toDouble() ?? 0,
          current:  current,
          category: g['category'] as String?,
          deadline: deadline,
          month:    g['month'] as String? ?? '',
        ));
      }

      if (mounted) setState(() { _goals = goals; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String id) async {
    await _sb.from('goals').delete().eq('id', id);
    _load();
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final bg      = dark ? kBg      : kBgLight;
    final surface = dark ? kSurface : kSurfaceLight;
    final textP   = dark ? kTextPrimary   : kTextPrimaryLight;
    final textM   = dark ? kTextMuted     : kTextMutedLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: BackButton(color: textP),
        title: Text('Goals',
            style: TextStyle(
                color: textP, fontSize: 20, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: kAccent),
            onPressed: () => _showAddGoal(context),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: textM),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: kAccent))
          : _goals.isEmpty
              ? _emptyState(textP, textM, context)
              : RefreshIndicator(
                  color: kAccent,
                  backgroundColor: surface,
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    itemCount: _goals.length,
                    itemBuilder: (ctx, i) => _GoalCard(
                      goal: _goals[i],
                      dark: dark,
                      onDelete: () => _delete(_goals[i].id),
                      onUpdateSavings: _goals[i].type == GoalType.savings
                          ? (v) => _updateSavingsCurrent(_goals[i].id, v)
                          : null,
                    ),
                  ),
                ),
      floatingActionButton: _goals.isNotEmpty
          ? FloatingActionButton.extended(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add goal'),
              onPressed: () => _showAddGoal(context),
            )
          : null,
    );
  }

  Widget _emptyState(Color textP, Color textM, BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_outlined, color: textM, size: 56),
          const SizedBox(height: 16),
          Text('No goals yet',
              style: TextStyle(
                  color: textP, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Set a savings target, monthly limit,\nor category cap to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textM, fontSize: 13)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: kAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14)),
            icon: const Icon(Icons.add),
            label: const Text('Add first goal'),
            onPressed: () => _showAddGoal(context),
          ),
        ],
      ),
    );
  }

  Future<void> _updateSavingsCurrent(String id, double value) async {
    await _sb.from('goals').update({'current': value}).eq('id', id);
    _load();
  }

  // ── add-goal bottom sheet ──────────────────────────────────────────────────

  void _showAddGoal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddGoalSheet(
        onSaved: _load,
      ),
    );
  }
}

// ─── goal card ────────────────────────────────────────────────────────────────

class _GoalCard extends StatelessWidget {
  final Goal goal;
  final bool dark;
  final VoidCallback onDelete;
  final void Function(double)? onUpdateSavings;

  const _GoalCard({
    required this.goal,
    required this.dark,
    required this.onDelete,
    this.onUpdateSavings,
  });

  Color get _typeColor {
    return switch (goal.type) {
      GoalType.savings  => kAccent,
      GoalType.monthly  => kWarning,
      GoalType.category => kInfo,
    };
  }

  IconData get _typeIcon {
    return switch (goal.type) {
      GoalType.savings  => Icons.savings_outlined,
      GoalType.monthly  => Icons.calendar_month_outlined,
      GoalType.category => Icons.label_outline,
    };
  }

  String get _typeLabel {
    return switch (goal.type) {
      GoalType.savings  => 'Savings',
      GoalType.monthly  => 'Monthly limit',
      GoalType.category => 'Category cap',
    };
  }

  /// Look up the display name + icon for a stored category_id.
  /// Falls back to capitalising the raw id if not found (handles legacy data).
  String _categoryDisplayName(String? categoryId) {
    if (categoryId == null || categoryId.isEmpty) return '';
    try {
      final cat = kCategories.firstWhere(
        (c) => c.id.toLowerCase() == categoryId.toLowerCase(),
      );
      return cat.name;
    } catch (_) {
      // Legacy free-text stored — display as-is but title-cased
      return categoryId[0].toUpperCase() + categoryId.substring(1);
    }
  }

  IconData _categoryIcon(String? categoryId) {
    if (categoryId == null) return Icons.label_outline;
    try {
      return kCategories
          .firstWhere((c) => c.id.toLowerCase() == categoryId.toLowerCase())
          .icon;
    } catch (_) {
      return Icons.label_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = dark ? kSurface : kSurfaceLight;
    final border  = dark ? kBorder  : kBorderLight;
    final textP   = dark ? kTextPrimary   : kTextPrimaryLight;
    final textS   = dark ? kTextSecondary : kTextSecondaryLight;
    final textM   = dark ? kTextMuted     : kTextMutedLight;
    final fmt     = NumberFormat.currency(symbol: 'S\$', decimalDigits: 2);

    // For spend-limit goals: achieved = went OVER (bad), so flip colour
    final isSpendGoal = goal.type == GoalType.monthly ||
        goal.type == GoalType.category;
    final overBudget = isSpendGoal && goal.current > goal.target;
    final progressColor = isSpendGoal
        ? (overBudget ? kError : kSuccess)
        : (goal.achieved ? kSuccess : _typeColor);

    final daysLeft = goal.deadline != null
        ? goal.deadline!.difference(DateTime.now()).inDays
        : null;

    // For category goals: show category chip below the header
    final catName = goal.type == GoalType.category
        ? _categoryDisplayName(goal.category)
        : null;
    final catIcon = goal.type == GoalType.category
        ? _categoryIcon(goal.category)
        : null;

    return Dismissible(
      key: ValueKey(goal.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: kError.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_outline, color: kError),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('Delete goal?',
                style: TextStyle(color: textP)),
            content: Text('This cannot be undone.',
                style: TextStyle(color: textS)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Cancel', style: TextStyle(color: textS))),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Delete',
                      style: TextStyle(color: kError))),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: goal.achieved && !isSpendGoal
                  ? kSuccess.withOpacity(0.5)
                  : overBudget
                      ? kError.withOpacity(0.4)
                      : border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                    color: _typeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(_typeIcon, color: _typeColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goal.name,
                      style: TextStyle(
                          color: textP, fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  Text(_typeLabel,
                      style: TextStyle(color: textM, fontSize: 11)),
                ],
              )),
              // Badge
              if (goal.achieved && !isSpendGoal)
                _Badge('Achieved', kSuccess)
              else if (overBudget)
                _Badge('Over budget', kError)
              else if (daysLeft != null && daysLeft <= 7 && daysLeft >= 0)
                _Badge('$daysLeft days left', kWarning),
            ]),

            // Category pill (category-cap goals only)
            if (catName != null && catName.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(catIcon, color: kInfo, size: 13),
                const SizedBox(width: 5),
                Text(catName,
                    style: TextStyle(
                        color: kInfo,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
            ],

            const SizedBox(height: 14),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: goal.progress,
                minHeight: 8,
                backgroundColor: border,
                valueColor: AlwaysStoppedAnimation(progressColor),
              ),
            ),

            const SizedBox(height: 10),

            // Amount row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isSpendGoal
                      ? '${fmt.format(goal.current)} spent'
                      : '${fmt.format(goal.current)} saved',
                  style: TextStyle(
                      color: overBudget ? kError : textS,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
                Text(
                  'of ${fmt.format(goal.target)}',
                  style: TextStyle(color: textM, fontSize: 12),
                ),
              ],
            ),

            // Deadline row
            if (goal.deadline != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.event_outlined, color: textM, size: 13),
                const SizedBox(width: 4),
                Text(
                  'By ${DateFormat('d MMM yyyy').format(goal.deadline!)}',
                  style: TextStyle(color: textM, fontSize: 11),
                ),
              ]),
            ],

            // Update savings button
            if (goal.type == GoalType.savings && onUpdateSavings != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  label: const Text('Update saved amount',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kAccent,
                    side: const BorderSide(color: kAccent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () => _showUpdateSavings(context, textP, textM,
                      border, surface),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showUpdateSavings(BuildContext context, Color textP, Color textM,
      Color border, Color surface) {
    final ctrl =
        TextEditingController(text: goal.current.toStringAsFixed(2));
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title:
            Text('Update saved amount', style: TextStyle(color: textP)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: textP),
          decoration: InputDecoration(
            prefixText: 'S\$ ',
            prefixStyle: TextStyle(color: textM),
            hintText: '0.00',
            hintStyle: TextStyle(color: textM),
            filled: true,
            fillColor: dark ? kBg : kBgLight,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kAccent, width: 1.5)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: textM))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kAccent, foregroundColor: Colors.white),
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null) {
                onUpdateSavings!(v);
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      );
}

// ─── add goal sheet ───────────────────────────────────────────────────────────

class _AddGoalSheet extends StatefulWidget {
  final VoidCallback onSaved;
  const _AddGoalSheet({required this.onSaved});

  @override
  State<_AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends State<_AddGoalSheet> {
  final _sb = Supabase.instance.client;
  final _nameCtrl   = TextEditingController();
  final _targetCtrl = TextEditingController();

  GoalType _type       = GoalType.savings;
  String   _categoryId = kCategories.first.id; // default to first category
  DateTime? _deadline;
  bool _saving = false;
  String? _err;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name   = _nameCtrl.text.trim();
    final target = double.tryParse(_targetCtrl.text);
    if (name.isEmpty || target == null || target <= 0) {
      setState(() => _err = 'Enter a name and a target amount greater than 0');
      return;
    }
    // category type always has a valid _categoryId from the picker

    setState(() { _saving = true; _err = null; });
    final uid   = _sb.auth.currentUser?.id;
    final now   = DateTime.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    try {
      await _sb.from('goals').insert({
        'user_id':  uid,
        'name':     name,
        'type':     switch (_type) {
          GoalType.savings  => 'savings',
          GoalType.monthly  => 'monthly',
          GoalType.category => 'category',
        },
        'target':   target,
        'current':  0,
        // Store category_id (e.g. 'food') — not display name (e.g. 'Food')
        'category': _type == GoalType.category ? _categoryId : null,
        'deadline': _deadline?.toIso8601String(),
        'month':    month,
      });
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      setState(() { _saving = false; _err = 'Save failed: $e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? kSurface : kSurfaceLight;
    final border  = dark ? kBorder  : kBorderLight;
    final textP   = dark ? kTextPrimary   : kTextPrimaryLight;
    final textS   = dark ? kTextSecondary : kTextSecondaryLight;
    final textM   = dark ? kTextMuted     : kTextMutedLight;

    InputDecoration _dec(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: textM),
      filled: true,
      fillColor: dark ? kBg : kBgLight,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kAccent, width: 1.5)),
    );

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: border,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),

              Text('New goal',
                  style: TextStyle(
                      color: textP, fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),

              // Goal type chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _TypeChip(
                    label: 'Savings target',
                    icon: Icons.savings_outlined,
                    selected: _type == GoalType.savings,
                    color: kAccent,
                    onTap: () => setState(() => _type = GoalType.savings),
                  ),
                  const SizedBox(width: 8),
                  _TypeChip(
                    label: 'Monthly limit',
                    icon: Icons.calendar_month_outlined,
                    selected: _type == GoalType.monthly,
                    color: kWarning,
                    onTap: () => setState(() => _type = GoalType.monthly),
                  ),
                  const SizedBox(width: 8),
                  _TypeChip(
                    label: 'Category cap',
                    icon: Icons.label_outline,
                    selected: _type == GoalType.category,
                    color: kInfo,
                    onTap: () => setState(() => _type = GoalType.category),
                  ),
                ]),
              ),
              const SizedBox(height: 16),

              // Goal name
              Text('Goal name',
                  style: TextStyle(
                      color: textM, fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                style: TextStyle(color: textP),
                decoration: _dec(switch (_type) {
                  GoalType.savings  => 'e.g. New laptop fund',
                  GoalType.monthly  => 'e.g. Monthly budget',
                  GoalType.category => 'e.g. Eating out limit',
                }),
              ),
              const SizedBox(height: 12),

              // ── Category picker (only for category type) ─────────────────
              if (_type == GoalType.category) ...[
                Text('Category',
                    style: TextStyle(
                        color: textM, fontSize: 11,
                        fontWeight: FontWeight.w600)),
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
                              ? cat.color.withOpacity(0.18)
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
                const SizedBox(height: 12),
              ],

              // Target amount
              Text('Target amount (S\$)',
                  style: TextStyle(
                      color: textM, fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _targetCtrl,
                style: TextStyle(color: textP),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec('0.00'),
              ),
              const SizedBox(height: 12),

              // Deadline (only for savings)
              if (_type == GoalType.savings) ...[
                Text('Target date (optional)',
                    style: TextStyle(
                        color: textM, fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now()
                          .add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2030),
                      builder: (ctx, child) => Theme(
                        data: Theme.of(ctx).copyWith(
                          colorScheme: ColorScheme.dark(
                              primary: kAccent,
                              surface: surface),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setState(() => _deadline = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: dark ? kBg : kBgLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: Row(children: [
                      Icon(Icons.event_outlined,
                          color: textM, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        _deadline != null
                            ? DateFormat('d MMM yyyy').format(_deadline!)
                            : 'No deadline',
                        style: TextStyle(
                            color: _deadline != null ? textP : textM,
                            fontSize: 14),
                      ),
                      const Spacer(),
                      if (_deadline != null)
                        GestureDetector(
                          onTap: () => setState(() => _deadline = null),
                          child: Icon(Icons.close,
                              color: textM, size: 16),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (_err != null) ...[
                Text(_err!,
                    style: TextStyle(
                        color: dark ? kError : kErrorLight,
                        fontSize: 12)),
                const SizedBox(height: 8),
              ],

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Save goal',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label, required this.icon,
    required this.selected, required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark   = Theme.of(context).brightness == Brightness.dark;
    final border = dark ? kBorder : kBorderLight;
    final textP  = dark ? kTextPrimary : kTextPrimaryLight;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? color : border, width: selected ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: selected ? color : textP, size: 14),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: selected ? color : textP,
                  fontSize: 12,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    );
  }
}