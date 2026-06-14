import 'package:flutter_test/flutter_test.dart';
import 'package:buddysplit_flutter/app_state.dart';
import 'package:buddysplit_flutter/backend_client.dart';

/// In-memory backend so [AppController] runs without a server (NFR-06).
class _FakeBackend implements ClearSplitApi {
  _FakeBackend(this._state);

  AppData _state;
  final List<DemoAccount> accounts = const [];

  @override
  Future<List<DemoAccount>> fetchAccounts() async => accounts;

  @override
  Future<(DemoAccount, AppData)> login(String email, String password) async {
    final account = DemoAccount(
      id: _state.me,
      displayName: 'Riley',
      email: email,
      avatar: '🙂',
      color: '#2563EB',
    );
    return (account, _state);
  }

  @override
  Future<(DemoAccount, AppData)> register(
      String name, String email, String password) async {
    return login(email, password);
  }

  @override
  Future<List<Member>> searchMembers(String query, {String? excludeId}) async =>
      const [];

  @override
  Future<AppData> syncGroup(String groupId, String requesterId) async => _state;

  @override
  Future<void> logout() async {}

  @override
  Future<AppData> saveState(String userId, AppData state) async {
    _state = state;
    return state;
  }

  @override
  Future<AppData> resetState(String userId) async => _state;

  @override
  Future<AppData> createGroupExpense(
      String groupId, String requesterId, Expense expense) async {
    _state.expenses.add(expense);
    return _state;
  }

  @override
  Future<AppData> editGroupExpense(String groupId, String expenseId,
      String requesterId, Map<String, dynamic> updates) async {
    final idx = _state.expenses.indexWhere((e) => e.id == expenseId);
    if (idx >= 0) {
      final merged = _state.expenses[idx].toJson()..addAll(updates);
      _state.expenses[idx] = Expense.fromJson(merged);
    }
    return _state;
  }

  @override
  Future<AppData> deleteGroupExpense(
      String groupId, String expenseId, String requesterId) async {
    _state.expenses.removeWhere((e) => e.id == expenseId);
    return _state;
  }

  @override
  Future<AppData> addExpenseComment(String groupId, String expenseId,
      String requesterId, String message) async {
    final e = _state.expenses.firstWhere((x) => x.id == expenseId);
    e.comments.add(Comment(
      id: 'cmt-${e.comments.length}',
      expenseId: expenseId,
      userId: requesterId,
      message: message,
      timestamp: DateTime(2026, 1, 1),
    ));
    return _state;
  }

  @override
  Future<AppData> recordSettlement(
      String groupId, String requesterId, Settlement settlement) async {
    _state.settlements.add(settlement);
    return _state;
  }

  @override
  Future<AppData> settleExpense(
      String groupId, String expenseId, String requesterId) async {
    for (final e in _state.expenses) {
      if (e.id == expenseId) e.settled = true;
    }
    return _state;
  }

  @override
  Future<AppData> updateProfile(String userId,
      {String? displayName, String? avatar, String? color}) async {
    final me = _state.personById(userId);
    if (me != null) {
      if (displayName != null) me.name = displayName;
      if (avatar != null) me.avatar = avatar;
      if (color != null) me.color = color;
    }
    return _state;
  }
}

AppData _sampleState() {
  return AppData(
    me: 'you',
    people: [
      Person(id: 'you', name: 'Riley', avatar: '🙂', color: '#2563EB'),
      Person(id: 'alex', name: 'Alex', avatar: '🧑', color: '#10B981'),
      Person(id: 'maya', name: 'Maya', avatar: '👩', color: '#8B5CF6'),
    ],
    groups: [
      Group(id: 'trip', name: 'Trip', emoji: '🚗', members: ['you', 'alex', 'maya']),
    ],
    expenses: [
      // You paid 90, split equally three ways → alex & maya each owe you 30.
      Expense(
        id: 'e1',
        title: 'Fuel',
        amount: 90,
        paidBy: 'you',
        participants: ['you', 'alex', 'maya'],
        groupId: 'trip',
        category: 'transport',
        date: DateTime(2026, 1, 1),
      ),
    ],
    settlements: [],
  );
}

void main() {
  group('Settlement & balance', () {
    test('JSON round-trip preserves a settlement', () {
      final s = Settlement(
        id: 's1',
        groupId: 'trip',
        from: 'alex',
        to: 'you',
        amount: 30,
        date: DateTime(2026, 1, 2),
      );
      final restored = Settlement.fromJson(s.toJson());
      expect(restored.id, s.id);
      expect(restored.groupId, s.groupId);
      expect(restored.from, s.from);
      expect(restored.to, s.to);
      expect(restored.amount, s.amount);
      expect(restored.date, s.date);
    });

    test('missing settlements key defaults to empty list', () {
      final state = AppData.fromJson({
        'me': 'you',
        'people': [],
        'groups': [],
        'expenses': [],
        // no "settlements" key
      });
      expect(state.settlements, isEmpty);
    });

    test('initial balances: alex and maya each owe you 30', () {
      final c = AppController(api: _FakeBackend(_sampleState()));
      // Hydrate controller state via login.
      return c.signIn('you@clearsplit.app', 'demo123').then((_) {
        final summary = c.computeBalances();
        expect(summary.perPerson['alex'], 30);
        expect(summary.perPerson['maya'], 30);
        expect(summary.owed, 60);
        expect(summary.owe, 0);
      });
    });

    test('partial settlement reduces balance', () async {
      final c = AppController(api: _FakeBackend(_sampleState()));
      await c.signIn('you@clearsplit.app', 'demo123');
      await c.recordSettlement('trip', from: 'alex', to: 'you', amount: 10);
      final summary = c.computeBalances();
      expect(summary.perPerson['alex'], 20); // 30 - 10
      expect(summary.owed, 50); // 20 + 30
    });

    test('full settlement clears a debt', () async {
      final c = AppController(api: _FakeBackend(_sampleState()));
      await c.signIn('you@clearsplit.app', 'demo123');
      await c.recordSettlement('trip', from: 'alex', to: 'you', amount: 30);
      await c.recordSettlement('trip', from: 'maya', to: 'you', amount: 30);
      final summary = c.computeBalances();
      expect(summary.owed, 0);
      expect(summary.perPerson['alex'], 0);
      expect(summary.perPerson['maya'], 0);
    });

    test('settleAllForGroup clears all debts in one call', () async {
      final c = AppController(api: _FakeBackend(_sampleState()));
      await c.signIn('you@clearsplit.app', 'demo123');
      await c.settleAllForGroup('trip');
      // After simplification + settle, the group nets to zero.
      final payments = c.computeGroupSettlements('trip');
      expect(payments, isEmpty);
    });

    test('recordSettlement rejects non-positive amount (SET-05)', () async {
      final c = AppController(api: _FakeBackend(_sampleState()));
      await c.signIn('you@clearsplit.app', 'demo123');
      expect(
        () => c.recordSettlement('trip', from: 'alex', to: 'you', amount: 0),
        throwsArgumentError,
      );
    });

    test('markSettled sets expense.settled = true', () async {
      final c = AppController(api: _FakeBackend(_sampleState()));
      await c.signIn('you@clearsplit.app', 'demo123');
      final expense = c.state!.expenses.first;
      await c.markSettled(expense);
      expect(c.state!.expenses.first.settled, isTrue);
    });

    test('computeGroupSettlements simplifies to minimal transfers', () async {
      final c = AppController(api: _FakeBackend(_sampleState()));
      await c.signIn('you@clearsplit.app', 'demo123');
      final payments = c.computeGroupSettlements('trip');
      // alex → you 30, maya → you 30 : two transfers, both to the creditor.
      final flat = payments.values.expand((e) => e).toList();
      expect(flat.length, 2);
      expect(flat.every((p) => p.to == 'you'), isTrue);
      expect(flat.fold<double>(0, (sum, p) => sum + p.amount), 60);
    });
  });
}
