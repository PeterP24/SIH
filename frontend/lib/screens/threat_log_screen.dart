import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// History of signing / verification / attack events with drill-down details.
class ThreatLogScreen extends StatefulWidget {
  const ThreatLogScreen({super.key});

  @override
  State<ThreatLogScreen> createState() => _ThreatLogScreenState();
}

class _ThreatLogScreenState extends State<ThreatLogScreen> {
  static final _formatter = DateFormat('dd MMM HH:mm:ss');

  List<LogEvent> _events = const [];
  String? _filter;
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
      final events =
          await AppState.of(context).api.logs(limit: 200, eventType: _filter);
      if (!mounted) return;
      setState(() {
        _events = events;
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SectionCard(
            title: 'Threat & activity log',
            subtitle: '${_events.length} events',
            trailing: IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            child: Wrap(
              spacing: 10,
              children: [
                for (final option in [null, 'sign', 'verify', 'attack'])
                  ChoiceChip(
                    label: Text(option?.toUpperCase() ?? 'ALL'),
                    selected: _filter == option,
                    onSelected: (_) {
                      setState(() => _filter = option);
                      _load();
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null) ErrorPanel(message: _error!, onRetry: _load),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final event in _events) _tile(event),
        ],
      ),
    );
  }

  Widget _tile(LogEvent event) {
    final detected = event.detected ?? false;
    final color = event.eventType == 'sign'
        ? AppTheme.accentCyan
        : detected
            ? AppTheme.danger
            : AppTheme.success;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        shape: const Border(),
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
          '${_formatter.format(event.createdAt)} · ${event.verdict ?? ''}'
          '${event.mismatchRate != null ? ' · mismatch ${event.mismatchRate!.toStringAsFixed(3)}' : ''}',
        ),
        trailing: event.eventType == 'sign'
            ? null
            : TokenChip(
                text: detected ? 'THREAT' : 'CLEAN',
                color: detected ? AppTheme.danger : AppTheme.success,
              ),
        childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        children: [
          InfoRow(label: 'Signature id', value: event.signatureId ?? '-'),
          InfoRow(
              label: 'Mismatch rate',
              value: event.mismatchRate?.toStringAsFixed(4) ?? '-'),
          InfoRow(label: 'QBER', value: event.qber?.toStringAsFixed(4) ?? '-'),
          InfoRow(
              label: 'Elapsed', value: '${event.elapsedMs?.toStringAsFixed(1) ?? '-'} ms'),
          if (event.payload['indicators'] is List)
            for (final indicator in (event.payload['indicators'] as List))
              InfoRow(label: 'Indicator', value: '$indicator'),
          if (event.payload['verification'] is Map &&
              (event.payload['verification'] as Map)['anomalies'] is List)
            for (final anomaly
                in ((event.payload['verification'] as Map)['anomalies'] as List))
              InfoRow(label: 'Anomaly', value: '$anomaly'),
          if (event.payload['anomalies'] is List)
            for (final anomaly in (event.payload['anomalies'] as List))
              InfoRow(label: 'Anomaly', value: '$anomaly'),
        ],
      ),
    );
  }
}
