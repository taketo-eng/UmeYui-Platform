import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/user.dart';
import 'api_client.dart';

// 認証状態を表すEnum
enum AuthStatus {
  unknown, // after just app started or during token validation
  authenticated,
  unauthenticated,
}

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  String? _errorMessage;

  // Getter
  AuthStatus get status => _status;
  User? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isAdmin => _user?.isAdmin ?? false;

  // アプリ起動時の初期化
  Future<void> initialize() async {
    final token = await apiClient.getToken();
    if (token == null) {
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    // トークンがあればユーザー情報を取得して復元
    // JWTのペイロードからuser_idを取り出す
    try {
      final userId = _parseUserIdFromToken(token);
      final json = await apiClient.getMe(userId);
      _user = User.fromJson(json);
      _status = AuthStatus.authenticated;
      await _setupPushToken(userId);
    } catch (_) {
      // トークンが無効・期限切れの場合はログアウト状態に
      await apiClient.deleteToken();
      _status = AuthStatus.unauthenticated;
    }

    notifyListeners();
  }

  // Login
  Future<bool> login(String email, String password) async {
    _errorMessage = null;
    try {
      final data = await apiClient.login(email, password);
      _user = User.fromJson(data['user'] as Map<String, dynamic>);
      _status = AuthStatus.authenticated;
      notifyListeners();
      await _setupPushToken(_user!.id);
      return true;
    } on ApiException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
      return false;
    }
  }

  // logout
  Future<void> logout() async {
    await apiClient.logout();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  // ユーザー情報を更新
  Future<void> refreshUser() async {
    if (_user == null) return;
    final json = await apiClient.getMe(_user!.id);
    _user = User.fromJson(json);
    notifyListeners();
  }

  Future<void> _setupPushToken(String userId) async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final fcmToken = await messaging.getToken();
      if (fcmToken != null) {
        await apiClient.registerPushToken(userId, fcmToken);
      }
      messaging.onTokenRefresh.listen((newToken) {
        apiClient.registerPushToken(userId, newToken);
      });
    } catch (_) {
      // 通知許可が拒否された場合などは無視して続行
    }
  }

  // JWTトークンのペイロード部分からuser_idを取り出す
  // JWT構造: header.payload.signature の payload をBase64デコード
  String _parseUserIdFromToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) throw Exception('Invalid token');

    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    switch (payload.length % 4) {
      case 2:
        payload += '==';
        break;
      case 3:
        payload += '=';
        break;
    }

    final decoded = utf8.decode(base64Decode(payload));
    final map = jsonDecode(decoded) as Map<String, dynamic>;
    return map['sub'] as String;
  }
}
