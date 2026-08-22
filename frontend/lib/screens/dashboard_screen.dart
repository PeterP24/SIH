import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Home screen: live counters plus a summary of the protocol configuration.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  MetricsSnapshot? _metrics;
  List<LogEvent> _recent = const [];
  String? _error;
  bool _loading = true;

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
    final state = AppState.of(context);
    try {
      final metrics = await state.api.metrics();
      final logs = await state.api.logs(limit: 6);
      state.setOnline(true);
      if (!mounted) return;
      setState(() {
        _metrics = metrics;
        _recent = logs;
        _loading = false;
      });
    } on ApiException catch (e) {
      state.setOnline(false);
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
          _header(context),
          const SizedBox(height: 20),
          if (_error != null) ...[
            ErrorPanel(message: _error!, onRetry: _load),
            const SizedBox(height: 20),
          ],
          if (_loading && m == null)
            const Center(child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            )),
          if (m != null) ...[
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth > 900
                  ? 4
                  : constraints.maxWidth > 600
                      ? 2
                      : 1;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.7,
                children: [
                  StatCard(
                    label: 'Signatures issued',
                    value: '${m.signatures}',
                    icon: Icons.draw,
                    color: AppTheme.accentCyan,
                  ),
                  StatCard(
                    label: 'Verifications',
                    value: '${m.verifications + m.attacks}',
                    icon: Icons.fact_check,
                    color: AppTheme.accent,
                  ),
                  StatCard(
                    label: 'Threats detected',
                    value: '${m.threatsDetected}',
                    icon: Icons.shield_moon,
                    color: AppTheme.danger,
                  ),
                  StatCard(
                    label: 'Detection accuracy',
                    value: '${(m.detectionAccuracy * 100).toStringAsFixed(1)}%',
                    icon: Icons.query_stats,
                    color: AppTheme.success,
                    caption: 'FAR ${(m.falseAcceptanceRate * 100).toStringAsFixed(1)}%'
                        ' · FRR ${(m.falseRejectionRate * 100).toStringAsFixed(1)}%',
                  ),
                ],
              );
            }),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Protocol configuration',
              subtitle: 'Teleportation-based QDS · statistical detection (no ML)',
              child: Column(
                children: [
                  InfoRow(label: 'Signature length', value: '${m.signatureLength} qubits'),
                  InfoRow(
                      label: 'Mismatch threshold',
                      value: m.threshold.toStringAsFixed(3)),
                  InfoRow(
                      label: 'Forgery probability',
                      value: m.theoreticalForgeryProbability.toStringAsExponential(3)),
                  InfoRow(label: 'Avg sign time', value: '${m.avgSignMs.toStringAsFixed(1)} ms'),
                  InfoRow(
                      label: 'Avg verify time',
                      value: '${m.avgVerifyMs.toStringAsFixed(1)} ms'),
                  InfoRow(label: 'Complexity', value: m.complexity),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SectionCard(
              title: 'Recent activity',
              trailing: TextButton(
                onPressed: () => widget.onNavigate(4),
                child: const Text('Threat log'),
              ),
              child: _recent.isEmpty
                  ? const Text('No events yet — sign a message to get started.')
                  : Column(
                      children: _recent.map(_activityTile).toList(),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _activityTile(LogEvent event) {
    final detected = event.detected ?? false;
    final color = event.eventType == 'sign'
        ? AppTheme.accentCyan
        : detected
            ? AppTheme.danger
            : AppTheme.success;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        event.eventType == 'sign'
            ? Icons.draw
            : event.eventType == 'attack'
                ? Icons.bug_report
                : Icons.fact_check,
        color: color,
      ),
      title: Text('${event.eventType.toUpperCase()} · ${event.subject ?? '-'}'),
      subtitle: Text(
        '${event.verdict ?? ''}'
        '${event.mismatchRate != null ? ' · mismatch ${event.mismatchRate!.toStringAsFixed(3)}' : ''}',
      ),
      trailing: Text(
        TimeOfDay.fromDateTime(event.createdAt).format(context),
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quantum Shield',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Quantum-inspired cyber threat detection for digital signature '
            'security — teleportation-based QDS with projective-measurement '
            'threshold analysis.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              TokenChip(text: 'Bell |Φ+⟩'),
              TokenChip(text: 'Teleportation'),
              TokenChip(text: 'Pauli X/Y/Z/I'),
              TokenChip(text: 'No-cloning'),
              TokenChip(text: 'No ML'),
            ],
          ),
        ],
      ),
    );
  }
}
