import 'package:flutter/foundation.dart';

import 'backend_client.dart';

// ============================================================================
// Data models (REQUIREMENTS §4) — all JSON-serializable.
// ============================================================================

class Person {
  Person({required this.id, required this.name, required this.avatar, required this.color});

  String id;
  String name;
  String avatar; // emoji
  String color; // hex, e.g. "#2563EB"

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        id: j['id'] as String,
        name: j['name'] as String,
        avatar: (j['avatar'] ?? '🙂') as String,
        color: (j['color'] ?? '#2563EB') as String,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'avatar': avatar, 'color': color};
}

class Group {
  Group({
    required this.id,
    required this.name,
    required this.emoji,
    required this.members,
    List<String>? admins,
  }) : admins = admins ?? (members.isEmpty ? [] : [members.first]);

  String id;
  String name;
  String emoji;
  List<String> members; // Person.id list
  List<String> admins; // Person.id list — group admins (subset of members)

  /// True when [personId] is a group admin. Legacy groups without an explicit
  /// admins list fall back to the first member, mirroring the backend's
  /// `isGroupAdmin`.
  bool isAdmin(String personId) {
    if (admins.isEmpty) {
      return members.isNotEmpty && members.first == personId;
    }
    return admins.contains(personId);
  }

  factory Group.fromJson(Map<String, dynamic> j) {
    final members = (j['members'] as List).cast<String>();
    final admins = (j['admins'] as List?)?.cast<String>() ??
        (members.isEmpty ? <String>[] : [members.first]);
    return Group(
      id: j['id'] as String,
      name: j['name'] as String,
      emoji: (j['emoji'] ?? '👥') as String,
      members: members,
      admins: admins,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'members': members,
        'admins': admins,
      };
}

/// A single audit-log entry on an expense (who did what, and when).
class ExpenseHistoryEntry {
  ExpenseHistoryEntry({required this.user, required this.action, required this.timestamp});

  final String user; // Person.id
  final String action; // e.g. "edited Dinner amount from 2500 to 3000"
  final DateTime timestamp;

  factory ExpenseHistoryEntry.fromJson(Map<String, dynamic> j) => ExpenseHistoryEntry(
        user: j['user'] as String,
        action: j['action'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
      );

  Map<String, dynamic> toJson() =>
      {'user': user, 'action': action, 'timestamp': timestamp.toIso8601String()};
}

/// A comment on an expense. Comments never affect balances.
class Comment {
  Comment({
    required this.id,
    required this.expenseId,
    required this.userId,
    required this.message,
    required this.timestamp,
  });

  final String id;
  final String expenseId;
  final String userId; // Person.id
  final String message;
  final DateTime timestamp;

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: (j['id'] ?? j['commentId']) as String,
        expenseId: j['expenseId'] as String,
        userId: j['userId'] as String,
        message: j['message'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'expenseId': expenseId,
        'userId': userId,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
      };
}

class Expense {
  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.participants,
    required this.category,
    required this.date,
    this.groupId,
    this.note,
    this.splitMethod = 'equal',
    Map<String, double>? splits,
    this.settled = false,
    String? createdBy,
    List<ExpenseHistoryEntry>? history,
    List<Comment>? comments,
  })  : splits = splits ?? {},
        createdBy = createdBy ?? paidBy,
        history = history ?? [],
        comments = comments ?? [];

  String id;
  String title;
  double amount;
  String paidBy; // Person.id
  List<String> participants; // Person.id list
  String? groupId; // null = non-group (friend) expense
  String category;
  DateTime date;
  String? note;
  String splitMethod; // 'equal' | 'amount' | 'percentage'
  Map<String, double> splits; // personId -> share
  bool settled;
  String createdBy; // Person.id of whoever created the expense
  List<ExpenseHistoryEntry> history;
  List<Comment> comments;

  /// Resolves a participant's share based on [splitMethod] (REQUIREMENTS §4.3).
  ///
  /// Equal splits are penny-accurate: the remainder cents that don't divide
  /// evenly are handed one-at-a-time to the first participants (largest-
  /// remainder), so the shares always sum back to the exact total — just like
  /// Splitwise. Without this, a $100 split 3 ways would leave a stray cent and
  /// the group would never reconcile to zero.
  double getParticipantShare(String personId) {
    if (!participants.contains(personId)) return 0;
    switch (splitMethod) {
      case 'amount':
        return splits[personId] ?? 0;
      case 'percentage':
        return amount * (splits[personId] ?? 0) / 100;
      case 'equal':
      default:
        if (participants.isEmpty) return 0;
        final totalCents = (amount * 100).round();
        final n = participants.length;
        final base = totalCents ~/ n;
        final remainder = totalCents - base * n; // cents to distribute
        final index = participants.indexOf(personId);
        final cents = base + (index < remainder ? 1 : 0);
        return cents / 100;
    }
  }

  /// Validates the split against [splitMethod] (business-logic spec). Returns a
  /// human-readable error, or null when valid. Mirrors the backend's
  /// `validateExpenseSplits`.
  String? validateSplits() {
    if (splitMethod == 'equal') return null;
    var total = 0.0;
    for (final id in participants) {
      total += splits[id] ?? 0;
    }
    if (splitMethod == 'amount' && (total - amount).abs() > 0.01) {
      return 'Exact amounts must add up to $amount (got $total)';
    }
    if (splitMethod == 'percentage' && (total - 100).abs() > 0.01) {
      return 'Percentages must add up to 100 (got $total)';
    }
    return null;
  }

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: j['id'] as String,
        title: j['title'] as String,
        amount: (j['amount'] as num).toDouble(),
        paidBy: j['paidBy'] as String,
        participants: (j['participants'] as List).cast<String>(),
        groupId: j['groupId'] as String?,
        category: (j['category'] ?? 'general') as String,
        date: DateTime.parse(j['date'] as String),
        note: j['note'] as String?,
        splitMethod: (j['splitMethod'] ?? 'equal') as String,
        splits: ((j['splits'] ?? {}) as Map)
            .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        settled: (j['settled'] ?? false) as bool,
        createdBy: (j['createdBy'] ?? j['paidBy']) as String,
        history: ((j['history'] ?? []) as List)
            .map((e) => ExpenseHistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        comments: ((j['comments'] ?? []) as List)
            .map((e) => Comment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'paidBy': paidBy,
        'participants': participants,
        'groupId': groupId,
        'category': category,
        'date': date.toIso8601String(),
        'note': note,
        'splitMethod': splitMethod,
        'splits': splits,
        'settled': settled,
        'createdBy': createdBy,
        'history': history.map((e) => e.toJson()).toList(),
        'comments': comments.map((e) => e.toJson()).toList(),
      };
}

class Settlement {
  Settlement({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.date,
    this.groupId,
  });

  String id;
  String? groupId; // null = direct friend settlement
  String from; // debtor Person.id
  String to; // creditor Person.id
  double amount;
  DateTime date;

  factory Settlement.fromJson(Map<String, dynamic> j) => Settlement(
        id: j['id'] as String,
        groupId: j['groupId'] as String?,
        from: j['from'] as String,
        to: j['to'] as String,
        amount: (j['amount'] as num).toDouble(),
        date: DateTime.parse(j['date'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'from': from,
        'to': to,
        'amount': amount,
        'date': date.toIso8601String(),
      };
}

class AppData {
  AppData({
    required this.me,
    required this.people,
    required this.groups,
    required this.expenses,
    required this.settlements,
  });

  String me; // current user's Person.id
  List<Person> people;
  List<Group> groups;
  List<Expense> expenses;
  List<Settlement> settlements;

  Person? personById(String id) {
    for (final p in people) {
      if (p.id == id) return p;
    }
    return null;
  }

  Group? groupById(String id) {
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        me: j['me'] as String,
        people: ((j['people'] ?? []) as List)
            .map((e) => Person.fromJson(e as Map<String, dynamic>))
            .toList(),
        groups: ((j['groups'] ?? []) as List)
            .map((e) => Group.fromJson(e as Map<String, dynamic>))
            .toList(),
        expenses: ((j['expenses'] ?? []) as List)
            .map((e) => Expense.fromJson(e as Map<String, dynamic>))
            .toList(),
        settlements: ((j['settlements'] ?? []) as List)
            .map((e) => Settlement.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'me': me,
        'people': people.map((e) => e.toJson()).toList(),
        'groups': groups.map((e) => e.toJson()).toList(),
        'expenses': expenses.map((e) => e.toJson()).toList(),
        'settlements': settlements.map((e) => e.toJson()).toList(),
      };
}

/// Net balance view relative to the signed-in user (REQUIREMENTS §4.6).
class BalanceSummary {
  BalanceSummary({required this.owed, required this.owe, required this.perPerson});

  final double owed; // total others owe me
  final double owe; // total I owe others
  final Map<String, double> perPerson; // personId -> net (positive = they owe me)

  double get net => owed - owe;
}

class DemoAccount {
  DemoAccount({
    required this.id,
    required this.displayName,
    required this.email,
    required this.avatar,
    required this.color,
    this.password = '',
  });

  final String id;
  final String displayName;
  final String email;
  final String password;
  final String avatar;
  final String color;

  factory DemoAccount.fromJson(Map<String, dynamic> j) => DemoAccount(
        id: j['id'] as String,
        displayName: (j['displayName'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        password: (j['password'] ?? '') as String,
        avatar: (j['avatar'] ?? '🙂') as String,
        color: (j['color'] ?? '#2563EB') as String,
      );
}

/// A directory entry returned by member search — someone who can sign in and
/// be added to groups/expenses (a demo account or a registered member).
class Member {
  Member({
    required this.id,
    required this.name,
    required this.avatar,
    required this.color,
    this.email = '',
  });

  final String id;
  final String name;
  final String avatar;
  final String color;
  final String email;

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        avatar: (j['avatar'] ?? '🙂') as String,
        color: (j['color'] ?? '#2563EB') as String,
        email: (j['email'] ?? '') as String,
      );

  /// The [Person] record to store in app state when this member is added.
  Person toPerson() =>
      Person(id: id, name: name, avatar: avatar, color: color);
}

// ============================================================================
// AppController — all business logic lives here, not in widgets (NFR-05).
// ============================================================================

class AppController extends ChangeNotifier {
  AppController({ClearSplitApi? api}) : _api = api ?? BackendClient();

  final ClearSplitApi _api;

  AppData? _state;
  DemoAccount? _activeAccount;
  String? _lastError;

  AppData? get state => _state;
  DemoAccount? get activeAccount => _activeAccount;
  bool get isSignedIn => _state != null && _activeAccount != null;
  String? get lastError => _lastError;
  String get myId => _state?.me ?? '';

  /// Name to show for [personId], rendering the signed-in user as "You"
  /// (Splitwise-style) and everyone else by their real name.
  String displayName(String personId) {
    if (personId == myId) return 'You';
    return _state?.personById(personId)?.name ?? 'Someone';
  }

  ClearSplitApi get api => _api;

  Future<List<DemoAccount>> fetchAccounts() => _api.fetchAccounts();

  Future<bool> signIn(String email, String password) async {
    try {
      final (account, state) = await _api.login(email, password);
      _activeAccount = account;
      _state = state;
      _lastError = null;
      notifyListeners();
      return true;
    } on BackendClientException catch (e) {
      _lastError = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Registers a new member and signs them straight in on success.
  Future<bool> register(String name, String email, String password) async {
    try {
      final (account, state) = await _api.register(name, email, password);
      _activeAccount = account;
      _state = state;
      _lastError = null;
      notifyListeners();
      return true;
    } on BackendClientException catch (e) {
      _lastError = e.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _api.logout();
    } on BackendClientException {
      // Logout is best-effort; clear local state regardless.
    }
    _state = null;
    _activeAccount = null;
    notifyListeners();
  }

  /// Persists the current state, replacing local state with the server's copy.
  /// On failure keeps the local mutation so the UI reflects last-known state
  /// (NFR-03) and surfaces the error.
  Future<void> _save() async {
    final state = _state;
    if (state == null) return;
    try {
      _state = await _api.saveState(state.me, state);
      _lastError = null;
    } on BackendClientException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }

  // ---- Expenses & groups -------------------------------------------------

  /// Adds an expense. Rejects invalid splits (business-logic spec). Group
  /// expenses fan out to all members via the backend; friend expenses persist
  /// to the user's own state.
  Future<void> addExpense(Expense expense) async {
    final state = _state;
    if (state == null) return;
    final err = expense.validateSplits();
    if (err != null) throw ArgumentError(err);

    expense.createdBy = myId;
    if (expense.history.isEmpty) {
      expense.history.add(ExpenseHistoryEntry(
        user: myId,
        action: 'added ${expense.title}',
        timestamp: DateTime.now(),
      ));
    }

    final groupId = expense.groupId;
    try {
      if (groupId != null) {
        _state = await _api.createGroupExpense(groupId, myId, expense);
      } else {
        state.expenses.add(expense);
        _state = await _api.saveState(state.me, state);
      }
      _lastError = null;
    } on BackendClientException catch (e) {
      // Keep the local copy so the UI reflects last-known state (NFR-03).
      if (!state.expenses.any((x) => x.id == expense.id)) {
        state.expenses.add(expense);
      }
      _lastError = e.message;
    }
    notifyListeners();
  }

  /// True when the signed-in user is an admin of group [groupId] (mirrors the
  /// backend's `isGroupAdmin`).
  bool amIAdmin(String groupId) => isAdmin(groupId, myId);

  /// True when [personId] is an admin of group [groupId].
  bool isAdmin(String groupId, String personId) {
    final group = _state?.groupById(groupId);
    return group?.isAdmin(personId) ?? false;
  }

  /// True when the signed-in user may edit/delete [expense]: the creator, or a
  /// group admin (mirroring the backend's `canModifyExpense`).
  bool canModifyExpense(Expense expense) {
    final state = _state;
    if (state == null) return false;
    if (myId == expense.createdBy) return true;
    final groupId = expense.groupId;
    if (groupId == null) return false;
    return amIAdmin(groupId);
  }

  String _describeChange(Expense before, Expense after) {
    final parts = <String>[];
    if (before.title != after.title) {
      parts.add('title from "${before.title}" to "${after.title}"');
    }
    if (before.amount != after.amount) {
      parts.add('amount from ${before.amount} to ${after.amount}');
    }
    if (before.category != after.category) {
      parts.add('category from ${before.category} to ${after.category}');
    }
    if (before.splitMethod != after.splitMethod) {
      parts.add('split from ${before.splitMethod} to ${after.splitMethod}');
    }
    return parts.isEmpty
        ? 'edited ${after.title}'
        : 'edited ${after.title} ${parts.join(', ')}';
  }

  /// Edits an expense (creator/admin only, validated), recording a history
  /// entry. [updated] carries the new field values for the same expense id.
  Future<void> editExpense(Expense updated) async {
    final state = _state;
    if (state == null) return;
    final idx = state.expenses.indexWhere((e) => e.id == updated.id);
    if (idx < 0) return;
    final original = state.expenses[idx];
    if (!canModifyExpense(original)) {
      throw StateError('Only the expense creator or a group admin can edit this expense');
    }
    final err = updated.validateSplits();
    if (err != null) throw ArgumentError(err);

    final groupId = updated.groupId;
    try {
      if (groupId != null) {
        final updates = {
          'title': updated.title,
          'amount': updated.amount,
          'paidBy': updated.paidBy,
          'participants': updated.participants,
          'category': updated.category,
          'date': updated.date.toIso8601String(),
          'note': updated.note,
          'splitMethod': updated.splitMethod,
          'splits': updated.splits,
        };
        _state = await _api.editGroupExpense(groupId, updated.id, myId, updates);
      } else {
        updated
          ..createdBy = original.createdBy
          ..comments = original.comments
          ..history = [
            ...original.history,
            ExpenseHistoryEntry(
              user: myId,
              action: _describeChange(original, updated),
              timestamp: DateTime.now(),
            ),
          ];
        state.expenses[idx] = updated;
        _state = await _api.saveState(state.me, state);
      }
      _lastError = null;
    } on BackendClientException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }

  /// Deletes an expense (creator/admin only). Group expenses fan out.
  Future<void> deleteExpense(Expense expense) async {
    final state = _state;
    if (state == null) return;
    if (!canModifyExpense(expense)) {
      throw StateError('Only the expense creator or a group admin can delete this expense');
    }
    final groupId = expense.groupId;
    try {
      if (groupId != null) {
        _state = await _api.deleteGroupExpense(groupId, expense.id, myId);
      } else {
        state.expenses.removeWhere((e) => e.id == expense.id);
        _state = await _api.saveState(state.me, state);
      }
      _lastError = null;
    } on BackendClientException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }

  /// Adds a comment to an expense (never affects balances). Group expenses fan
  /// out so every member sees the comment.
  Future<void> addComment(Expense expense, String message) async {
    final state = _state;
    final text = message.trim();
    if (state == null || text.isEmpty) return;
    final groupId = expense.groupId;
    try {
      if (groupId != null) {
        _state = await _api.addExpenseComment(groupId, expense.id, myId, text);
      } else {
        final idx = state.expenses.indexWhere((e) => e.id == expense.id);
        if (idx >= 0) {
          state.expenses[idx].comments.add(Comment(
            id: 'cmt-${DateTime.now().microsecondsSinceEpoch}',
            expenseId: expense.id,
            userId: myId,
            message: text,
            timestamp: DateTime.now(),
          ));
        }
        _state = await _api.saveState(state.me, state);
      }
      _lastError = null;
    } on BackendClientException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }

  /// Creates a group, optionally seeding it with directory [members] (people
  /// found via search). Any new people are added to local state, then the
  /// membership is fanned out so each member converges on the group.
  Future<Group> createGroup(
    String name,
    String emoji, {
    List<Member> members = const [],
  }) async {
    final state = _state;
    if (state == null) {
      throw StateError('Not signed in');
    }
    for (final m in members) {
      if (!state.people.any((p) => p.id == m.id)) {
        state.people.add(m.toPerson());
      }
    }
    final memberIds = <String>{state.me, ...members.map((m) => m.id)}.toList();
    final group = Group(
      id: 'grp-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      emoji: emoji,
      members: memberIds,
      admins: [state.me], // the creator becomes the group admin (GRP-01)
    );
    state.groups.add(group);
    notifyListeners();
    await _save();
    await _syncGroup(group.id);
    return group;
  }

  /// Adds an existing person to a group (admin only). Group access changes are
  /// authorized and fanned out by the backend.
  Future<void> addMemberToGroup(String groupId, String personId) async {
    final state = _state;
    final group = state?.groupById(groupId);
    if (state == null || group == null || group.members.contains(personId)) {
      return;
    }
    final person = state.personById(personId);
    if (person == null) return;
    await addMembersToGroup(groupId, [
      Member(
        id: person.id,
        name: person.name,
        avatar: person.avatar,
        color: person.color,
      ),
    ]);
  }

  /// Adds directory [members] to a group (admin only), one fan-out per member.
  /// Throws [StateError] when the signed-in user isn't a group admin.
  Future<void> addMembersToGroup(String groupId, List<Member> members) async {
    final state = _state;
    final group = state?.groupById(groupId);
    if (state == null || group == null || members.isEmpty) return;
    if (!amIAdmin(groupId)) {
      throw StateError('Only a group admin can add members');
    }
    try {
      for (final m in members) {
        if (group.members.contains(m.id)) continue;
        _state = await _api.addGroupMember(groupId, myId, m);
      }
      _lastError = null;
    } on BackendClientException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }

  /// Net balance (positive = they are owed) for [personId] within [groupId].
  /// Used to block removing a member who isn't settled up.
  double groupMemberBalance(String groupId, String personId) {
    final state = _state;
    if (state == null) return 0;
    return _dollars(_rawBalances(state, groupId: groupId)[personId] ?? 0);
  }

  /// Removes [memberId] from a group (admin only). Rejects up front when the
  /// member still has an outstanding balance in the group or is the last admin;
  /// the backend enforces the same rules authoritatively.
  Future<void> removeMemberFromGroup(String groupId, String memberId) async {
    final group = _state?.groupById(groupId);
    if (group == null || !group.members.contains(memberId)) return;
    if (!amIAdmin(groupId)) {
      throw StateError('Only a group admin can remove members');
    }
    if (groupMemberBalance(groupId, memberId) != 0) {
      throw StateError(
          'Member must be settled up in this group before they can be removed');
    }
    if (group.isAdmin(memberId) && group.admins.length <= 1) {
      throw StateError(
          'Promote another member to admin before removing the last admin');
    }
    try {
      _state = await _api.removeGroupMember(groupId, myId, memberId);
      _lastError = null;
    } on BackendClientException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }

  /// Promotes [memberId] to admin (admin only).
  Future<void> assignAdmin(String groupId, String memberId) async {
    final group = _state?.groupById(groupId);
    if (group == null || !group.members.contains(memberId)) return;
    if (!amIAdmin(groupId)) {
      throw StateError('Only a group admin can assign roles');
    }
    try {
      _state = await _api.assignGroupAdmin(groupId, myId, memberId);
      _lastError = null;
    } on BackendClientException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }

  /// Revokes [memberId]'s admin role (admin only). Rejects up front when it
  /// would leave the group with no admin.
  Future<void> revokeAdmin(String groupId, String memberId) async {
    final group = _state?.groupById(groupId);
    if (group == null) return;
    if (!amIAdmin(groupId)) {
      throw StateError('Only a group admin can assign roles');
    }
    if (group.isAdmin(memberId) && group.admins.length <= 1) {
      throw StateError('A group must keep at least one admin');
    }
    try {
      _state = await _api.revokeGroupAdmin(groupId, myId, memberId);
      _lastError = null;
    } on BackendClientException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }

  /// Ensures [member] exists as a person in local state (so they can be picked
  /// as a participant on a non-group expense), persisting if newly added.
  Future<void> ensurePerson(Member member) async {
    final state = _state;
    if (state == null || state.people.any((p) => p.id == member.id)) return;
    state.people.add(member.toPerson());
    notifyListeners();
    await _save();
  }

  /// Searches the member directory, excluding the signed-in user.
  Future<List<Member>> searchMembers(String query) async {
    try {
      final results = await _api.searchMembers(query, excludeId: myId);
      _lastError = null;
      return results;
    } on BackendClientException catch (e) {
      _lastError = e.message;
      return const [];
    }
  }

  /// Best-effort fan-out of a group's membership to all members' states. The
  /// local state is already saved, so a failure here only skips propagation.
  Future<void> _syncGroup(String groupId) async {
    try {
      _state = await _api.syncGroup(groupId, myId);
      _lastError = null;
    } on BackendClientException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }

  // ---- Balances (pure; mirror backend balances.js) -----------------------

  static int _cents(double d) => (d * 100).round();
  static double _dollars(int cents) => cents / 100;

  /// Pairwise net in cents between [me] and every other person.
  Map<String, int> _pairwiseBalances(AppData state) {
    final me = state.me;
    final out = <String, int>{};
    void add(String id, int c) => out[id] = (out[id] ?? 0) + c;

    for (final e in state.expenses) {
      if (e.settled) continue;
      if (e.paidBy == me) {
        for (final p in e.participants) {
          if (p == me) continue;
          add(p, _cents(e.getParticipantShare(p)));
        }
      } else if (e.participants.contains(me)) {
        add(e.paidBy, -_cents(e.getParticipantShare(me)));
      }
    }
    for (final s in state.settlements) {
      if (s.from == me) {
        add(s.to, _cents(s.amount));
      } else if (s.to == me) {
        add(s.from, -_cents(s.amount));
      }
    }
    return out;
  }

  /// Multilateral net ledger in cents, optionally filtered to a group.
  Map<String, int> _rawBalances(AppData state, {String? groupId}) {
    final out = <String, int>{};
    void add(String id, int c) => out[id] = (out[id] ?? 0) + c;

    for (final e in state.expenses) {
      if (e.settled) continue;
      if (groupId != null && e.groupId != groupId) continue;
      add(e.paidBy, _cents(e.amount));
      for (final p in e.participants) {
        add(p, -_cents(e.getParticipantShare(p)));
      }
    }
    for (final s in state.settlements) {
      if (groupId != null && s.groupId != groupId) continue;
      add(s.from, _cents(s.amount));
      add(s.to, -_cents(s.amount));
    }
    return out;
  }

  BalanceSummary computeBalances() {
    final state = _state;
    if (state == null) {
      return BalanceSummary(owed: 0, owe: 0, perPerson: {});
    }
    final raw = _pairwiseBalances(state);
    final perPerson = <String, double>{};
    int owed = 0;
    int owe = 0;
    for (final person in state.people) {
      if (person.id == state.me) continue;
      final c = raw[person.id] ?? 0;
      perPerson[person.id] = _dollars(c);
      if (c > 0) {
        owed += c;
      } else if (c < 0) {
        owe += -c;
      }
    }
    return BalanceSummary(
      owed: _dollars(owed),
      owe: _dollars(owe),
      perPerson: perPerson,
    );
  }

  /// Net balance with a single friend (positive = they owe me).
  double balanceWithFriend(String personId) =>
      computeBalances().perPerson[personId] ?? 0;

  /// Greedy debt simplification for a group (REQUIREMENTS §11).
  /// Returns { debtorId: [(to, amount), ...] }.
  Map<String, List<({String to, double amount})>> computeGroupSettlements(
      String groupId) {
    final state = _state;
    if (state == null) return {};
    final balances = _rawBalances(state, groupId: groupId);

    final creditors = <({String id, int cents})>[];
    final debtors = <({String id, int cents})>[];
    balances.forEach((id, c) {
      if (c > 0) {
        creditors.add((id: id, cents: c));
      } else if (c < 0) {
        debtors.add((id: id, cents: -c));
      }
    });
    creditors.sort((a, b) => b.cents - a.cents);
    debtors.sort((a, b) => b.cents - a.cents);

    final payments = <String, List<({String to, double amount})>>{};
    var ci = 0;
    var di = 0;
    var creditLeft = creditors.map((e) => e.cents).toList();
    var debtLeft = debtors.map((e) => e.cents).toList();
    while (ci < creditors.length && di < debtors.length) {
      final transfer =
          creditLeft[ci] < debtLeft[di] ? creditLeft[ci] : debtLeft[di];
      if (transfer > 0) {
        payments
            .putIfAbsent(debtors[di].id, () => [])
            .add((to: creditors[ci].id, amount: _dollars(transfer)));
      }
      creditLeft[ci] -= transfer;
      debtLeft[di] -= transfer;
      if (creditLeft[ci] == 0) ci++;
      if (debtLeft[di] == 0) di++;
    }
    return payments;
  }

  /// Total tracked spend for a group (sum of all its expense amounts).
  double groupTotal(String groupId) {
    final state = _state;
    if (state == null) return 0;
    var cents = 0;
    for (final e in state.expenses) {
      if (e.groupId == groupId) cents += _cents(e.amount);
    }
    return _dollars(cents);
  }

  // ---- Settlements (backend fan-out) -------------------------------------

  Future<void> markSettled(Expense expense) async {
    final state = _state;
    if (state == null) return;
    final groupId = expense.groupId;
    try {
      if (groupId != null) {
        _state = await _api.settleExpense(groupId, expense.id, state.me);
      } else {
        // Non-group expense: settle locally and persist own state.
        expense.settled = true;
        _state = await _api.saveState(state.me, state);
      }
      _lastError = null;
    } on BackendClientException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }

  /// Records a payment. Rejects non-positive amounts (SET-05). Group settlements
  /// fan out via the backend; friend settlements persist to own state.
  Future<void> recordSettlement(
    String? groupId, {
    required String from,
    required String to,
    required double amount,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Settlement amount must be greater than zero');
    }
    final state = _state;
    if (state == null) return;
    final settlement = Settlement(
      id: 'set-${DateTime.now().microsecondsSinceEpoch}',
      groupId: groupId,
      from: from,
      to: to,
      amount: amount,
      date: DateTime.now(),
    );
    try {
      if (groupId != null) {
        _state = await _api.recordSettlement(groupId, state.me, settlement);
      } else {
        state.settlements.add(settlement);
        _state = await _api.saveState(state.me, state);
      }
      _lastError = null;
    } on BackendClientException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }

  /// Settles every outstanding debt in a group in one action (SET-03).
  Future<void> settleAllForGroup(String groupId) async {
    final payments = computeGroupSettlements(groupId);
    for (final entry in payments.entries) {
      for (final p in entry.value) {
        await recordSettlement(
          groupId,
          from: entry.key,
          to: p.to,
          amount: p.amount,
        );
      }
    }
  }

  // ---- Profile -----------------------------------------------------------

  Future<void> updateProfile({String? name, String? avatar, String? color}) async {
    final state = _state;
    if (state == null) return;
    try {
      _state = await _api.updateProfile(
        state.me,
        displayName: name,
        avatar: avatar,
        color: color,
      );
      _lastError = null;
    } on BackendClientException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }

  /// Re-seeds the signed-in account to the initial demo data (REQUIREMENTS §9).
  Future<void> resetCurrentAccount() async {
    final state = _state;
    if (state == null) return;
    try {
      _state = await _api.resetState(state.me);
      _lastError = null;
    } on BackendClientException catch (e) {
      _lastError = e.message;
    }
    notifyListeners();
  }
}
