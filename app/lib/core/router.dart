import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/rooms/rooms_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/home_shell.dart';
import '../features/users/users_screen.dart';
import 'supabase.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Relance la redirection quand la session ou le profil change.
  final refresh = ValueNotifier(0);
  ref
    ..listen(authStateProvider, (_, _) => refresh.value++)
    ..listen(profileProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/chambres',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(supabaseProvider).auth.currentSession != null;
      final atLogin = state.matchedLocation == '/connexion';
      if (!loggedIn) return atLogin ? null : '/connexion';
      if (atLogin) return '/chambres';
      return null;
    },
    routes: [
      GoRoute(path: '/connexion', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (_, state, child) =>
            HomeShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/chambres', builder: (_, _) => const RoomsScreen()),
          GoRoute(
            path: '/utilisateurs',
            builder: (_, _) => const UsersScreen(),
          ),
          GoRoute(
            path: '/parametres',
            builder: (_, _) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
