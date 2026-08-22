import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quantum_shield_app/main.dart';
import 'package:quantum_shield_app/state/app_state.dart';
import 'package:quantum_shield_app/theme/app_theme.dart';

void main() {
  testWidgets('home shell renders navigation destinations', (tester) async {
    await tester.pumpWidget(
      AppStateScope(
        state: AppState(),
        child: MaterialApp(theme: AppTheme.dark, home: const HomeShell()),
      ),
    );
    await tester.pump();

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Sign'), findsWidgets);
    expect(find.text('Attacks'), findsWidgets);
  });
}
