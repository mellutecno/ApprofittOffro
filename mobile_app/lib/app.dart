import 'package:flutter/material.dart';

import 'core/network/api_client.dart';
import 'core/network/session_store.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/brand_wordmark.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/landing_page.dart';
import 'features/home/home_shell.dart';

class ApprofittOffroMobileApp extends StatefulWidget {
  const ApprofittOffroMobileApp({super.key});

  @override
  State<ApprofittOffroMobileApp> createState() =>
      _ApprofittOffroMobileAppState();
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
              return LandingPage(authController: _authController);
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
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.asset(
                    'assets/branding/app_icon.png',
                    width: 112,
                    height: 112,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 18),
                const BrandWordmark(height: 52, alignment: Alignment.center),
                const SizedBox(height: 14),
                Text(
                  'Sto preparando ApprofittOffro...',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
