import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api_client.dart';
import 'features/auth/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    SissansissanApp(api: ApiClient(await SharedPreferences.getInstance())),
  );
}

class SissansissanApp extends StatelessWidget {
  const SissansissanApp({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SISSANSISSAN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0B5D4B)),
      home: AuthGate(api: api),
    );
  }
}

/// Shows the login screen or the home screen depending on the stored session.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.api});

  final ApiClient api;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Map<String, dynamic>? _user;
  late bool _checking = widget.api.hasToken;

  @override
  void initState() {
    super.initState();
    if (_checking) _restoreSession();
  }

  Future<void> _restoreSession() async {
    Map<String, dynamic>? user;
    try {
      user = await widget.api.me();
    } on Exception {
      user = null; // Expired or revoked token: fall back to the login screen.
    }
    if (mounted) {
      setState(() {
        _user = user;
        _checking = false;
      });
    }
  }

  Future<void> _logout() async {
    try {
      await widget.api.logout();
    } on Exception {
      // The token is cleared locally even when the server is unreachable.
    }
    if (mounted) setState(() => _user = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = _user;
    if (user == null) {
      return LoginScreen(
        api: widget.api,
        onLoggedIn: (u) => setState(() => _user = u),
      );
    }
    return HomeScreen(user: user, onLogout: _logout);
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.user, required this.onLogout});

  static const _roles = {
    'super_admin': 'Super administrateur',
    'hotel_admin': 'Administrateur hôtelier',
    'receptionist': 'Réceptionniste',
  };

  final Map<String, dynamic> user;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final hotel =
        (user['hotel'] as Map<String, dynamic>?)?['name'] as String? ??
        'Plateforme SaaS';
    return Scaffold(
      appBar: AppBar(
        title: Text(hotel),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: onLogout,
          ),
        ],
      ),
      body: Center(
        child: Text(
          'Bienvenue ${user['name']} (${_roles[user['role']] ?? user['role']})',
        ),
      ),
    );
  }
}
