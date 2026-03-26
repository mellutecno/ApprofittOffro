import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../models/app_user.dart';

class AuthController extends ChangeNotifier {
  AuthController(this.apiClient);

  final ApiClient apiClient;

  AppUser? _currentUser;
  bool _isBusy = false;
  String? _errorMessage;

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

  Future<void> logout() async {
    _setBusy(true);
    try {
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
