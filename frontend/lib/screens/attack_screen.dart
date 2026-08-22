import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Attack simulator: mount forgery / replay / impersonation / channel attacks
/// against a signature and see whether the detector catches them.
class AttackScreen extends StatefulWidget {
  const AttackScreen({super.key});

  @override
  State<AttackScreen> createState() => _AttackScreenState();
}

class _AttackScreenState extends State<AttackScreen> {
  final _signatureController = TextEditingController();
  final _tamperController = TextEditingController();
  List<AttackType> _types = const [];
  String _selected = 'forgery';
  double _channelError = 0.25;
  AttackResult? _result;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTypes());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final last = AppState.of(context).lastSignature;
    if (_signatureController.text.isEmpty && last != null) {
      _signatureController.text = last.signatureId;
    }
  }

  @override
  void dispose() {
    _signatureController.dispose();
    _tamperController.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final types = await AppState.of(context).api.attackTypes();
      if (!mounted) return;
      setState(() => _types = types);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final state = AppState.of(context);
    try {
      final result = await state.api.simulateAttack(
        _selected,
        signatureId: _signatureController.text.trim().isEmpty
            ? null
            : _signatureController.text.trim(),
        tamperedMessage: _tamperController.text.trim(),
        channelErrorRate: _channelError,
      );
      state.setOnline(true);
      if (!mounted) return;
      setState(() {
        _result = result;
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
    final result = _result;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionCard(
          title: 'Attack simulator',
          subtitle: 'Adversarial runs against a stored signature',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final type in _types)
                    ChoiceChip(
                      label: Text(_label(type.name)),
                      selected: _selected == type.name,
                      onSelected: (_) => setState(() => _selected = type.name),
                      selectedColor: AppTheme.accent.withValues(alpha: 0.4),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (_types.any((t) => t.name == _selected))
                Text(
                  _types.firstWhere((t) => t.name == _selected).description,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _signatureController,
                decoration: const InputDecoration(
                  labelText: 'Target signature id',
                  helperText: 'Leave empty to attack the most recent signature',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _tamperController,
                decoration: const InputDecoration(
                  labelText: 'Tampered message (optional)',
                  helperText: 'Used by replay / forgery to present different content',
                ),
              ),
              const SizedBox(height: 14),
              Text('Channel error rate: ${_channelError.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white70)),
              Slider(
                value: _channelError,
                onChanged: (v) => setState(() => _channelError = v),
                divisions: 20,
                label: _channelError.toStringAsFixed(2),
              ),
              const SizedBox(height: 6),
              FilledButton.icon(
                onPressed: _loading ? null : _run,
                icon: _loading
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.security),
                label: Text(_loading ? 'Running attack…' : 'Launch attack'),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          ErrorPanel(message: _error!, onRetry: _run),
        ],
        if (result != null) ...[
          const SizedBox(height: 18),
          VerdictBanner(
            positive: result.detected == result.expectedDetection,
            title: result.detected ? 'THREAT DETECTED' : 'NO THREAT DETECTED',
            detail: result.verification.reason,
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: '${_label(result.attackType)} · ${result.attacker}',
            subtitle: result.description,
            child: Column(
              children: [
                InfoRow(label: 'Attack id', value: result.attackId),
                InfoRow(label: 'Target signature', value: result.targetSignatureId),
                InfoRow(label: 'Presented message', value: result.presentedMessage),
                InfoRow(
                    label: 'Mismatch rate',
                    value: result.verification.mismatchRate.toStringAsFixed(4)),
                InfoRow(
                    label: 'Threshold τ',
                    value: result.verification.threshold.toStringAsFixed(3)),
                InfoRow(label: 'QBER', value: result.verification.qber.toStringAsFixed(4)),
                InfoRow(
                    label: 'Elapsed', value: '${result.elapsedMs.toStringAsFixed(1)} ms'),
                const SizedBox(height: 12),
                for (final indicator in result.indicators)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.radar, size: 18, color: AppTheme.accentCyan),
                        const SizedBox(width: 8),
                        Expanded(child: Text(indicator)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _label(String name) => name
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
