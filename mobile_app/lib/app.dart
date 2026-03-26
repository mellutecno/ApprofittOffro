import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_shell.dart';
import 'package:flutter/material.dart';

import 'core/network/api_client.dart';
import 'core/network/session_store.dart';
import 'core/theme/app_theme.dart';

class ApprofittOffroMobileApp extends StatefulWidget {
  const ApprofittOffroMobileApp({super.key});

  @override
  State<ApprofittOffroMobileApp> createState() => _ApprofittOffroMobileAppState();
}

class _ApprofittOffroMobileAppState extends State<ApprofittOffroMobileApp> {
  late final AuthController _authController;
  late final Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    final apiClient = ApiClient(sessionStore: SessionStore());
    _authController = AuthController(apiClient);
    _bootstrapFuture = _authController.initialize();
  }

  @override
  void dispose() {
    _authController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ApprofittOffro',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      home: FutureBuilder<void>(
        future: _bootstrapFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _SplashScreen();
          }

          return AnimatedBuilder(
            animation: _authController,
            builder: (context, _) {
              if (_authController.isAuthenticated) {
                return HomeShell(authController: _authController);
              }
              return LoginPage(authController: _authController);
            },
          );
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Sto preparando ApprofittOffro...'),
          ],
        ),
      ),
    );
  }
}
