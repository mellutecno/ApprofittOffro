import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../models/app_user.dart';

class AuthController extends ChangeNotifier {
  AuthController(this.apiClient);

  final ApiClient apiClient;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  AppUser? _currentUser;
  bool _isBusy = false;
  String? _errorMessage;
  bool _googleInitialized = false;

  AppUser? get currentUser => _currentUser;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null;

  Future<void> initialize() async {
    await apiClient.initialize();
    if (!apiClient.hasSession) {
      return;
    }
    try {
      _currentUser = await apiClient.fetchCurrentUser();
    } catch (_) {
      await apiClient.logout();
      _currentUser = null;
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
      _errorMessage = null;
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
      if (AppConfig.googleServerClientId.isEmpty) {
        throw ApiException(
          'Accesso Google non ancora configurato su questa build.',
        );
      }

      if (!_googleInitialized) {
        await _googleSignIn.initialize(
          clientId:
              AppConfig.googleAndroidClientId.isEmpty
                  ? null
                  : AppConfig.googleAndroidClientId,
          serverClientId: AppConfig.googleServerClientId,
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

      await apiClient.loginWithGoogle(idToken: idToken);
      _currentUser = await apiClient.fetchCurrentUser();
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
      _errorMessage = null;
      notifyListeners();
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }
}
