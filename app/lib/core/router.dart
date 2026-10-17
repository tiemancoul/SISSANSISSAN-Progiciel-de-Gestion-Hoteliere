import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/billing/cash_screen.dart';
import '../features/billing/invoice_screen.dart';
import '../features/billing/invoices_screen.dart';
import '../features/reservations/calendar_screen.dart';
import '../features/reservations/guests_screen.dart';
import '../features/reservations/reservations_screen.dart';
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
    initialLocation: '/reservations',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = ref.read(supabaseProvider).auth.currentSession != null;
      final atLogin = state.matchedLocation == '/connexion';
      if (!loggedIn) return atLogin ? null : '/connexion';
      if (atLogin) return '/reservations';
      return null;
    },
    routes: [
      GoRoute(path: '/connexion', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (_, state, child) =>
            HomeShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/reservations',
            builder: (_, _) => const ReservationsScreen(),
          ),
          GoRoute(
            path: '/calendrier',
            builder: (_, _) => const CalendarScreen(),
          ),
          GoRoute(path: '/clients', builder: (_, _) => const GuestsScreen()),
          GoRoute(
            path: '/factures',
            builder: (_, _) => const InvoicesScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    InvoiceScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/caisse', builder: (_, _) => const CashScreen()),
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
