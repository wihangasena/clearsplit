import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_state.dart';

/// Thrown when the backend is unreachable or returns an error response.
class BackendClientException implements Exception {
  BackendClientException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'BackendClientException($statusCode): $message';
}

/// Abstraction over the backend so [AppController] can be constructed in tests
/// with an in-memory fake — no running server required (NFR-06).
abstract interface class ClearSplitApi {
  Future<List<DemoAccount>> fetchAccounts();
  Future<(DemoAccount, AppData)> login(String email, String password);
  Future<(DemoAccount, AppData)> register(
      String name, String email, String password);
  Future<List<Member>> searchMembers(String query, {String? excludeId});
  Future<AppData> syncGroup(String groupId, String requesterId);
  Future<AppData> addGroupMember(
      String groupId, String requesterId, Member member);
  Future<AppData> removeGroupMember(
      String groupId, String requesterId, String memberId);
  Future<AppData> assignGroupAdmin(
      String groupId, String requesterId, String memberId);
  Future<AppData> revokeGroupAdmin(
      String groupId, String requesterId, String memberId);
  Future<void> logout();
  Future<AppData> saveState(String userId, AppData state);
  Future<AppData> resetState(String userId);
  Future<AppData> createGroupExpense(
      String groupId, String requesterId, Expense expense);
  Future<AppData> editGroupExpense(String groupId, String expenseId,
      String requesterId, Map<String, dynamic> updates);
  Future<AppData> deleteGroupExpense(
      String groupId, String expenseId, String requesterId);
  Future<AppData> addExpenseComment(
      String groupId, String expenseId, String requesterId, String message);
  Future<AppData> recordSettlement(
      String groupId, String requesterId, Settlement settlement);
  Future<AppData> settleExpense(
      String groupId, String expenseId, String requesterId);
  Future<AppData> updateProfile(String userId,
      {String? displayName, String? avatar, String? color});
}

/// Thin wrapper over the ClearSplit REST API (REQUIREMENTS §7).
///
/// All methods throw [BackendClientException] on transport failure or non-2xx
/// responses so the controller can fall back to last-known local state.
class BackendClient implements ClearSplitApi {
  BackendClient({String? baseUrl, http.Client? httpClient})
      : baseUrl = baseUrl ?? _detectBaseUrl(),
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  /// Auto-detects the backend URL (overridable with
  /// `--dart-define=BACKEND_BASE_URL=...`):
  ///   - Android emulator → http://10.0.2.2:8081
  ///   - Web / desktop     → http://127.0.0.1:8081
  static String _detectBaseUrl() {
    const override = String.fromEnvironment('BACKEND_BASE_URL');
    if (override.isNotEmpty) return override;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8081';
    }
    return 'http://127.0.0.1:8081';
  }

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> _decode(http.Response res) async {
    final body = res.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw BackendClientException(
        body['message']?.toString() ?? 'Request failed',
        statusCode: res.statusCode,
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      final res = await request();
      return await _decode(res);
    } on BackendClientException {
      rethrow;
    } catch (e) {
      throw BackendClientException('Cannot reach backend: $e');
    }
  }

  static const _jsonHeaders = {'Content-Type': 'application/json'};

  @override
  Future<List<DemoAccount>> fetchAccounts() async {
    final body = await _send(() => _http.get(_uri('/accounts')));
    final list = (body['accounts'] as List).cast<Map<String, dynamic>>();
    return list.map(DemoAccount.fromJson).toList();
  }

  /// Returns `(account, state)` on success.
  @override
  Future<(DemoAccount, AppData)> login(String email, String password) async {
    final body = await _send(
      () => _http.post(
        _uri('/auth/login'),
        headers: _jsonHeaders,
        body: jsonEncode({'email': email, 'password': password}),
      ),
    );
    return (
      DemoAccount.fromJson(body['account'] as Map<String, dynamic>),
      AppData.fromJson(body['state'] as Map<String, dynamic>),
    );
  }

  /// Registers a new member and returns `(account, state)`, signed-in-ready.
  @override
  Future<(DemoAccount, AppData)> register(
      String name, String email, String password) async {
    final body = await _send(
      () => _http.post(
        _uri('/auth/register'),
        headers: _jsonHeaders,
        body: jsonEncode({'name': name, 'email': email, 'password': password}),
      ),
    );
    return (
      DemoAccount.fromJson(body['account'] as Map<String, dynamic>),
      AppData.fromJson(body['state'] as Map<String, dynamic>),
    );
  }

  /// Searches the member directory (demo accounts + registered members).
  @override
  Future<List<Member>> searchMembers(String query, {String? excludeId}) async {
    final params = <String, String>{'q': query};
    if (excludeId != null) params['excludeId'] = excludeId;
    final body = await _send(
      () => _http.get(_uri('/members').replace(queryParameters: params)),
    );
    final list = (body['members'] as List).cast<Map<String, dynamic>>();
    return list.map(Member.fromJson).toList();
  }

  /// Propagates a group's current membership to all members' states.
  @override
  Future<AppData> syncGroup(String groupId, String requesterId) async {
    final body = await _send(
      () => _http.post(
        _uri('/groups/$groupId/sync'),
        headers: _jsonHeaders,
        body: jsonEncode({'requesterId': requesterId}),
      ),
    );
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  /// Adds [member] to a group (admin only) and returns the fanned-out state.
  @override
  Future<AppData> addGroupMember(
    String groupId,
    String requesterId,
    Member member,
  ) async {
    final body = await _send(
      () => _http.post(
        _uri('/groups/$groupId/members'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'requesterId': requesterId,
          'member': {
            'id': member.id,
            'name': member.name,
            'avatar': member.avatar,
            'color': member.color,
          },
        }),
      ),
    );
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  /// Removes [memberId] from a group (admin only).
  @override
  Future<AppData> removeGroupMember(
    String groupId,
    String requesterId,
    String memberId,
  ) async {
    final body = await _send(
      () => _http.delete(
        _uri('/groups/$groupId/members/$memberId'),
        headers: _jsonHeaders,
        body: jsonEncode({'requesterId': requesterId}),
      ),
    );
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  /// Promotes [memberId] to admin (admin only).
  @override
  Future<AppData> assignGroupAdmin(
    String groupId,
    String requesterId,
    String memberId,
  ) async {
    final body = await _send(
      () => _http.put(
        _uri('/groups/$groupId/admins/$memberId'),
        headers: _jsonHeaders,
        body: jsonEncode({'requesterId': requesterId}),
      ),
    );
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  /// Revokes [memberId]'s admin role (admin only).
  @override
  Future<AppData> revokeGroupAdmin(
    String groupId,
    String requesterId,
    String memberId,
  ) async {
    final body = await _send(
      () => _http.delete(
        _uri('/groups/$groupId/admins/$memberId'),
        headers: _jsonHeaders,
        body: jsonEncode({'requesterId': requesterId}),
      ),
    );
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  @override
  Future<void> logout() async {
    await _send(() => _http.post(_uri('/auth/logout')));
  }

  @override
  Future<AppData> saveState(String userId, AppData state) async {
    final body = await _send(
      () => _http.put(
        _uri('/state/$userId'),
        headers: _jsonHeaders,
        body: jsonEncode({'state': state.toJson()}),
      ),
    );
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  @override
  Future<AppData> resetState(String userId) async {
    final body = await _send(() => _http.post(_uri('/state/$userId/reset')));
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  @override
  Future<AppData> createGroupExpense(
    String groupId,
    String requesterId,
    Expense expense,
  ) async {
    final body = await _send(
      () => _http.post(
        _uri('/groups/$groupId/expenses'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'requesterId': requesterId,
          'expense': expense.toJson(),
        }),
      ),
    );
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  @override
  Future<AppData> editGroupExpense(
    String groupId,
    String expenseId,
    String requesterId,
    Map<String, dynamic> updates,
  ) async {
    final body = await _send(
      () => _http.put(
        _uri('/groups/$groupId/expenses/$expenseId'),
        headers: _jsonHeaders,
        body: jsonEncode({'requesterId': requesterId, 'expense': updates}),
      ),
    );
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  @override
  Future<AppData> deleteGroupExpense(
    String groupId,
    String expenseId,
    String requesterId,
  ) async {
    final body = await _send(
      () => _http.delete(
        _uri('/groups/$groupId/expenses/$expenseId'),
        headers: _jsonHeaders,
        body: jsonEncode({'requesterId': requesterId}),
      ),
    );
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  @override
  Future<AppData> addExpenseComment(
    String groupId,
    String expenseId,
    String requesterId,
    String message,
  ) async {
    final body = await _send(
      () => _http.post(
        _uri('/groups/$groupId/expenses/$expenseId/comments'),
        headers: _jsonHeaders,
        body: jsonEncode({'requesterId': requesterId, 'message': message}),
      ),
    );
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  @override
  Future<AppData> recordSettlement(
    String groupId,
    String requesterId,
    Settlement settlement,
  ) async {
    final body = await _send(
      () => _http.post(
        _uri('/groups/$groupId/settlements'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'requesterId': requesterId,
          'settlement': settlement.toJson(),
        }),
      ),
    );
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  @override
  Future<AppData> settleExpense(
    String groupId,
    String expenseId,
    String requesterId,
  ) async {
    final body = await _send(
      () => _http.post(
        _uri('/groups/$groupId/expenses/$expenseId/settle'),
        headers: _jsonHeaders,
        body: jsonEncode({'requesterId': requesterId}),
      ),
    );
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  @override
  Future<AppData> updateProfile(
    String userId, {
    String? displayName,
    String? avatar,
    String? color,
  }) async {
    final body = await _send(
      () => _http.patch(
        _uri('/profile/$userId'),
        headers: _jsonHeaders,
        body: jsonEncode({
          'displayName': ?displayName,
          'avatar': ?avatar,
          'color': ?color,
        }),
      ),
    );
    return AppData.fromJson(body['state'] as Map<String, dynamic>);
  }

  void dispose() => _http.close();
}
