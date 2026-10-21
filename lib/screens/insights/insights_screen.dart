import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/models/category.dart';
import 'package:tapsense/models/transaction.dart';
import 'package:tapsense/services/transaction_service.dart';
import 'package:tapsense/services/ai_service.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  List<Transaction> _txs = [];
  bool _loading = true;
  int _touchedIndex = -1;
  String _digest = '';
  bool _digestLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _loadDigest() async {
    setState(() => _digestLoading = true);
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final weekTxs = _txs.where((t) => t.createdAt.isAfter(cutoff)).toList();
    final digest = await AiService.weeklyDigest(weekTxs);
    if (mounted) setState(() { _digest = digest; _digestLoading = false; });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final txs = await TransactionService.fetchRecent(userId, limit: 100);
    if (mounted) setState(() { _txs = txs; _loading = false; });
    await _loadDigest();
  }

  double get _weekSpend {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return _txs
        .where((t) => t.createdAt.isAfter(cutoff) && t.amount < 0)
        .fold(0.0, (s, t) => s + t.amount.abs());
  }

  Map<String, double> get _byCategory {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final map = <String, double>{};
    for (final t in _txs.where(
        (t) => t.createdAt.isAfter(cutoff) && t.amount < 0)) {
      map[t.categoryId] = (map[t.categoryId] ?? 0) + t.amount.abs();
    }
    return Map.fromEntries(
        map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }

  List<double> get _dailySpend {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 6 - i));
      return _txs
          .where((t) =>
              t.amount < 0 &&
              t.createdAt.year == day.year &&
              t.createdAt.month == day.month &&
              t.createdAt.day == day.day)
          .fold(0.0, (s, t) => s + t.amount.abs());
    });
  }

  List<String> get _dayLabels {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 6 - i));
      return DateFormat('E').format(day);
    });
  }

  @override
  Widget build(BuildContext context) {
    // ── Theme-aware colours (fixes dark-mode-only rendering) ──────────────────
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
        title: Text('Insights', style: TextStyle(color: textP)),
        leading: BackButton(
            color: textP,
            onPressed: () => Navigator.pop(context)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: kAccent))
          : RefreshIndicator(
              color: kAccent,
              backgroundColor: surface,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [

                  // ── Week total ──────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        kAccent.withOpacity(0.2),
                        kAccent.withOpacity(0.04),
                      ]),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kAccent.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('This week',
                            style: TextStyle(
                                color: textS, fontSize: 13)),
                        const SizedBox(height: 6),
                        Text('S\$ ${_weekSpend.toStringAsFixed(2)}',
                            style: TextStyle(
                                color: textP,
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1)),
                        const SizedBox(height: 4),
                        Text('${_txs.length} transactions logged',
                            style: TextStyle(
                                color: textM, fontSize: 12)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Bar chart ───────────────────────────────────
                  Text('Daily spend',
                      style: TextStyle(
                          color: textP,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),

                  Container(
                    height: 180,
                    padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: border),
                    ),
                    child: _dailySpend.every((v) => v == 0)
                        ? Center(
                            child: Text('No data yet',
                                style: TextStyle(color: textM)))
                        : BarChart(
                            BarChartData(
                              maxY: (_dailySpend.reduce(
                                          (a, b) => a > b ? a : b) *
                                      1.3)
                                  .clamp(10, double.infinity),
                              barTouchData: BarTouchData(
                                touchTooltipData: BarTouchTooltipData(
                                  getTooltipColor: (_) => surface,
                                  getTooltipItem: (g, gi, rod, ri) =>
                                      BarTooltipItem(
                                          'S\$ ${rod.toY.toStringAsFixed(2)}',
                                          TextStyle(
                                              color: kAccent,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12)),
                                ),
                              ),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (v, _) => Padding(
                                      padding:
                                          const EdgeInsets.only(top: 4),
                                      child: Text(
                                          _dayLabels[v.toInt()],
                                          style: TextStyle(
                                              color: textM,
                                              fontSize: 10)),
                                    ),
                                  ),
                                ),
                                leftTitles: const AxisTitles(
                                    sideTitles:
                                        SideTitles(showTitles: false)),
                                topTitles: const AxisTitles(
                                    sideTitles:
                                        SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(
                                    sideTitles:
                                        SideTitles(showTitles: false)),
                              ),
                              gridData: FlGridData(
                                drawVerticalLine: false,
                                getDrawingHorizontalLine: (_) => FlLine(
                                    color: border, strokeWidth: 1),
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups: List.generate(
                                  7,
                                  (i) => BarChartGroupData(x: i, barRods: [
                                        BarChartRodData(
                                          toY: _dailySpend[i],
                                          color: kAccent,
                                          width: 18,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          backDrawRodData:
                                              BackgroundBarChartRodData(
                                            show: true,
                                            toY: (_dailySpend.reduce(
                                                        (a, b) =>
                                                            a > b ? a : b) *
                                                    1.3)
                                                .clamp(10, double.infinity),
                                            color:
                                                kAccent.withOpacity(0.06),
                                          ),
                                        ),
                                      ])),
                            ),
                          ),
                  ),

                  const SizedBox(height: 28),

                  // ── AI digest card ──────────────────────────────
                  Text('Weekly digest',
                      style: TextStyle(
                          color: textP,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),

                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: kAccent.withOpacity(0.3)),
                    ),
                    child: _digestLoading
                        ? Row(children: [
                            const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: kAccent)),
                            const SizedBox(width: 12),
                            Text('Generating summary...',
                                style: TextStyle(
                                    color: textS, fontSize: 13)),
                          ])
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.auto_awesome,
                                    color: kAccent, size: 16),
                                const SizedBox(width: 6),
                                const Text('AI Summary',
                                    style: TextStyle(
                                        color: kAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                const Spacer(),
                                GestureDetector(
                                  onTap: _loadDigest,
                                  child: Icon(Icons.refresh,
                                      color: textM, size: 16),
                                ),
                              ]),
                              const SizedBox(height: 10),
                              Text(
                                _digest.isEmpty
                                    ? 'Tap refresh to generate your weekly summary.'
                                    : _digest,
                                style: TextStyle(
                                    color: textS,
                                    fontSize: 13,
                                    height: 1.5),
                              ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 28),

                  // ── Category breakdown ──────────────────────────
                  Text('By category',
                      style: TextStyle(
                          color: textP,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),

                  if (_byCategory.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: border),
                      ),
                      child: Center(
                          child: Text('No spend data yet',
                              style: TextStyle(color: textM))),
                    )
                  else ...[
                    SizedBox(
                      height: 200,
                      child: PieChart(PieChartData(
                        sectionsSpace: 3,
                        centerSpaceRadius: 48,
                        pieTouchData: PieTouchData(
                          touchCallback: (e, r) => setState(() =>
                              _touchedIndex = r?.touchedSection
                                      ?.touchedSectionIndex ??
                                  -1),
                        ),
                        sections: _byCategory.entries
                            .toList()
                            .asMap()
                            .entries
                            .map((entry) {
                          final i   = entry.key;
                          final cat = categoryById(entry.value.key);
                          final pct = _weekSpend > 0
                              ? entry.value.value / _weekSpend * 100
                              : 0.0;
                          final isTouched = i == _touchedIndex;
                          return PieChartSectionData(
                            value: entry.value.value,
                            color: cat.color,
                            radius: isTouched ? 60 : 50,
                            title: '${pct.toStringAsFixed(0)}%',
                            titleStyle: TextStyle(
                              color: Colors.white,
                              fontSize: isTouched ? 13 : 11,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        }).toList(),
                      )),
                    ),
                    const SizedBox(height: 14),

                    ..._byCategory.entries.map((e) {
                      final cat = categoryById(e.key);
                      final pct = _weekSpend > 0
                          ? e.value / _weekSpend * 100
                          : 0.0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: border),
                        ),
                        child: Row(children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: cat.color,
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Icon(cat.icon, color: cat.color, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(cat.name,
                                  style: TextStyle(
                                      color: textP,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500))),
                          Text('${pct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                  color: textS, fontSize: 12)),
                          const SizedBox(width: 12),
                          Text('S\$ ${e.value.toStringAsFixed(2)}',
                              style: TextStyle(
                                  color: textP,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ]),
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }
}