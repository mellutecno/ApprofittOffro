import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../models/app_user.dart';

class AuthController extends ChangeNotifier {
  AuthController(this.apiClient) {
    apiClient.onUnauthorized = _handleUnauthorizedSession;
  }

  static const Duration _sessionTimeout = Duration(days: 30);

  final ApiClient apiClient;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  Future<void> Function()? beforeLogoutHook;

  AppUser? _currentUser;
  bool _isBusy = false;
  String? _errorMessage;
  bool _googleInitialized = false;
  String? _resolvedGoogleServerClientId;
  Future<void>? _googlePrepareFuture;
  bool _pendingProfileCompletion = false;
  bool _requiresReauthentication = false;
  bool _adminBackgroundLogoutInFlight = false;
  int _adminBackgroundLogoutHoldCount = 0;

  AppUser? get currentUser => _currentUser;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null;
  bool get requiresReauthentication => _requiresReauthentication;
  bool get pendingProfileCompletion =>
      _pendingProfileCompletion ||
      (_currentUser?.needsMandatoryProfileSetup ?? false);

  bool consumePendingProfileCompletion() {
    final shouldComplete = pendingProfileCompletion;
    _pendingProfileCompletion = false;
    return shouldComplete;
  }

  Future<void> initialize() async {
    await apiClient.initialize();
    prewarmGoogleSignIn();
    if (!apiClient.hasSession) {
      _requiresReauthentication = false;
      return;
    }
    if (await apiClient.sessionStore.isSessionExpired(_sessionTimeout)) {
      await _handleUnauthorizedSession();
      return;
    }
    try {
      _currentUser = await apiClient.fetchCurrentUser();
      _pendingProfileCompletion =
          _currentUser?.needsMandatoryProfileSetup ?? false;
      _requiresReauthentication = false;
      _errorMessage = null;
      await apiClient.sessionStore.touch();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _handleUnauthorizedSession();
      } else {
        _errorMessage = 'Non riesco a verificare la sessione adesso.';
      }
    } catch (_) {
      _errorMessage = 'Non riesco a verificare la sessione adesso.';
    }
    notifyListeners();
  }

  Future<void> refreshCurrentUser() async {
    if (!apiClient.hasSession) {
      _currentUser = null;
      notifyListeners();
      return;
    }

    try {
      _currentUser = await apiClient.fetchCurrentUser();
      _pendingProfileCompletion =
          _currentUser?.needsMandatoryProfileSetup ?? false;
      _requiresReauthentication = false;
      _errorMessage = null;
      await apiClient.sessionStore.touch();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _handleUnauthorizedSession();
        return;
      }
      _errorMessage = e.message;
    } catch (_) {
      _errorMessage = 'Non riesco ad aggiornare il profilo adesso.';
    }
    notifyListeners();
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _setBusy(true);
    _errorMessage = null;

    try {
      await apiClient.login(email: email, password: password);
      _currentUser = await apiClient.fetchCurrentUser();
      _pendingProfileCompletion = false;
      _requiresReauthentication = false;
      await apiClient.sessionStore.touch();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Non riesco a completare il login adesso.';
      notifyListeners();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<String?> requestPasswordReset({
    required String email,
  }) async {
    _setBusy(true);
    _errorMessage = null;

    try {
      final message = await apiClient.requestPasswordReset(email: email);
      _errorMessage = null;
      notifyListeners();
      return message;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return null;
    } catch (_) {
      _errorMessage = 'Non riesco a inviare il recupero password adesso.';
      notifyListeners();
      return null;
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> loginWithGoogle() async {
    _setBusy(true);
    _errorMessage = null;

    try {
      await _prepareGoogleSignIn();
      final account = await _googleSignIn.authenticate();
      return await _completeGoogleLogin(account);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        final recoveredAccount =
            await _tryRecoverCanceledGoogleAuthentication();
        if (recoveredAccount != null) {
          return await _completeGoogleLogin(recoveredAccount);
        }
        final description = e.description?.trim() ?? '';
        _errorMessage = description.isNotEmpty
            ? 'Accesso Google non riuscito: $description'
            : 'Accesso Google annullato.';
      } else {
        _errorMessage =
            e.description ?? 'Non riesco a completare l\'accesso Google.';
      }
      notifyListeners();
      return false;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _errorMessage = 'Non riesco a completare l\'accesso Google adesso.';
      notifyListeners();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> logout() async {
    _setBusy(true);
    try {
      if (beforeLogoutHook != null) {
        await beforeLogoutHook!();
      }
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Se l'utente non è entrato con Google, ignoro silenziosamente.
      }
      await apiClient.logout();
      _currentUser = null;
      _pendingProfileCompletion = false;
      _requiresReauthentication = false;
      _errorMessage = null;
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  Future<void> handleAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        await _handleAppResumed();
        break;
      case AppLifecycleState.inactive:
        await _markAppInactive();
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (_currentUser?.isAdmin == true) {
          if (_adminBackgroundLogoutHoldCount > 0) {
            await _markAppInactive();
          } else {
            await _logoutAdminOnBackground();
          }
        } else {
          await _markAppInactive();
        }
        break;
    }
  }

  Future<T> runWithAdminBackgroundLogoutSuspended<T>(
    Future<T> Function() action,
  ) async {
    _adminBackgroundLogoutHoldCount += 1;
    try {
      return await action();
    } finally {
      if (_adminBackgroundLogoutHoldCount > 0) {
        _adminBackgroundLogoutHoldCount -= 1;
      }
    }
  }

  Future<void> _logoutAdminOnBackground() async {
    if (_adminBackgroundLogoutInFlight || _currentUser?.isAdmin != true) {
      return;
    }
    _adminBackgroundLogoutInFlight = true;
    try {
      await logout();
    } finally {
      _adminBackgroundLogoutInFlight = false;
    }
  }

  Future<void> _handleAppResumed() async {
    if (!apiClient.hasSession) {
      return;
    }
    if (await apiClient.sessionStore.isSessionExpired(_sessionTimeout)) {
      await _handleUnauthorizedSession();
      return;
    }
    try {
      _currentUser = await apiClient.fetchCurrentUser();
      _pendingProfileCompletion =
          _currentUser?.needsMandatoryProfileSetup ?? false;
      _requiresReauthentication = false;
      _errorMessage = null;
      await apiClient.sessionStore.touch();
      notifyListeners();
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await _handleUnauthorizedSession();
      }
    } catch (_) {
      // Se la rete non è disponibile non butto fuori l'utente.
    }
  }

  Future<void> _markAppInactive() async {
    if (!apiClient.hasSession) {
      return;
    }
    await apiClient.sessionStore.touch();
  }

  Future<String> _resolveGoogleServerClientId() async {
    if (AppConfig.googleServerClientId.isNotEmpty) {
      return AppConfig.googleServerClientId;
    }
    if ((_resolvedGoogleServerClientId ?? '').isNotEmpty) {
      return _resolvedGoogleServerClientId!;
    }

    try {
      final payload = await apiClient.fetchGoogleAuthConfig();
      final serverClientId =
          (payload['server_client_id'] ?? '').toString().trim();
      _resolvedGoogleServerClientId = serverClientId;
      return serverClientId;
    } catch (_) {
      return '';
    }
  }

  Future<void> prewarmGoogleSignIn() async {
    try {
      await _prepareGoogleSignIn();
    } catch (_) {
      // Riprovo al primo tap sul login Google.
    }
  }

  Future<void> _prepareGoogleSignIn() {
    if (_googleInitialized) {
      return Future<void>.value();
    }

    final inFlight = _googlePrepareFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _configureGoogleSignIn();
    _googlePrepareFuture = future;
    return future;
  }

  Future<void> _configureGoogleSignIn() async {
    try {
      final googleServerClientId = await _resolveGoogleServerClientId();
      if (googleServerClientId.isEmpty) {
        throw ApiException(
          'Accesso Google non ancora configurato su questa build.',
        );
      }

      await _googleSignIn.initialize(
        clientId: AppConfig.googleAndroidClientId.isEmpty
            ? null
            : AppConfig.googleAndroidClientId,
        serverClientId: googleServerClientId,
      );
      _googleInitialized = true;
    } catch (_) {
      _googlePrepareFuture = null;
      rethrow;
    }
  }

  Future<bool> _completeGoogleLogin(GoogleSignInAccount account) async {
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw ApiException(
        'Google non ha restituito un token valido per completare l\'accesso.',
      );
    }

    final payload = await apiClient.loginWithGoogle(idToken: idToken);
    _currentUser = await apiClient.fetchCurrentUser();
    _pendingProfileCompletion = payload['created'] == true ||
        (_currentUser?.needsMandatoryProfileSetup ?? false);
    _requiresReauthentication = false;
    await apiClient.sessionStore.touch();
    notifyListeners();
    return true;
  }

  Future<GoogleSignInAccount?> _tryRecoverCanceledGoogleAuthentication() async {
    try {
      final attempt = _googleSignIn.attemptLightweightAuthentication(
        reportAllExceptions: true,
      );
      if (attempt == null) {
        return null;
      }
      return await attempt;
    } on GoogleSignInException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String> deleteAccount() async {
    _setBusy(true);
    _errorMessage = null;

    try {
      if (beforeLogoutHook != null) {
        await beforeLogoutHook!();
      }
      final message = await apiClient.deleteMyAccount();
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Se l'utente non usa Google, ignoro.
      }
      _currentUser = null;
      _pendingProfileCompletion = false;
      _requiresReauthentication = false;
      notifyListeners();
      return message;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      rethrow;
    } catch (_) {
      _errorMessage = 'Non riesco a eliminare il tuo account adesso.';
      notifyListeners();
      throw ApiException(_errorMessage!);
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }

  Future<void> _handleUnauthorizedSession() async {
    _currentUser = null;
    _pendingProfileCompletion = false;
    _requiresReauthentication = true;
    _errorMessage = 'Sessione scaduta. Effettua di nuovo il login.';
    _isBusy = false;
    try {
      await apiClient.clearLocalSession();
    } catch (_) {
      // La pulizia locale è già il fallback minimo necessario.
    }
    notifyListeners();
  }
}
