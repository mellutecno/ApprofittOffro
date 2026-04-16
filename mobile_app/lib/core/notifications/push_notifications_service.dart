import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../config/app_config.dart';
import '../navigation/app_launch_target.dart';
import '../network/api_client.dart';

class PushNotificationsService {
  PushNotificationsService({
    required ApiClient apiClient,
    required void Function(AppLaunchTarget target) onLaunchTargetRequested,
  })  : _apiClient = apiClient,
        _onLaunchTargetRequested = onLaunchTargetRequested;

  final ApiClient _apiClient;
  final void Function(AppLaunchTarget target) _onLaunchTargetRequested;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  FirebaseMessaging? _messaging;
  int _localNotificationId = 0;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  bool _initialized = false;
  bool _firebaseAvailable = false;
  bool _authenticated = false;
  bool _syncingRegistration = false;
  bool _syncRegistrationQueued = false;
  String? _currentToken;
  String? _registeredToken;

  bool get isAvailable => _firebaseAvailable;

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'approfittoffro_alerts',
    'ApprofittOffro alerts',
    description: 'Notifiche eventi, richieste, recensioni e follower.',
    importance: Importance.high,
  );

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    if (!Platform.isAndroid) {
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        if (AppConfig.firebaseMessagingConfigured) {
          await Firebase.initializeApp(
            options: FirebaseOptions(
              apiKey: AppConfig.firebaseApiKey,
              appId: AppConfig.firebaseAppId,
              messagingSenderId: AppConfig.firebaseMessagingSenderId,
              projectId: AppConfig.firebaseProjectId,
              storageBucket: AppConfig.firebaseStorageBucket.isEmpty
                  ? null
                  : AppConfig.firebaseStorageBucket,
            ),
          );
        } else {
          await Firebase.initializeApp();
        }
      }
      _firebaseAvailable = Firebase.apps.isNotEmpty;
      if (!_firebaseAvailable) {
        return;
      }
      await _initializeLocalNotifications();
      _messaging = FirebaseMessaging.instance;
      _messageOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleNotificationTap,
      );
      _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
        _handleForegroundMessage,
      );
      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }
      _tokenRefreshSubscription = _messaging!.onTokenRefresh.listen((token) {
        _currentToken = token;
        _registeredToken = null;
        unawaited(_syncRegistration());
      });
    } catch (_) {
      _firebaseAvailable = false;
    }
  }

  Future<void> syncWithAuth(bool authenticated) async {
    _authenticated = authenticated;
    if (_syncingRegistration) {
      _syncRegistrationQueued = true;
      return;
    }

    do {
      _syncingRegistration = true;
      _syncRegistrationQueued = false;
      try {
        await _syncRegistration();
      } finally {
        _syncingRegistration = false;
      }
    } while (_syncRegistrationQueued);
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _messageOpenedSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
  }

  Future<void> prepareForLogout() async {
    await _unregisterTokenIfNeeded();
  }

  Future<void> _syncRegistration() async {
    if (!_firebaseAvailable) {
      return;
    }
    final messaging = _messaging;
    if (messaging == null) {
      return;
    }

    if (!_authenticated) {
      await _unregisterTokenIfNeeded();
      return;
    }

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final authorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!authorized) {
      return;
    }

    _currentToken ??= await messaging.getToken();
    final token = _currentToken;
    if (token == null || token.isEmpty || token == _registeredToken) {
      return;
    }

    try {
      await _apiClient.registerPushToken(
        token: token,
        platform: 'android',
        deviceLabel: 'Android app',
      );
      _registeredToken = token;
    } catch (_) {
      // Riprovo al prossimo refresh sessione o refresh token.
    }
  }

  Future<void> _unregisterTokenIfNeeded() async {
    final token = _registeredToken ?? _currentToken;
    if (token == null || token.isEmpty) {
      _registeredToken = null;
      return;
    }
    try {
      await _apiClient.unregisterPushToken(token);
    } catch (_) {
      // Logout comunque valido; lato backend il token verra' sovrascritto alla prossima registrazione.
    } finally {
      _registeredToken = null;
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final target = _parseTarget(response.payload);
        if (target == null) {
          return;
        }
        _onLaunchTargetRequested(target);
      },
    );
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_androidChannel);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title = (notification?.title ?? '').trim();
    final body = (notification?.body ?? '').trim();
    if (title.isEmpty && body.isEmpty) {
      return;
    }
    await _localNotifications.show(
      _localNotificationId++,
      title.isEmpty ? 'ApprofittOffro' : title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'approfittoffro_alerts',
          'ApprofittOffro alerts',
          channelDescription:
              'Notifiche eventi, richieste, recensioni e follower.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: message.data['target']?.toString() ?? 'login',
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final target = _parseTarget(message.data['target']?.toString());
    if (target == null) {
      return;
    }
    _onLaunchTargetRequested(target);
  }

  AppLaunchTarget? _parseTarget(String? rawTarget) {
    final normalized = (rawTarget ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'pending-requests':
        return AppLaunchTarget.pendingRequests;
      case 'profile':
        return AppLaunchTarget.profile;
      case 'offers':
        return AppLaunchTarget.offers;
      case 'login':
        return AppLaunchTarget.login;
      case 'chat_request':
        return AppLaunchTarget.chatRequest;
      default:
        return null;
    }
  }
}
