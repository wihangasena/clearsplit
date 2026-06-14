import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:buddysplit_flutter/app_state.dart';
import 'package:buddysplit_flutter/backend_client.dart';
import 'package:buddysplit_flutter/main.dart';

/// Minimal offline backend so the smoke test never touches the network.
class _NoopBackend implements ClearSplitApi {
  @override
  Future<List<DemoAccount>> fetchAccounts() async => const [];
  @override
  Future<(DemoAccount, AppData)> login(String e, String p) async =>
      throw BackendClientException('offline');
  @override
  Future<void> logout() async {}
  @override
  Future<AppData> saveState(String userId, AppData state) async => state;
  @override
  Future<AppData> resetState(String userId) async =>
      throw BackendClientException('offline');
  @override
  Future<AppData> createGroupExpense(String g, String r, Expense e) async =>
      throw BackendClientException('offline');
  @override
  Future<AppData> editGroupExpense(
          String g, String e, String r, Map<String, dynamic> u) async =>
      throw BackendClientException('offline');
  @override
  Future<AppData> deleteGroupExpense(String g, String e, String r) async =>
      throw BackendClientException('offline');
  @override
  Future<AppData> addExpenseComment(
          String g, String e, String r, String m) async =>
      throw BackendClientException('offline');
  @override
  Future<AppData> recordSettlement(String g, String r, Settlement s) async =>
      throw BackendClientException('offline');
  @override
  Future<AppData> settleExpense(String g, String e, String r) async =>
      throw BackendClientException('offline');
  @override
  Future<AppData> updateProfile(String userId,
          {String? displayName, String? avatar, String? color}) async =>
      throw BackendClientException('offline');
}

void main() {
  testWidgets('shows the login screen when signed out', (tester) async {
    await tester.pumpWidget(
      ClearSplitApp(controller: AppController(api: _NoopBackend())),
    );
    await tester.pumpAndSettle();

    expect(find.text('ClearSplit'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });
}
