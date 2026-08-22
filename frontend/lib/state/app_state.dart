import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';

/// Minimal shared state: the API client, the most recent signature (so the
/// verify/attack screens can pre-fill it) and backend reachability.
class AppState extends ChangeNotifier {
  AppState({ApiService? api}) : api = api ?? ApiService();

  final ApiService api;

  SignatureResult? _lastSignature;
  bool _backendOnline = true;

  SignatureResult? get lastSignature => _lastSignature;
  bool get backendOnline => _backendOnline;

  set lastSignature(SignatureResult? value) {
    _lastSignature = value;
    notifyListeners();
  }

  Future<void> refreshHealth() async {
    final online = await api.health();
    if (online != _backendOnline) {
      _backendOnline = online;
      notifyListeners();
    }
  }

  void setOnline(bool value) {
    if (_backendOnline != value) {
      _backendOnline = value;
      notifyListeners();
    }
  }

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppStateScope>()!.notifier!;
}

/// Inherited holder so any screen can reach the shared [AppState].
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({super.key, required AppState state, required super.child})
      : super(notifier: state);
}
