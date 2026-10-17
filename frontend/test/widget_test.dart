import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sissansissan/main.dart';
import 'package:sissansissan/core/api_client.dart';

void main() {
  testWidgets(
    'without a stored session the login form is shown and validated',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = ApiClient(await SharedPreferences.getInstance());

      await tester.pumpWidget(SissansissanApp(api: api));
      expect(find.text('Se connecter'), findsOneWidget);

      await tester.tap(find.text('Se connecter'));
      await tester.pump();
      expect(find.text('E-mail invalide'), findsOneWidget);
      expect(find.text('Mot de passe requis'), findsOneWidget);
    },
  );
}
