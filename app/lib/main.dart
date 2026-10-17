import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/router.dart';

// Clé publique uniquement : la clé service_role ne doit jamais être dans l'application.
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isEmpty || _supabaseKey.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Configuration manquante : lancer avec '
              '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...',
            ),
          ),
        ),
      ),
    );
    return;
  }
  await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
  runApp(const ProviderScope(child: SissanApp()));
}

class SissanApp extends ConsumerWidget {
  const SissanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'SISSAN SISSAN | Gestion hôtelière',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF8B5E34)),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
