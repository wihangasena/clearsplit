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
  Future<(DemoAccount, AppData)> register(
      String name, String email, String password) async =>
      login(email, password);

  @override
  Future<List<Member>> searchMembers(String query, {String? excludeId}) async =>
      const [];

  @override
  Future<AppData> syncGroup(String groupId, String requesterId) async => _state;

  @override
  Future<AppData> addGroupMember(
      String groupId, String requesterId, Member member) async {
    final g = _state.groupById(groupId);
    if (g != null && !g.members.contains(member.id)) g.members.add(member.id);
    if (!_state.people.any((p) => p.id == member.id)) {
      _state.people.add(member.toPerson());
    }
    return _state;
  }

  @override
  Future<AppData> removeGroupMember(
      String groupId, String requesterId, String memberId) async {
    final g = _state.groupById(groupId);
    g?.members.remove(memberId);
    g?.admins.remove(memberId);
    return _state;
  }

  @override
  Future<AppData> assignGroupAdmin(
      String groupId, String requesterId, String memberId) async {
    final g = _state.groupById(groupId);
    if (g != null && !g.admins.contains(memberId)) g.admins.add(memberId);
    return _state;
  }

  @override
  Future<AppData> revokeGroupAdmin(
      String groupId, String requesterId, String memberId) async {
    final g = _state.groupById(groupId);
    g?.admins.remove(memberId);
    return _state;
  }

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

  group('Activity feed', () {
    test('addExpense (friend) logs an "added" activity event', () async {
      final c = await _signedIn(_state());
      await c.addExpense(_friendExpense());
      final a = c.state!.activity.single;
      expect(a.type, ActivityEvent.typeAdded);
      expect(a.actor, 'you');
      expect(a.expenseId, 'e1');
      expect(a.title, 'Fuel');
    });

    test('editExpense (friend) logs an "edited" event describing the change',
        () async {
      final c = await _signedIn(_state());
      await c.addExpense(_friendExpense());
      await c.editExpense(_friendExpense()..amount = 120);
      final edits =
          c.state!.activity.where((a) => a.type == ActivityEvent.typeEdited);
      expect(edits.length, 1);
      expect(edits.single.description, contains('amount from 90.0 to 120.0'));
    });

    test('deleteExpense (friend) logs a "deleted" event that survives removal',
        () async {
      final c = await _signedIn(_state());
      await c.addExpense(_friendExpense());
      await c.deleteExpense(c.state!.expenses.single);
      expect(c.state!.expenses, isEmpty);
      final del = c.state!.activity
          .where((a) => a.type == ActivityEvent.typeDeleted)
          .single;
      // The snapshot persists even though the expense record is gone.
      expect(del.title, 'Fuel');
      expect(del.amount, 90);
    });

    test('markSettled (friend) logs a "settled" event', () async {
      final c = await _signedIn(_state());
      await c.addExpense(_friendExpense());
      await c.markSettled(c.state!.expenses.single);
      final settled = c.state!.activity
          .where((a) => a.type == ActivityEvent.typeSettled)
          .single;
      expect(settled.expenseId, 'e1');
    });

    test('AppData round-trips activity through JSON', () {
      final data = _state()
        ..activity.add(ActivityEvent(
          id: 'a1',
          type: ActivityEvent.typeAdded,
          actor: 'you',
          expenseId: 'e1',
          title: 'Fuel',
          amount: 90,
          timestamp: DateTime(2026, 1, 1),
        ));
      final restored = AppData.fromJson(data.toJson());
      expect(restored.activity.single.title, 'Fuel');
      expect(restored.activity.single.type, ActivityEvent.typeAdded);
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

    test('group preserves admins through JSON', () {
      final g = Group(
          id: 'g', name: 'X', emoji: '👥', members: ['you', 'alex'], admins: ['alex']);
      expect(Group.fromJson(g.toJson()).admins, ['alex']);
    });

    test('group without admins defaults to the first member', () {
      final g = Group.fromJson(
          {'id': 'g', 'name': 'X', 'emoji': '👥', 'members': ['you', 'alex']});
      expect(g.admins, ['you']);
      expect(g.isAdmin('you'), isTrue);
      expect(g.isAdmin('alex'), isFalse);
    });
  });

  group('Group roles & membership', () {
    test('createGroup makes the creator the sole admin', () async {
      final c = await _signedIn(_state());
      final g = await c.createGroup('Cabin', '⛺');
      expect(g.admins, ['you']);
      expect(c.amIAdmin(g.id), isTrue);
      expect(c.isAdmin(g.id, 'alex'), isFalse);
    });

    test('first member is admin by default on a group without an admins list',
        () async {
      final c = await _signedIn(_state());
      expect(c.amIAdmin('trip'), isTrue); // 'you' is first member of 'trip'
    });

    test('assignAdmin then revokeAdmin toggles the role', () async {
      final c = await _signedIn(_state());
      await c.assignAdmin('trip', 'alex');
      expect(c.isAdmin('trip', 'alex'), isTrue);
      await c.revokeAdmin('trip', 'alex');
      expect(c.isAdmin('trip', 'alex'), isFalse);
    });

    test('revokeAdmin throws on the last admin', () async {
      final c = await _signedIn(_state());
      expect(() => c.revokeAdmin('trip', 'you'), throwsStateError);
    });

    test('removeMemberFromGroup removes a settled member', () async {
      final c = await _signedIn(_state());
      final g = await c.createGroup('Duo', '👥', members: [
        Member(id: 'alex', name: 'Alex', avatar: '🧑', color: '#10B981'),
      ]);
      expect(g.members.contains('alex'), isTrue);
      await c.removeMemberFromGroup(g.id, 'alex');
      expect(c.state!.groupById(g.id)!.members.contains('alex'), isFalse);
    });

    test('removeMemberFromGroup blocks a member with an outstanding balance',
        () async {
      final c = await _signedIn(_state());
      await c.addExpense(Expense(
        id: 'g-exp',
        title: 'Cabin',
        amount: 90,
        paidBy: 'you',
        participants: ['you', 'alex', 'maya'],
        groupId: 'trip',
        category: 'home',
        date: DateTime(2026, 1, 1),
      ));
      expect(() => c.removeMemberFromGroup('trip', 'alex'), throwsStateError);
    });

    test('removeMemberFromGroup blocks removing the last admin', () async {
      final c = await _signedIn(_state());
      expect(() => c.removeMemberFromGroup('trip', 'you'), throwsStateError);
    });

    test('non-admins cannot manage members or roles', () async {
      final c = await _signedIn(_state());
      c.state!.groups.add(Group(
        id: 'g2',
        name: 'Others',
        emoji: '👥',
        members: ['you', 'alex'],
        admins: ['alex'], // 'you' is only a member here
      ));
      expect(c.amIAdmin('g2'), isFalse);
      expect(() => c.assignAdmin('g2', 'you'), throwsStateError);
      expect(() => c.revokeAdmin('g2', 'alex'), throwsStateError);
      expect(() => c.removeMemberFromGroup('g2', 'alex'), throwsStateError);
      expect(
        () => c.addMembersToGroup('g2', [
          Member(id: 'maya', name: 'Maya', avatar: '👩', color: '#8B5CF6'),
        ]),
        throwsStateError,
      );
    });
  });
}
