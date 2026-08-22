import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Verify a signature: shows the per-qubit projective measurement outcomes and
/// the threshold decision.
class VerifyScreen extends StatefulWidget {
  const VerifyScreen({super.key});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _signatureController = TextEditingController();
  final _messageController = TextEditingController();
  final _verifierController = TextEditingController(text: 'Bob');
  VerificationResult? _result;
  bool _loading = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final last = AppState.of(context).lastSignature;
    if (_signatureController.text.isEmpty && last != null) {
      _signatureController.text = last.signatureId;
      _messageController.text = last.message;
    }
  }

  @override
  void dispose() {
    _signatureController.dispose();
    _messageController.dispose();
    _verifierController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final id = _signatureController.text.trim();
    if (id.isEmpty) {
      setState(() => _error = 'Enter a signature id (sign a message first).');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final state = AppState.of(context);
    try {
      final result = await state.api.verify(
        id,
        message: _messageController.text.trim().isEmpty
            ? null
            : _messageController.text.trim(),
        verifier: _verifierController.text.trim(),
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
          title: 'Verify a signature',
          subtitle:
              'The verifier re-applies the Pauli corrections and measures each '
              'qubit in its key-derived basis.',
          child: Column(
            children: [
              TextField(
                controller: _signatureController,
                decoration: const InputDecoration(labelText: 'Signature id'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _messageController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Message presented for verification',
                  helperText: 'Change it to see the tamper/replay detection fire',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _verifierController,
                decoration: const InputDecoration(labelText: 'Verifier identity'),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _loading ? null : _verify,
                icon: _loading
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.travel_explore),
                label: Text(_loading ? 'Measuring qubits…' : 'Run projective measurement'),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          ErrorPanel(message: _error!, onRetry: _verify),
        ],
        if (result != null) ...[
          const SizedBox(height: 18),
          VerdictBanner(
            positive: result.accepted,
            title: result.accepted ? 'SIGNATURE ACCEPTED' : 'SIGNATURE REJECTED',
            detail: result.reason,
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: 'Measurement statistics',
            child: Column(
              children: [
                InfoRow(
                    label: 'Mismatch rate',
                    value: result.mismatchRate.toStringAsFixed(4)),
                InfoRow(label: 'Threshold τ', value: result.threshold.toStringAsFixed(3)),
                InfoRow(label: 'Channel QBER', value: result.qber.toStringAsFixed(4)),
                InfoRow(
                    label: 'Forgery probability',
                    value: result.forgeryProbability.toStringAsExponential(3)),
                InfoRow(
                    label: 'Elapsed', value: '${result.elapsedMs.toStringAsFixed(1)} ms'),
                const SizedBox(height: 12),
                _mismatchBar(result),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: 'Per-qubit projective measurements',
            subtitle: 'basis · expected → measured (red = mismatch)',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < result.measuredBits.length; i++)
                  TokenChip(
                    text: '${result.bases[i]} ${result.expectedBits[i]}→${result.measuredBits[i]}',
                    color: result.expectedBits[i] == result.measuredBits[i]
                        ? AppTheme.success
                        : AppTheme.danger,
                  ),
              ],
            ),
          ),
          if (result.anomalies.isNotEmpty) ...[
            const SizedBox(height: 18),
            SectionCard(
              title: 'Anomalies',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final anomaly in result.anomalies)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber,
                              size: 18, color: AppTheme.warning),
                          const SizedBox(width: 8),
                          Expanded(child: Text(anomaly)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _mismatchBar(VerificationResult result) {
    final ratio = (result.mismatchRate).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 14,
            backgroundColor: AppTheme.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(
                result.accepted ? AppTheme.success : AppTheme.danger),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'threshold τ = ${result.threshold.toStringAsFixed(2)} · '
          'key-less attacker expectation ≈ 0.333',
          style: const TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ],
    );
  }
}
