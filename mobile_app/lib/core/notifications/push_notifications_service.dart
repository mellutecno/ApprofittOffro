import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../chat/chat_presence_tracker.dart';
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
        try {
          await Firebase.initializeApp();
        } catch (_) {
          if (!AppConfig.firebaseMessagingConfigured) {
            rethrow;
          }
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
      android: AndroidInitializationSettings('ic_notification_small'),
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

    // Se e' un messaggio chat, gestiscilo diversamente.
    if (message.data['type'] == 'chat_message' ||
        message.data['type'] == 'chat_cleared') {
      final offerId = int.tryParse(message.data['offer_id']?.toString() ?? '');
      final otherUserId =
          int.tryParse(message.data['chat_with_user_id']?.toString() ?? '');
      if (offerId != null &&
          otherUserId != null &&
          ChatPresenceTracker.isViewingConversation(
            offerId: offerId,
            otherUserId: otherUserId,
          )) {
        return;
      }

      final chatPayload = _buildChatPayload(
        offerId: message.data['offer_id'],
        otherUserId: message.data['chat_with_user_id'],
        otherUserName: message.data['chat_with_name'],
        otherUserPhotoFilename: message.data['chat_with_photo_filename'],
      );

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
            icon: 'ic_notification_small',
            color: Color(0xFFDFFF00),
          ),
        ),
        payload: chatPayload ?? (message.data['target']?.toString() ?? 'login'),
      );
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
          icon: 'ic_notification_small',
          color: Color(0xFFDFFF00),
        ),
      ),
      payload: message.data['target']?.toString() ?? 'login',
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    // Gestisci tap su notifica chat.
    if (message.data['type'] == 'chat_message' ||
        message.data['type'] == 'chat_cleared') {
      final chatPayload = _buildChatPayload(
        offerId: message.data['offer_id'],
        otherUserId: message.data['chat_with_user_id'],
        otherUserName: message.data['chat_with_name'],
        otherUserPhotoFilename: message.data['chat_with_photo_filename'],
      );
      final chatTarget = _parseTarget(chatPayload);
      if (chatTarget != null) {
        _onLaunchTargetRequested(chatTarget);
        return;
      }
    }

    final target = _parseTarget(message.data['target']?.toString());
    if (target == null) {
      return;
    }
    _onLaunchTargetRequested(target);
  }

  AppLaunchTarget? _parseTarget(String? rawTarget) {
    final raw = (rawTarget ?? '').trim();

    // Gestisci target chat.
    if (raw.toLowerCase().startsWith('chat:')) {
      final parts = raw.split(':');
      if (parts.length >= 4) {
        final offerId = int.tryParse(parts[1]);
        final otherUserId = int.tryParse(parts[2]);
        if (offerId == null ||
            offerId <= 0 ||
            otherUserId == null ||
            otherUserId <= 0) {
          return null;
        }
        final decodedName = Uri.decodeComponent(parts[3]).trim();
        final decodedPhoto = parts.length >= 5
            ? Uri.decodeComponent(parts.sublist(4).join(':')).trim()
            : '';
        return AppLaunchTarget.chat(
          offerId: offerId,
          otherUserId: otherUserId,
          otherUserName: decodedName.isEmpty ? 'Utente' : decodedName,
          otherUserPhotoFilename: decodedPhoto,
        );
      }
    }

    final normalized = raw.toLowerCase();
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

  String? _buildChatPayload({
    required Object? offerId,
    required Object? otherUserId,
    required Object? otherUserName,
    required Object? otherUserPhotoFilename,
  }) {
    final parsedOfferId = int.tryParse((offerId ?? '').toString());
    final parsedOtherUserId = int.tryParse((otherUserId ?? '').toString());
    if (parsedOfferId == null ||
        parsedOfferId <= 0 ||
        parsedOtherUserId == null ||
        parsedOtherUserId <= 0) {
      return null;
    }

    final safeName =
        Uri.encodeComponent((otherUserName ?? '').toString().trim());
    final safePhoto = Uri.encodeComponent(
      (otherUserPhotoFilename ?? '').toString().trim(),
    );
    return 'chat:$parsedOfferId:$parsedOtherUserId:$safeName:$safePhoto';
  }
}
