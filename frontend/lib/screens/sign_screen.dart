import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Sign a message and walk through the teleportation steps that produced the
/// quantum signature.
class SignScreen extends StatefulWidget {
  const SignScreen({super.key});

  @override
  State<SignScreen> createState() => _SignScreenState();
}

class _SignScreenState extends State<SignScreen> {
  final _messageController =
      TextEditingController(text: 'Transfer 25,000 INR to account 9042118');
  final _signerController = TextEditingController(text: 'Alice');
  SignatureResult? _result;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _messageController.dispose();
    _signerController.dispose();
    super.dispose();
  }

  Future<void> _sign() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final state = AppState.of(context);
    try {
      final result =
          await state.api.sign(message, signer: _signerController.text.trim());
      state.lastSignature = result;
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
          title: 'Sign a message',
          subtitle:
              'The SHA-256 digest is encoded into Pauli eigenstates and teleported '
              'to the verifier through Bell pairs.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _messageController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  hintText: 'Enter the document or transaction to sign',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _signerController,
                decoration: const InputDecoration(labelText: 'Signer identity'),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _loading ? null : _sign,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bolt),
                label: Text(_loading ? 'Teleporting qubits…' : 'Generate quantum signature'),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          ErrorPanel(message: _error!, onRetry: _sign),
        ],
        if (result != null) ...[
          const SizedBox(height: 18),
          SectionCard(
            title: 'Signature issued',
            subtitle: result.signatureId,
            child: Column(
              children: [
                InfoRow(label: 'Key id', value: result.keyId),
                InfoRow(label: 'SHA-256', value: result.messageHash),
                InfoRow(label: 'Signature qubits', value: '${result.length}'),
                InfoRow(label: 'Key QBER', value: result.keyQber.toStringAsFixed(3)),
                InfoRow(
                    label: 'Elapsed', value: '${result.elapsedMs.toStringAsFixed(1)} ms'),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < result.bases.length; i++)
                        TokenChip(
                          text: '${result.bases[i]}·${result.corrections[i]}',
                          color: _basisColor(result.bases[i]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: 'Quantum signing process',
            subtitle: 'Step-by-step teleportation of the first digest qubits',
            child: Column(
              children: [
                for (final step in result.steps) _stepTile(step),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepTile(SignatureStep step) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.accent.withValues(alpha: 0.25),
                child: Text('${step.index + 1}',
                    style: const TextStyle(fontSize: 12, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              TokenChip(text: 'bit ${step.digestBit}'),
              const SizedBox(width: 8),
              TokenChip(
                  text: '${step.basis} → ${step.preparedState}',
                  color: _basisColor(step.basis)),
              const SizedBox(width: 8),
              TokenChip(text: 'Bell ${step.bellMeasurement}', color: AppTheme.warning),
              const SizedBox(width: 8),
              TokenChip(text: step.pauliCorrection, color: AppTheme.success),
            ],
          ),
          const SizedBox(height: 10),
          Text(step.description,
              style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
        ],
      ),
    );
  }

  Color _basisColor(String basis) => switch (basis) {
        'X' => AppTheme.accentCyan,
        'Y' => AppTheme.warning,
        _ => AppTheme.accent,
      };
}
