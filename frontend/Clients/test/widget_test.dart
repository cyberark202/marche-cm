import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:clients_app/main.dart';
import 'package:clients_app/features/auth/session_store.dart';

void main() {
  testWidgets('Clients app boots', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SessionStore(),
        child: const ClientsApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
  });
}
