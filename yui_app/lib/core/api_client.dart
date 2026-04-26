import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

const _baseUrl = 'https://yui-api.yahiro-t-eng.workers.dev';

// トークンを保存するためのキー
const _tokenKey = 'jwt_token';

class ApiClient {
  // iOSはkeychain, Androidはkeystoreに保存される
  final _storage = const FlutterSecureStorage();

  // -- token management --
  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return _storage.read(key: _tokenKey);
  }

  Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  // -- http request helper --
  Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final token = await getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  // check response status and throw exeptions if needed
  void _checkStatus(http.Response res) {
    if (res.statusCode >= 400) {
      try {
        final body = jsonDecode(res.body);
        final message = body['error'] as String? ?? 'エラーが発生しました';
        throw ApiException(res.statusCode, message);
      } on ApiException {
        rethrow;
      } catch (_) {
        // レスポンスがJSONでない場合（500 Internal Server Error など）
        throw ApiException(res.statusCode, 'エラーが発生しました（${res.statusCode}）');
      }
    }
  }

  // GET Request
  Future<dynamic> get(String path) async {
    final res = await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
    );
    _checkStatus(res);
    return jsonDecode(res.body);
  }

  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    bool auth = true,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(auth: auth),
      body: jsonEncode(body),
    );
    _checkStatus(res);
    return jsonDecode(res.body);
  }

  // Patch Request
  Future<dynamic> patch(String path, Map<String, dynamic> body) async {
    final res = await http.patch(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    _checkStatus(res);
    return jsonDecode(res.body);
  }

  // delete request
  Future<dynamic> delete(String path) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl$path'),
      headers: await _headers(),
    );
    _checkStatus(res);
    return jsonDecode(res.body);
  }

  // Authorization API
  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = await post('/auth/login', {
      'email': email,
      'password': password,
    }, auth: false);
    await saveToken(data['token'] as String);
    return data;
  }

  Future<void> logout() async {
    await post('/auth/logout', {});
    await deleteToken();
  }

  // パスワード変更申請（確認コードをメール送信）
  // 戻り値: { email_hint: 'ab****@example.com' }
  Future<Map<String, dynamic>> requestPasswordChange(
    String currentPassword,
    String newPassword,
  ) async {
    return await post('/auth/change-password', {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  // 確認コードでパスワード変更を確定
  Future<void> verifyPasswordChange(String code) async {
    await post('/auth/verify-password-change', {'code': code});
  }

  // 管理者によるパスワードリセット（現在のパスワード不要）
  Future<void> adminResetPassword(String userId, String newPassword) async {
    await patch('/users/$userId/reset-password', {'new_password': newPassword});
  }

  // メールアドレス変更申請（確認コードを現在のメアドに送信）
  Future<Map<String, dynamic>> requestEmailChange(
    String currentPassword,
  ) async {
    return await post('/auth/change-email', {
      'current_password': currentPassword,
    });
  }

  // 確認コード + 新しいメアドでメールアドレス変更を確定
  Future<void> verifyEmailChange(String code, String newEmail) async {
    await post('/auth/verify-email-change', {
      'code': code,
      'new_email': newEmail,
    });
  }

  // 管理者によるメールアドレス変更（復旧用）
  Future<void> adminChangeEmail(String userId, String newEmail) async {
    await patch('/users/$userId/email', {'new_email': newEmail});
  }

  // User API
  Future<Map<String, dynamic>> getMe(String userId) async {
    return await get('/users/$userId');
  }

  Future<void> updateProfile(
    String userId, {
    String? shopName,
    String? bio,
    String? homepageBio,
    String? category,
    String? websiteUrl,
    String? instagramUrl,
    String? xUrl,
    String? lineUrl,
    String? facebookUrl,
  }) async {
    await patch('/users/$userId', {
      if (shopName != null) 'shop_name': shopName,
      if (bio != null) 'bio': bio,
      if (homepageBio != null) 'homepage_bio': homepageBio,
      if (category != null) 'category': category,
      if (websiteUrl != null) 'website_url': websiteUrl,
      if (instagramUrl != null) 'instagram_url': instagramUrl,
      if (xUrl != null) 'x_url': xUrl,
      if (lineUrl != null) 'line_url': lineUrl,
      if (facebookUrl != null) 'facebook_url': facebookUrl,
    });
  }

  Future<List<dynamic>> getUsers() async {
    return await get('/users') as List<dynamic>;
  }

  Future<Map<String, dynamic>> createUser({
    required String email,
    required String password,
    String? shopName,
  }) async {
    return await post('/users', {
      'email': email,
      'password': password,
      if (shopName != null && shopName.isNotEmpty) 'shop_name': shopName,
    });
  }

  Future<Map<String, dynamic>> uploadAvatar(
    String userId,
    File imageFile,
  ) async {
    final token = await getToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/users/$userId/avatar'),
    );
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    final ext = imageFile.path.split('.').last.toLowerCase();
    final mimeType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    request.files.add(
      await http.MultipartFile.fromPath(
        'avatar',
        imageFile.path,
        contentType: MediaType.parse(mimeType),
      ),
    );
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    _checkStatus(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadHomepageAvatar(String userId, File imageFile) async {
    final token = await getToken();
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/users/$userId/homepage-avatar'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    final ext = imageFile.path.split('.').last.toLowerCase();
    final mimeType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    request.files.add(await http.MultipartFile.fromPath('image', imageFile.path, contentType: MediaType.parse(mimeType)));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    _checkStatus(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ---- パスワードリセット（未ログイン） ----
  Future<Map<String, dynamic>> requestPasswordReset(String email, String newPassword) async {
    return await post('/auth/forgot-password', {'email': email, 'new_password': newPassword}, auth: false) as Map<String, dynamic>;
  }

  Future<void> verifyPasswordReset(String email, String code) async {
    await post('/auth/verify-forgot-password', {'email': email, 'code': code}, auth: false);
  }

  Future<void> setUserActive(String userId, bool isActive) async {
    await patch('/users/$userId/active', {'is_active': isActive ? 1 : 0});
  }

  Future<void> deleteUser(String userId) async {
    await delete('/users/$userId');
  }

  // Slot API
  Future<List<dynamic>> getSlots() async {
    return await get('/slots');
  }

  Future<Map<String, dynamic>> getSlotDetail(String slotId) async {
    return await get('/slots/$slotId');
  }

  Future<Map<String, dynamic>> createSlot(String date) async {
    return await post('/slots', {'date': date});
  }

  Future<void> deleteSlot(String slotId) async {
    await delete('/slots/$slotId');
  }

  Future<void> updateSlot(
    String slotId, {
    String? name,
    String? startTime,
    String? endTime,
    String? description,
    int? minVendors,
    int? maxVendors,
  }) async {
    await patch('/slots/$slotId', {
      if (name != null) 'name': name,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (description != null) 'description': description,
      if (minVendors != null) 'min_vendors': minVendors,
      if (maxVendors != null) 'max_vendors': maxVendors,
    });
  }

  // ---- 予約API ----
  Future<Map<String, dynamic>> createReservation(
    String slotId, {
    int? minVendors,
    int? maxVendors,
  }) async {
    return await post('/slots/$slotId/reservations', {
      if (minVendors != null) 'min_vendors': minVendors,
      if (maxVendors != null) 'max_vendors': maxVendors,
    });
  }

  Future<void> cancelReservation(String slotId) async {
    await delete('/slots/$slotId/reservations');
  }

  // ---- 参加申請API ----

  Future<Map<String, dynamic>> sendJoinRequest(
    String slotId, {
    String? message,
  }) async {
    return await post('/slots/$slotId/join-requests', {
      if (message != null && message.isNotEmpty) 'message': message,
    });
  }

  Future<List<dynamic>> getIncomingRequests() async {
    return await get('/join-requests/incoming') as List<dynamic>;
  }

  Future<List<dynamic>> getOutgoingRequests() async {
    return await get('/join-requests/outgoing') as List<dynamic>;
  }

  Future<void> respondToRequest(
    String requestId, {
    required String action, // 'approve' or 'reject'
    String? responseMessage,
  }) async {
    await patch('/join-requests/$requestId', {
      'action': action,
      if (responseMessage != null && responseMessage.isNotEmpty)
        'response_message': responseMessage,
    });
  }

  Future<void> registerPushToken(String userId, String token) async {
    await patch('/users/$userId/push-token', {'push_token': token});
  }

  // ---- 通知API ----

  Future<List<dynamic>> getNotifications() async {
    return await get('/notifications') as List<dynamic>;
  }

  Future<void> markAllNotificationsRead() async {
    await patch('/notifications/read-all', {});
  }

  // ---- チャットAPI ----

  Future<List<dynamic>> getChatRooms() async {
    final data = await get('/chat-rooms');
    return data['rooms'] as List<dynamic>;
  }

  Future<void> cancelEvent(String slotId) async {
    await post('/slots/$slotId/cancel-event', {});
  }

  Future<Map<String, dynamic>> getChatRoom(String roomId) async {
    return await get('/chat-rooms/$roomId');
  }

  Future<Map<String, dynamic>> getMessages(
    String roomId, {
    String? before,
  }) async {
    final query = before != null ? '?before=$before' : '';
    return await get('/chat-rooms/$roomId/messages$query');
  }

  Future<Map<String, dynamic>> sendMessage(
    String roomId,
    String body, {
    File? imageFile,
  }) async {
    if (imageFile != null) {
      final token = await getToken();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/chat-rooms/$roomId/messages'),
      );
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (body.isNotEmpty) request.fields['body'] = body;
      request.files.add(
        await http.MultipartFile.fromPath(
          'image',
          imageFile.path,
          contentType: MediaType.parse('image/jpeg'),
        ),
      );
      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      _checkStatus(res);
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    return await post('/chat-rooms/$roomId/messages', {'body': body});
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

final apiClient = ApiClient();

/// 相対パス（'/' 始まり）を絶対URLに変換する
String resolveUrl(String url) => url.startsWith('/') ? '$_baseUrl$url' : url;
