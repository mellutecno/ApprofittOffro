import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/auth/biometric_auth_service.dart';
import 'core/navigation/app_launch_target.dart';
import 'core/network/api_client.dart';
import 'core/network/session_store.dart';
import 'core/notifications/push_notifications_service.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/brand_wordmark.dart';
import 'features/auth/landing_page.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_shell.dart';

class ApprofittOffroMobileApp extends StatefulWidget {
  const ApprofittOffroMobileApp({super.key});

  @override
  State<ApprofittOffroMobileApp> createState() =>
      _ApprofittOffroMobileAppState();
}

class _ApprofittOffroMobileAppState extends State<ApprofittOffroMobileApp>
    with WidgetsBindingObserver {
  late final AuthController _authController;
  PushNotificationsService? _pushNotificationsService;
  late final Future<void> _bootstrapFuture;
  late final AppLinks _appLinks;
  StreamSubscription<Uri?>? _linkSubscription;
  AppLaunchTarget? _pendingLaunchTarget;
  bool _initialLinkResolved = false;
  bool _biometricRequired = false;
  bool _biometricAuthenticated = false;
  bool _biometricChecked = false;
  final BiometricAuthService _biometricService = BiometricAuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final apiClient = ApiClient(sessionStore: SessionStore());
    _authController = AuthController(apiClient);
    final pushNotificationsService = PushNotificationsService(
      apiClient: apiClient,
      onLaunchTargetRequested: _handlePushLaunchTarget,
    );
    _pushNotificationsService = pushNotificationsService;
    _authController.beforeLogoutHook =
        pushNotificationsService.prepareForLogout;
    _authController.addListener(_handleAuthStateChanged);
    _appLinks = AppLinks();
    _bootstrapFuture = _bootstrap();
    _listenForIncomingLinks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    _authController.removeListener(_handleAuthStateChanged);
    final pushNotificationsService = _pushNotificationsService;
    if (pushNotificationsService != null) {
      unawaited(pushNotificationsService.dispose());
    }
    _authController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_authController.handleAppLifecycleState(state));
  }

  Future<void> _bootstrap() async {
    final bootstrapStartedAt = DateTime.now();
    final pushNotificationsService = _pushNotificationsService;
    if (pushNotificationsService != null) {
      await pushNotificationsService.initialize();
    }
    await _authController.initialize();
    if (pushNotificationsService != null) {
      await pushNotificationsService
          .syncWithAuth(_authController.isAuthenticated);
    }

    _biometricChecked = true;
    if (_authController.isAuthenticated) {
      final biometricEnabled = await _biometricService.isBiometricEnabled();
      if (biometricEnabled) {
        setState(() {
          _biometricRequired = true;
        });
        final authenticated = await _biometricService.authenticate();
        if (authenticated) {
          setState(() {
            _biometricAuthenticated = true;
            _biometricRequired = false;
          });
        }
      }
    }

    await _resolveInitialLink();

    const minimumSplashDuration = Duration(milliseconds: 1600);
    final elapsed = DateTime.now().difference(bootstrapStartedAt);
    if (elapsed < minimumSplashDuration) {
      await Future.delayed(minimumSplashDuration - elapsed);
    }
  }

  void _handleAuthStateChanged() {
    final pushNotificationsService = _pushNotificationsService;
    if (pushNotificationsService == null) {
      return;
    }
    unawaited(
      pushNotificationsService.syncWithAuth(_authController.isAuthenticated),
    );
  }

  void _handlePushLaunchTarget(AppLaunchTarget target) {
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingLaunchTarget = target;
    });
  }

  Future<void> _resolveInitialLink() async {
    if (_initialLinkResolved) {
      return;
    }
    _initialLinkResolved = true;
    try {
      final initialUri = await _appLinks.getInitialLink();
      _handleIncomingUri(initialUri);
    } catch (_) {
      // Nessun deep link iniziale disponibile.
    }
  }

  void _listenForIncomingLinks() {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleIncomingUri,
      onError: (_) {
        // Deep link non leggibile: ignoro e continuo.
      },
    );
  }

  void _handleIncomingUri(Uri? uri) {
    final target = _parseLaunchTarget(uri);
    if (target == null || !mounted) {
      return;
    }
    setState(() {
      _pendingLaunchTarget = target;
    });
  }

  AppLaunchTarget? _parseLaunchTarget(Uri? uri) {
    if (uri == null || uri.scheme.toLowerCase() != 'approfittoffro') {
      return null;
    }

    final host = uri.host.toLowerCase();
    final segments =
        uri.pathSegments.map((segment) => segment.toLowerCase()).toList();
    final target = uri.queryParameters['target']?.toLowerCase();

    if (host == 'profile' && segments.contains('pending-requests')) {
      return AppLaunchTarget.pendingRequests;
    }
    if (host == 'profile' || target == 'profile') {
      return AppLaunchTarget.profile;
    }
    if (host == 'offers' || target == 'offers') {
      return AppLaunchTarget.offers;
    }
    if (host == 'pending-requests' ||
        (host == 'requests' && segments.contains('pending')) ||
        target == 'pending-requests') {
      return AppLaunchTarget.pendingRequests;
    }
    if (host == 'login' || host.isEmpty) {
      return AppLaunchTarget.login;
    }
    return AppLaunchTarget.login;
  }

  void _consumeLaunchTarget() {
    if (!mounted || _pendingLaunchTarget == null) {
      return;
    }
    setState(() {
      _pendingLaunchTarget = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ApprofittOffro',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      locale: const Locale('it', 'IT'),
      supportedLocales: const [
        Locale('it', 'IT'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: FutureBuilder<void>(
        future: _bootstrapFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _SplashScreen();
          }

          if (_biometricRequired && !_biometricAuthenticated) {
            return _BiometricLockScreen(
              onAuthenticate: () async {
                final authenticated = await _biometricService.authenticate();
                if (authenticated && mounted) {
                  setState(() {
                    _biometricAuthenticated = true;
                    _biometricRequired = false;
                  });
                }
              },
            );
          }

          return AnimatedBuilder(
            animation: _authController,
            builder: (context, _) {
              if (_authController.isAuthenticated) {
                return HomeShell(
                  authController: _authController,
                  launchTarget: _pendingLaunchTarget,
                  onLaunchTargetHandled: _consumeLaunchTarget,
                );
              }
              if (_authController.requiresReauthentication) {
                return LoginPage(authController: _authController);
              }
              return LandingPage(
                authController: _authController,
                autoOpenLogin: _pendingLaunchTarget != null,
              );
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
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 120,
                  left: 10,
                  child: _SplashOrb(
                    size: 140,
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                Positioned(
                  bottom: 130,
                  right: 12,
                  child: _SplashOrb(
                    size: 180,
                    color: AppTheme.peach.withValues(alpha: 0.24),
                  ),
                ),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: const EdgeInsets.fromLTRB(28, 30, 28, 26),
                  decoration: BoxDecoration(
                    color: AppTheme.paper.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(34),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 30,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/branding/app_icon.png',
                            width: 104,
                            height: 104,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const BrandWordmark(
                        height: 54,
                        alignment: Alignment.center,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Sto apparecchiando una versione piu bella, piu veloce e piu umana da vivere.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppTheme.brown.withValues(alpha: 0.76),
                              height: 1.5,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      const SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(strokeWidth: 3.2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashOrb extends StatelessWidget {
  const _SplashOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _BiometricLockScreen extends StatelessWidget {
  const _BiometricLockScreen({required this.onAuthenticate});

  final VoidCallback onAuthenticate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cream,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const BrandWordmark(height: 80),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.fingerprint,
                  size: 80,
                  color: AppTheme.orange,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Autenticazione richiesta',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.espresso,
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  'Usa l\'impronta digitale per accedere',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.brown,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: onAuthenticate,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Autenticati'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
