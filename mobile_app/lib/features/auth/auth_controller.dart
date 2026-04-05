import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../models/app_user.dart';

class AuthController extends ChangeNotifier {
  AuthController(this.apiClient);

  static const Duration _sessionTimeout = Duration(minutes: 5);

  final ApiClient apiClient;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  AppUser? _currentUser;
  bool _isBusy = false;
  String? _errorMessage;
  bool _googleInitialized = false;
  String? _resolvedGoogleServerClientId;
  bool _pendingProfileCompletion = false;

  AppUser? get currentUser => _currentUser;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null;
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
    if (!apiClient.hasSession) {
      return;
    }
    if (await apiClient.sessionStore.isSessionExpired(_sessionTimeout)) {
      await apiClient.logout();
      _currentUser = null;
      _pendingProfileCompletion = false;
      notifyListeners();
      return;
    }
    try {
      _currentUser = await apiClient.fetchCurrentUser();
      _pendingProfileCompletion =
          _currentUser?.needsMandatoryProfileSetup ?? false;
      await apiClient.sessionStore.touch();
    } catch (_) {
      await apiClient.logout();
      _currentUser = null;
      _pendingProfileCompletion = false;
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
      _errorMessage = null;
      await apiClient.sessionStore.touch();
    } on ApiException catch (e) {
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

  Future<bool> loginWithGoogle() async {
    _setBusy(true);
    _errorMessage = null;

    try {
      final googleServerClientId = await _resolveGoogleServerClientId();
      if (googleServerClientId.isEmpty) {
        throw ApiException(
          'Accesso Google non ancora configurato su questa build.',
        );
      }

      if (!_googleInitialized) {
        await _googleSignIn.initialize(
          clientId: AppConfig.googleAndroidClientId.isEmpty
              ? null
              : AppConfig.googleAndroidClientId,
          serverClientId: googleServerClientId,
        );
        _googleInitialized = true;
      }

      final account = await _googleSignIn.authenticate();
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
      await apiClient.sessionStore.touch();
      notifyListeners();
      return true;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        _errorMessage = 'Accesso Google annullato.';
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
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Se l'utente non è entrato con Google, ignoro silenziosamente.
      }
      await apiClient.logout();
      _currentUser = null;
      _pendingProfileCompletion = false;
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
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        await _markAppInactive();
        break;
    }
  }

  Future<void> _handleAppResumed() async {
    if (!apiClient.hasSession) {
      return;
    }
    if (await apiClient.sessionStore.isSessionExpired(_sessionTimeout)) {
      await apiClient.logout();
      _currentUser = null;
      _pendingProfileCompletion = false;
      _errorMessage = null;
      notifyListeners();
      return;
    }
    await apiClient.sessionStore.touch();
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

  Future<String> deleteAccount() async {
    _setBusy(true);
    _errorMessage = null;

    try {
      final message = await apiClient.deleteMyAccount();
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Se l'utente non usa Google, ignoro.
      }
      _currentUser = null;
      _pendingProfileCompletion = false;
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
}
