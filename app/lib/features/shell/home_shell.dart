import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/roles.dart';
import '../../core/supabase.dart';

class _Destination {
  const _Destination(this.path, this.label, this.icon, this.visible);
  final String path;
  final String label;
  final IconData icon;
  final bool Function(AppRole) visible;
}

final _destinations = [
  _Destination(
    '/reservations',
    'Réservations',
    Icons.event_outlined,
    (_) => true,
  ),
  _Destination(
    '/clients',
    'Clients',
    Icons.person_outline,
    (r) => r.canManageGuests,
  ),
  _Destination('/chambres', 'Chambres', Icons.bed_outlined, (_) => true),
  _Destination(
    '/utilisateurs',
    'Utilisateurs',
    Icons.people_outline,
    (r) => r.canManageUsers,
  ),
  _Destination(
    '/parametres',
    'Paramètres',
    Icons.settings_outlined,
    (_) => true,
  ),
];

/// Cadre de l'application : navigation selon le rôle et la largeur d'écran.
class HomeShell extends ConsumerWidget {
  const HomeShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    return profile.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => _Message(text: errorText(e)),
      data: (p) {
        if (p == null || !p.hasAccess) {
          return const _Message(
            text:
                'Votre compte est créé mais aucun rôle ne vous a encore été '
                'attribué. Contactez l\'administrateur de l\'hôtel.',
          );
        }
        final items = _destinations.where((d) => d.visible(p.role!)).toList();
        final index = items
            .indexWhere((d) => location.startsWith(d.path))
            .clamp(0, items.length - 1);
        void go(int i) => context.go(items[i].path);
        final wide = MediaQuery.sizeOf(context).width >= 840;
        final logout = IconButton(
          tooltip: 'Se déconnecter',
          icon: const Icon(Icons.logout),
          onPressed: () => ref.read(supabaseProvider).auth.signOut(),
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(items[index].label),
            actions: [
              Center(child: Text('${p.fullName ?? ''} · ${p.role!.label}')),
              logout,
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: index,
                      onDestinationSelected: go,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final d in items)
                          NavigationRailDestination(
                            icon: Icon(d.icon),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: child),
                  ],
                )
              : child,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: go,
                  destinations: [
                    for (final d in items)
                      NavigationDestination(icon: Icon(d.icon), label: d.label),
                  ],
                ),
        );
      },
    );
  }
}

class _Message extends ConsumerWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => ref.read(supabaseProvider).auth.signOut(),
              child: const Text('Se déconnecter'),
            ),
          ],
        ),
      ),
    ),
  );
}
