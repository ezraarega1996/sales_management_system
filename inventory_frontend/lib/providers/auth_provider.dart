import 'package:flutter/material.dart';
import 'package:inventory_frontend/models/user.dart';
import 'package:inventory_frontend/services/sale_outbox.dart';
import 'package:inventory_frontend/utils/api.dart';
import 'package:inventory_frontend/utils/local_cache.dart';
import 'package:inventory_frontend/utils/storage.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _error;
  bool _isAuthenticated = false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _isAuthenticated;
  bool get isOwner => _user?.role == 'owner';
  bool get isAdmin => _user?.role == 'admin';

  /// Restores the saved session (called by the splash screen). Works offline: no network call
  /// is needed to enter the app.
  Future<void> checkAuth() async {
    _isLoading = true;
    notifyListeners();
    try {
      final token = await Storage.getToken();
      final userData = await Storage.getUser();
      if (token != null && userData != null) {
        _user = User.fromJson(userData);
        _isAuthenticated = true;
        await _attachUserData();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Points the offline cache and sales queue at the current user's data.
  Future<void> _attachUserData() async {
    LocalCache.setUser(_user?.id);
    await SaleOutbox.instance.switchUser(_user?.id);
    SaleOutbox.instance.sync();
  }

  Future<bool> login(String username, String password) async {
    if (username.isEmpty || password.isEmpty) {
      _error = 'Username and password are required';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await Api.post('auth/login', {'username': username, 'password': password});
      if (response == null || response['token'] == null || response['user'] == null) {
        _error = 'Invalid response from server';
        return false;
      }
      await Storage.saveToken(response['token']);
      await Storage.saveUser(response['user']);
      _user = User.fromJson(response['user']);
      _isAuthenticated = true;
      await _attachUserData();
      return true;
    } on OfflineException {
      _error = 'Cannot reach the server. Check your connection and try again.';
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> registerBusiness(Map<String, dynamic> businessData) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await Api.post('businesses', businessData);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> changePassword(String currentPassword, String newPassword) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await Api.post('auth/change-password', {'currentPassword': currentPassword, 'newPassword': newPassword});
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Called on logout to clear what other providers loaded for this user (set up in main.dart).
  VoidCallback? onLoggedOut;

  /// Unsynced sales are kept on the phone (per user) and sent after the same user logs in again.
  Future<void> logout() async {
    await Storage.clearSession();
    await LocalCache.clear();
    await SaleOutbox.instance.switchUser(null);
    LocalCache.setUser(null);
    _user = null;
    _isAuthenticated = false;
    onLoggedOut?.call();
    notifyListeners();
  }
}
