
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:project/features/auth/admin_login_page.dart';
import 'package:project/features/auth/session_store.dart';

void main() {
  testWidgets('Admin login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AdminSessionStore>(
        create: (_) => AdminSessionStore(),
        child: const MaterialApp(home: AdminLoginPage()),
      ),
    );

    expect(find.text('Connectez-vous'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });
}
