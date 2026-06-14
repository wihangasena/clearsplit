import 'package:flutter_test/flutter_test.dart';
import 'package:buddysplit_flutter/app_state.dart';
import 'package:buddysplit_flutter/backend_client.dart';

/// In-memory backend mirroring the server's group fan-out + history/comment
/// behaviour, so [AppController] can be exercised without a server.
class _FakeBackend implements ClearSplitApi {
  _FakeBackend(this._state);
  AppData _state;

  @override
  Future<List<DemoAccount>> fetchAccounts() async => const [];

  @override
  Future<(DemoAccount, AppData)> login(String email, String password) async => (
        DemoAccount(
            id: _state.me, displayName: 'Riley', email: email, avatar: '🙂', color: '#2563EB'),
        _state,
      );

  @override
  Future<void> logout() async {}

  @override
  Future<AppData> saveState(String userId, AppData state) async => _state = state;

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
      final before = _state.expenses[idx];
      final merged = before.toJson()..addAll(updates);
      final after = Expense.fromJson(merged);
      after.history = [
        ...before.history,
        ExpenseHistoryEntry(
            user: requesterId, action: 'edited ${after.title}', timestamp: DateTime(2026)),
      ];
      _state.expenses[idx] = after;
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
  Future<AppData> addExpenseComment(
      String groupId, String expenseId, String requesterId, String message) async {
    final e = _state.expenses.firstWhere((x) => x.id == expenseId);
    e.comments.add(Comment(
        id: 'c${e.comments.length}',
        expenseId: expenseId,
        userId: requesterId,
        message: message,
        timestamp: DateTime(2026)));
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
      String groupId, String expenseId, String requesterId) async => _state;

  @override
  Future<AppData> updateProfile(String userId,
          {String? displayName, String? avatar, String? color}) async => _state;
}

AppData _state() => AppData(
      me: 'you',
      people: [
        Person(id: 'you', name: 'Riley', avatar: '🙂', color: '#2563EB'),
        Person(id: 'alex', name: 'Alex', avatar: '🧑', color: '#10B981'),
        Person(id: 'maya', name: 'Maya', avatar: '👩', color: '#8B5CF6'),
      ],
      groups: [
        // 'you' is first member → default group admin.
        Group(id: 'trip', name: 'Trip', emoji: '🚗', members: ['you', 'alex', 'maya']),
      ],
      expenses: [],
      settlements: [],
    );

Future<AppController> _signedIn(AppData state) async {
  final c = AppController(api: _FakeBackend(state));
  await c.signIn('you@clearsplit.app', 'demo123');
  return c;
}

Expense _friendExpense({
  String splitMethod = 'equal',
  Map<String, double>? splits,
  double amount = 90,
}) =>
    Expense(
      id: 'e1',
      title: 'Fuel',
      amount: amount,
      paidBy: 'you',
      participants: ['you', 'alex'],
      category: 'transport',
      date: DateTime(2026, 1, 1),
      splitMethod: splitMethod,
      splits: splits,
    );

void main() {
  group('Split validation', () {
    test('equal split is valid', () {
      expect(_friendExpense().validateSplits(), isNull);
    });

    test('exact amounts must sum to total', () {
      expect(
        _friendExpense(splitMethod: 'amount', splits: {'you': 40, 'alex': 50}, amount: 90)
            .validateSplits(),
        isNull,
      );
      expect(
        _friendExpense(splitMethod: 'amount', splits: {'you': 40, 'alex': 40}, amount: 90)
            .validateSplits(),
        isNotNull,
      );
    });

    test('percentages must sum to 100', () {
      expect(
        _friendExpense(splitMethod: 'percentage', splits: {'you': 60, 'alex': 40})
            .validateSplits(),
        isNull,
      );
      expect(
        _friendExpense(splitMethod: 'percentage', splits: {'you': 60, 'alex': 30})
            .validateSplits(),
        isNotNull,
      );
    });

    test('addExpense rejects an invalid split', () async {
      final c = await _signedIn(_state());
      expect(
        () => c.addExpense(
            _friendExpense(splitMethod: 'percentage', splits: {'you': 60, 'alex': 30})),
        throwsArgumentError,
      );
    });
  });

  group('Expense creation stamps creator + history', () {
    test('addExpense sets createdBy and an "added" history entry', () async {
      final c = await _signedIn(_state());
      await c.addExpense(_friendExpense());
      final e = c.state!.expenses.single;
      expect(e.createdBy, 'you');
      expect(e.history.single.action, 'added Fuel');
      expect(e.history.single.user, 'you');
    });
  });

  group('Editing + permissions', () {
    test('editExpense (friend) appends a history entry', () async {
      final c = await _signedIn(_state());
      await c.addExpense(_friendExpense());
      final edited = _friendExpense()..amount = 120;
      await c.editExpense(edited);
      final e = c.state!.expenses.single;
      expect(e.amount, 120);
      expect(e.history.length, 2);
      expect(e.history.last.action, contains('amount from 90.0 to 120.0'));
    });

    test('canModifyExpense: creator can, unrelated member cannot', () async {
      final c = await _signedIn(_state());
      final mine = _friendExpense();
      expect(c.canModifyExpense(mine), isTrue);

      // Group expense created by alex; "you" is group admin (first member) → allowed.
      final alexGroup = Expense(
        id: 'e2',
        title: 'Snacks',
        amount: 10,
        paidBy: 'alex',
        createdBy: 'alex',
        participants: ['you', 'alex'],
        groupId: 'trip',
        category: 'food',
        date: DateTime(2026, 1, 1),
      );
      expect(c.canModifyExpense(alexGroup), isTrue); // admin override

      // Friend expense created by alex, no group → "you" cannot modify.
      final alexFriend = Expense(
        id: 'e3',
        title: 'Coffee',
        amount: 6,
        paidBy: 'alex',
        createdBy: 'alex',
        participants: ['you', 'alex'],
        category: 'food',
        date: DateTime(2026, 1, 1),
      );
      expect(c.canModifyExpense(alexFriend), isFalse);
    });

    test('editExpense throws when the user lacks permission', () async {
      final c = await _signedIn(_state());
      final alexFriend = Expense(
        id: 'e3',
        title: 'Coffee',
        amount: 6,
        paidBy: 'alex',
        createdBy: 'alex',
        participants: ['you', 'alex'],
        category: 'food',
        date: DateTime(2026, 1, 1),
      );
      c.state!.expenses.add(alexFriend);
      expect(() => c.editExpense(alexFriend..amount = 9), throwsStateError);
    });

    test('deleteExpense (friend) removes it', () async {
      final c = await _signedIn(_state());
      await c.addExpense(_friendExpense());
      await c.deleteExpense(c.state!.expenses.single);
      expect(c.state!.expenses, isEmpty);
    });
  });

  group('Comments', () {
    test('addComment appends a comment without changing balances', () async {
      final c = await _signedIn(_state());
      await c.addExpense(_friendExpense());
      final before = c.computeBalances().owed;
      await c.addComment(c.state!.expenses.single, 'Thanks!');
      final e = c.state!.expenses.single;
      expect(e.comments.single.message, 'Thanks!');
      expect(e.comments.single.userId, 'you');
      expect(c.computeBalances().owed, before); // unchanged
    });

    test('empty comments are ignored', () async {
      final c = await _signedIn(_state());
      await c.addExpense(_friendExpense());
      await c.addComment(c.state!.expenses.single, '   ');
      expect(c.state!.expenses.single.comments, isEmpty);
    });
  });

  group('JSON round-trip', () {
    test('expense preserves createdBy, history and comments', () {
      final e = _friendExpense()
        ..createdBy = 'alex'
        ..history.add(ExpenseHistoryEntry(
            user: 'alex', action: 'added Fuel', timestamp: DateTime(2026, 1, 1)))
        ..comments.add(Comment(
            id: 'c1',
            expenseId: 'e1',
            userId: 'alex',
            message: 'hi',
            timestamp: DateTime(2026, 1, 1)));
      final restored = Expense.fromJson(e.toJson());
      expect(restored.createdBy, 'alex');
      expect(restored.history.single.action, 'added Fuel');
      expect(restored.comments.single.message, 'hi');
    });
  });
}
