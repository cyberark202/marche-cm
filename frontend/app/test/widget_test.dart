// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:marche_cm/main.dart';
import 'package:marche_cm/features/auth/session_store.dart';

void main() {
  testWidgets('App boots admin dashboard', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) {
          final session = SessionStore();
          session.setSession(
            accessToken: "test-token",
            userRole: UserRole.generalAdmin,
            currentUserId: 1,
            currentUsername: "admin",
          );
          return session;
        },
        child: const MarcheCmApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text('Supervision Admin'), findsOneWidget);
  });
}
