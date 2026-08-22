import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Backend connection settings and a connectivity check.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _controller =
      TextEditingController(text: AppConfig.baseUrl);
  bool? _reachable;
  bool _checking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await AppConfig.setBaseUrl(_controller.text);
    if (!mounted) return;
    setState(() => _reachable = null);
    await _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final ok = await AppState.of(context).api.health();
    if (!mounted) return;
    AppState.of(context).setOnline(ok);
    setState(() {
      _reachable = ok;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        SectionCard(
          title: 'Backend connection',
          subtitle: 'REST base URL of the FastAPI quantum backend',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  helperText: 'Android emulator: http://10.0.2.2:8000 · '
                      'desktop: http://localhost:8000',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('Save & test'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _checking ? null : _check,
                    icon: const Icon(Icons.network_check),
                    label: const Text('Test connection'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_checking) const LinearProgressIndicator(),
              if (_reachable != null && !_checking)
                Row(
                  children: [
                    Icon(_reachable! ? Icons.check_circle : Icons.error,
                        color: _reachable! ? AppTheme.success : AppTheme.danger),
                    const SizedBox(width: 8),
                    Text(_reachable!
                        ? 'Backend reachable at ${AppConfig.baseUrl}'
                        : 'No response from ${AppConfig.baseUrl}'),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const SectionCard(
          title: 'About',
          subtitle: 'SIH Problem Statement 26141',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quantum Shield simulates a teleportation-based Quantum Digital '
                'Signature protocol on Qiskit Aer and detects forgery, replay, '
                'impersonation and quantum-channel manipulation using projective '
                'measurement statistics and threshold rules only — no AI/ML is '
                'involved in the detection logic.',
              ),
              SizedBox(height: 12),
              InfoRow(label: 'Frontend', value: 'Flutter (Android · iOS · Windows)'),
              InfoRow(label: 'Backend', value: 'FastAPI + Qiskit Aer + SQLite'),
            ],
          ),
        ),
      ],
    );
  }
}
