import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Charts over the simulated runs: mismatch-rate trend, per-attack detection
/// rates and forgery probability vs. signature length.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  MetricsSnapshot? _metrics;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final metrics = await AppState.of(context).api.metrics();
      if (!mounted) return;
      setState(() {
        _metrics = metrics;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _metrics;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null) ErrorPanel(message: _error!, onRetry: _load),
          if (_loading && m == null)
            const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator())),
          if (m != null) ...[
            SectionCard(
              title: 'Mismatch rate per run',
              subtitle:
                  'Honest runs sit near 0; key-less attackers cluster around 1/3, '
                  'replays near 1/2. The dashed line is the decision threshold τ.',
              trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
              child: SizedBox(height: 240, child: _mismatchChart(m)),
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Detection rate by attack type',
              child: SizedBox(height: 240, child: _attackChart(m)),
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Forgery probability vs. signature length',
              subtitle: 'Binomial tail P = Σ_{k≤τn} C(n,k)(1/3)^k(2/3)^{n-k}',
              child: SizedBox(height: 240, child: _forgeryChart(m)),
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Performance & security summary',
              child: Column(
                children: [
                  InfoRow(
                      label: 'Detection accuracy',
                      value: '${(m.detectionAccuracy * 100).toStringAsFixed(2)} %'),
                  InfoRow(
                      label: 'Detection rate',
                      value: '${(m.detectionRate * 100).toStringAsFixed(2)} %'),
                  InfoRow(
                      label: 'False acceptance rate',
                      value: '${(m.falseAcceptanceRate * 100).toStringAsFixed(2)} %'),
                  InfoRow(
                      label: 'False rejection rate',
                      value: '${(m.falseRejectionRate * 100).toStringAsFixed(2)} %'),
                  InfoRow(
                      label: 'Theoretical P(forgery)',
                      value: m.theoreticalForgeryProbability.toStringAsExponential(3)),
                  InfoRow(
                      label: 'Avg sign / verify',
                      value:
                          '${m.avgSignMs.toStringAsFixed(1)} ms / ${m.avgVerifyMs.toStringAsFixed(1)} ms'),
                  InfoRow(label: 'Complexity', value: m.complexity),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mismatchChart(MetricsSnapshot m) {
    if (m.mismatchSeries.isEmpty) {
      return const Center(child: Text('No verification runs yet.'));
    }
    final spots = <FlSpot>[
      for (var i = 0; i < m.mismatchSeries.length; i++)
        FlSpot(i.toDouble(), m.mismatchSeries[i].value),
    ];
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 0.8,
        gridData: FlGridData(show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Colors.white12, strokeWidth: 1)),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(),
          rightTitles: AxisTitles(),
          leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 38, interval: 0.2)),
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 24, interval: 5)),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(
            y: m.threshold,
            color: AppTheme.warning,
            strokeWidth: 2,
            dashArray: [6, 4],
            label: HorizontalLineLabel(
                show: true,
                labelResolver: (_) => 'τ = ${m.threshold}',
                style: const TextStyle(color: AppTheme.warning, fontSize: 11)),
          ),
        ]),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: AppTheme.accentCyan,
            barWidth: 2,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
                radius: 3.5,
                color: spot.y > m.threshold ? AppTheme.danger : AppTheme.success,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
                show: true, color: AppTheme.accentCyan.withValues(alpha: 0.12)),
          ),
        ],
      ),
    );
  }

  Widget _attackChart(MetricsSnapshot m) {
    if (m.perAttack.isEmpty) {
      return const Center(child: Text('Run an attack simulation to populate this chart.'));
    }
    final entries = m.perAttack.entries.toList();
    return BarChart(
      BarChartData(
        maxY: 1.05,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 34, interval: 0.25)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= entries.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    entries[index].key.replaceAll('_', '\n'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < entries.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: entries[i].value.detectionRate,
                width: 16,
                borderRadius: BorderRadius.circular(4),
                color: entries[i].key == 'baseline' ? AppTheme.success : AppTheme.accent,
              ),
              BarChartRodData(
                toY: entries[i].value.meanMismatchRate,
                width: 16,
                borderRadius: BorderRadius.circular(4),
                color: AppTheme.accentCyan,
              ),
            ]),
        ],
      ),
    );
  }

  Widget _forgeryChart(MetricsSnapshot m) {
    // Recomputed client-side so the curve renders even before any run.
    final spots = <FlSpot>[];
    for (var n = 4; n <= 64; n += 4) {
      spots.add(FlSpot(n.toDouble(), _forgeryProbability(n, m.threshold)));
    }
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 1,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(),
          rightTitles: AxisTitles(),
          leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 38, interval: 0.25)),
          bottomTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 24, interval: 16)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppTheme.danger,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData:
                BarAreaData(show: true, color: AppTheme.danger.withValues(alpha: 0.12)),
          ),
        ],
      ),
    );
  }

  /// Binomial lower tail with p = 1/3 (same formula as the backend).
  double _forgeryProbability(int n, double threshold) {
    const p = 1 / 3;
    final kMax = (threshold * n).floor();
    var total = 0.0;
    for (var k = 0; k <= kMax; k++) {
      total += _binomial(n, k) * _pow(p, k) * _pow(1 - p, n - k);
    }
    return total.clamp(0.0, 1.0);
  }

  double _binomial(int n, int k) {
    var result = 1.0;
    for (var i = 1; i <= k; i++) {
      result = result * (n - k + i) / i;
    }
    return result;
  }

  double _pow(double base, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }
}
