import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/sheets.dart';
import 'theme.dart';
import 'widgets/common.dart';

/// Main shell: 4-tab bottom nav (Friends · Groups · Activity · Account) with a
/// center-docked "Add expense" FAB (REQUIREMENTS §8).
class ClearSplitHome extends StatefulWidget {
  const ClearSplitHome({super.key, required this.controller});

  final AppController controller;

  @override
  State<ClearSplitHome> createState() => _ClearSplitHomeState();
}

class _ClearSplitHomeState extends State<ClearSplitHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final screens = [
          FriendsScreen(controller: c),
          GroupsScreen(controller: c),
          ActivityScreen(controller: c),
          AccountScreen(controller: c),
        ];
        return Scaffold(
          extendBody: true,
          body: SafeArea(bottom: false, child: screens[_tab]),
          floatingActionButton: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.brand.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => showAddExpenseSheet(context, c),
                child: const Icon(Icons.add, color: Colors.white, size: 30),
              ),
            ),
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerDocked,
          bottomNavigationBar: BottomAppBar(
            color: Colors.white,
            elevation: 12,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            surfaceTintColor: Colors.transparent,
            shape: const CircularNotchedRectangle(),
            notchMargin: 9,
            height: 68,
            padding: EdgeInsets.zero,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(Icons.people_outline, Icons.people, 'Friends', 0),
                _navItem(Icons.groups_outlined, Icons.groups, 'Groups', 1),
                const SizedBox(width: 56), // notch gap
                _navItem(Icons.receipt_long_outlined, Icons.receipt_long,
                    'Activity', 2),
                _navItem(Icons.person_outline, Icons.person, 'Account', 3),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _navItem(IconData icon, IconData active, String label, int index) {
    final selected = _tab == index;
    final color =
        selected ? AppTheme.brand : Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? active : icon, color: color, size: 24),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Friends tab (FRND-01..03)
// ============================================================================

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final data = controller.state!;
    final summary = controller.computeBalances();
    final friends =
        data.people.where((p) => p.id != controller.myId).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        const _ScreenTitle('Friends', subtitle: 'Your shared balances'),
        OverallBalanceCard(summary: summary),
        const _SectionHeader('FRIENDS'),
        if (friends.isEmpty)
          const _EmptyState(
            icon: Icons.people_outline,
            message: 'No friends yet.',
          )
        else
          SoftCard(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < friends.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 72),
                  ListTile(
                    leading: PersonAvatar(person: friends[i], radius: 22),
                    title: Text(friends[i].name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: BalanceLabel(
                        net: summary.perPerson[friends[i].id] ?? 0),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => FriendDetailScreen(
                            controller: controller, friendId: friends[i].id),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// Groups tab (GRP-03)
// ============================================================================

class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final data = controller.state!;
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Groups',
                      style: Theme.of(context).textTheme.headlineSmall),
                  Text('Shared trips & households',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.inkSoft)),
                ],
              ),
              FilledButton.tonalIcon(
                onPressed: () => showCreateGroupSheet(context, controller),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (data.groups.isEmpty)
          const _EmptyState(
            icon: Icons.groups_outlined,
            message: 'No groups yet. Create one!',
          )
        else
          ...data.groups.map((g) {
            final total = controller.groupTotal(g.id);
            return SoftCard(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      GroupDetailScreen(controller: controller, groupId: g.id),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: AppTheme.brandGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(g.emoji, style: const TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(
                          '${g.members.length} members · ${money(total)} tracked',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.inkSoft),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppTheme.inkSoft),
                ],
              ),
            );
          }),
      ],
    );
  }
}

// ============================================================================
// Activity tab (ACT-01, ACT-02)
// ============================================================================

class _ActivityEntry {
  _ActivityEntry({required this.date, required this.build});
  final DateTime date;
  final Widget Function(BuildContext) build;
}

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final data = controller.state!;
    final me = controller.myId;

    final entries = <_ActivityEntry>[];

    // Expense events come from the append-only activity log (added / edited /
    // deleted / settled), so edits and deletions are visible — not just the
    // current amount — and a deleted expense still leaves a trace.
    for (final a in data.activity) {
      entries.add(_ActivityEntry(
        date: a.timestamp,
        build: (ctx) => _activityTile(ctx, data, me, a),
      ));
    }

    for (final s in data.settlements) {
      final from = data.personById(s.from);
      final to = data.personById(s.to);
      final actor = s.from == me ? 'You' : (from?.name ?? 'Someone');
      final target = s.to == me ? 'you' : (to?.name ?? 'someone');
      final double effect =
          s.from == me ? s.amount : (s.to == me ? -s.amount : 0);
      entries.add(_ActivityEntry(
        date: s.date,
        build: (ctx) => ListTile(
          leading:
              _CircleIcon(icon: Icons.payments_outlined, color: AppTheme.positive),
          title: Text('$actor paid $target ${money(s.amount)}'),
          subtitle: const Text('Settlement'),
          trailing: _effectLabel(ctx, effect),
        ),
      ));
    }

    entries.sort((a, b) => b.date.compareTo(a.date));

    final now = DateTime.now();
    bool isToday(DateTime d) =>
        d.year == now.year && d.month == now.month && d.day == now.day;
    final today = entries.where((e) => isToday(e.date)).toList();
    final earlier = entries.where((e) => !isToday(e.date)).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        const _ScreenTitle('Activity', subtitle: 'Recent expenses & payments'),
        if (today.isNotEmpty) ...[
          const _SectionHeader('TODAY'),
          _activityGroup(context, today),
        ],
        if (earlier.isNotEmpty) ...[
          const _SectionHeader('EARLIER'),
          _activityGroup(context, earlier),
        ],
        if (entries.isEmpty)
          const _EmptyState(
            icon: Icons.receipt_long_outlined,
            message: 'No activity yet.',
          ),
      ],
    );
  }

  Expense? _expenseById(AppData data, String? id) {
    if (id == null) return null;
    for (final e in data.expenses) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Renders one activity-log entry, branching on the event type so an edit,
  /// delete, or settle reads differently from a plain "added".
  Widget _activityTile(
      BuildContext context, AppData data, String me, ActivityEvent a) {
    final actorPerson = data.personById(a.actor);
    final actor = a.actor == me ? 'You' : (actorPerson?.name ?? 'Someone');
    final title = a.title ?? 'an expense';
    final live = _expenseById(data, a.expenseId);

    switch (a.type) {
      case ActivityEvent.typeAdded:
        final myShare = live?.getParticipantShare(me) ?? 0;
        final double effect = live == null
            ? 0
            : (live.paidBy == me ? (live.amount - myShare) : -myShare);
        return ListTile(
          leading: actorPerson == null
              ? _CircleIcon(icon: Icons.receipt, color: AppTheme.brand)
              : PersonAvatar(person: actorPerson, radius: 22),
          title: Text('$actor added "$title"'),
          subtitle: Text(live != null
              ? '${categoryEmoji(live.category)} ${money(live.amount)}${live.settled ? ' · settled' : ''}'
              : (a.amount != null ? money(a.amount!) : 'Expense')),
          trailing: live == null ? null : _effectLabel(context, effect),
        );
      case ActivityEvent.typeEdited:
        return ListTile(
          leading:
              _CircleIcon(icon: Icons.edit_outlined, color: AppTheme.brand),
          title: Text('$actor edited "$title"'),
          subtitle:
              Text(a.description.isEmpty ? 'Updated expense' : a.description),
        );
      case ActivityEvent.typeDeleted:
        return ListTile(
          leading:
              _CircleIcon(icon: Icons.delete_outline, color: AppTheme.negative),
          title: Text('$actor deleted "$title"'),
          subtitle:
              Text(a.amount != null ? money(a.amount!) : 'Expense removed'),
        );
      case ActivityEvent.typeSettled:
        return ListTile(
          leading: _CircleIcon(
              icon: Icons.check_circle_outline, color: AppTheme.positive),
          title: Text('$actor marked "$title" settled'),
          subtitle: const Text('Expense settled'),
        );
      default:
        return ListTile(
          leading: _CircleIcon(icon: Icons.history, color: AppTheme.brand),
          title: Text('$actor updated "$title"'),
          subtitle: a.description.isEmpty ? null : Text(a.description),
        );
    }
  }

  Widget _activityGroup(BuildContext context, List<_ActivityEntry> items) {
    return SoftCard(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 72),
            items[i].build(context),
          ],
        ],
      ),
    );
  }

  Widget _effectLabel(BuildContext context, double effect) {
    if (effect.abs() < 0.005) return const SizedBox.shrink();
    final positive = effect > 0;
    return Text(
      '${positive ? '+' : '-'}${money(effect)}',
      style: TextStyle(
        color: positive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

// ============================================================================
// Account tab (PROF, AUTH-05)
// ============================================================================

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final me = controller.state!.personById(controller.myId)!;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        const _ScreenTitle('Account'),
        SoftCard(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              PersonAvatar(person: me, radius: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(me.name, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(controller.activeAccount?.email ?? '',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppTheme.inkSoft)),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(controller: controller),
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Edit'),
              ),
            ],
          ),
        ),
        const _SectionHeader('PREFERENCES'),
        _settingsCard([
          _settingsTile(
            context,
            icon: Icons.edit_outlined,
            title: 'Edit profile',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EditProfileScreen(controller: controller),
              ),
            ),
          ),
          _settingsTile(context,
              icon: Icons.notifications_outlined, title: 'Notifications'),
          _settingsTile(context,
              icon: Icons.payment_outlined, title: 'Payment methods'),
        ]),
        const _SectionHeader('ACCOUNT'),
        _settingsCard([
          _settingsTile(
            context,
            icon: Icons.restart_alt,
            title: 'Reset demo data',
            showChevron: false,
            onTap: () => _confirmReset(context),
          ),
          _settingsTile(
            context,
            icon: Icons.logout,
            title: 'Sign out',
            color: theme.colorScheme.error,
            showChevron: false,
            onTap: controller.signOut,
          ),
        ]),
      ],
    );
  }

  Widget _settingsCard(List<Widget> tiles) {
    return SoftCard(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            tiles[i],
          ],
        ],
      ),
    );
  }

  Widget _settingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    VoidCallback? onTap,
    Color? color,
    bool showChevron = true,
  }) {
    final c = color ?? AppTheme.ink;
    return ListTile(
      leading: Icon(icon, color: c),
      title: Text(title,
          style: TextStyle(color: c, fontWeight: FontWeight.w600)),
      trailing: showChevron
          ? Icon(Icons.chevron_right, color: AppTheme.inkSoft)
          : null,
      onTap: onTap,
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset demo data?'),
        content: const Text(
            'This restores your account to the original seeded expenses and groups.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed ?? false) await controller.resetCurrentAccount();
  }
}

// ============================================================================
// Friend detail (FRND-04..06)
// ============================================================================

class FriendDetailScreen extends StatelessWidget {
  const FriendDetailScreen({
    super.key,
    required this.controller,
    required this.friendId,
  });

  final AppController controller;
  final String friendId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final data = controller.state!;
        final friend = data.personById(friendId)!;
        final me = controller.myId;
        final net = controller.balanceWithFriend(friendId);

        // Expenses + settlements shared with this friend.
        final expenses = data.expenses.where((e) {
          final both =
              e.participants.contains(me) && e.participants.contains(friendId);
          return both && (e.paidBy == me || e.paidBy == friendId);
        }).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final settlements = data.settlements
            .where((s) =>
                (s.from == me && s.to == friendId) ||
                (s.from == friendId && s.to == me))
            .toList();

        return Scaffold(
          appBar: AppBar(title: Text(friend.name)),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              SoftCard(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        PersonAvatar(person: friend, radius: 28),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(friend.name,
                              style: Theme.of(context).textTheme.titleLarge),
                        ),
                        BalanceLabel(net: net),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => showAddExpenseSheet(
                                context, controller,
                                friendId: friendId),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add expense'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => showSettleUpSheet(
                                context, controller,
                                friendId: friendId),
                            icon: const Icon(Icons.payments_outlined, size: 18),
                            label: const Text('Settle up'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const _SectionHeader('SHARED EXPENSES'),
              if (expenses.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('No shared expenses yet.'),
                )
              else
                SoftCard(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < expenses.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 72),
                        _ExpenseTile(
                            controller: controller, expense: expenses[i]),
                      ],
                    ],
                  ),
                ),
              if (settlements.isNotEmpty) ...[
                const _SectionHeader('PAYMENTS'),
                SoftCard(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < settlements.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 72),
                        Builder(builder: (_) {
                          final s = settlements[i];
                          final youPaid = s.from == me;
                          return ListTile(
                            leading: _CircleIcon(
                                icon: Icons.payments_outlined,
                                color: AppTheme.positive),
                            title: Text(youPaid
                                ? 'You paid ${friend.name} ${money(s.amount)}'
                                : '${friend.name} paid you ${money(s.amount)}'),
                            subtitle:
                                Text(s.date.toString().split(' ').first),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// Group detail (GRP-03, BAL-04, SET-01/03)
// ============================================================================

class GroupDetailScreen extends StatelessWidget {
  const GroupDetailScreen({
    super.key,
    required this.controller,
    required this.groupId,
  });

  final AppController controller;
  final String groupId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final data = controller.state!;
        final group = data.groupById(groupId);
        if (group == null) {
          return const Scaffold(body: Center(child: Text('Group not found')));
        }
        final theme = Theme.of(context);
        final total = controller.groupTotal(groupId);
        final payments = controller.computeGroupSettlements(groupId);
        final groupExpenses =
            data.expenses.where((e) => e.groupId == groupId).toList()
              ..sort((a, b) => b.date.compareTo(a.date));

        return Scaffold(
          appBar: AppBar(
            title: Text('${group.emoji} ${group.name}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.group_add),
                tooltip: 'Manage members',
                onPressed: () =>
                    showManageMembersSheet(context, controller, group),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.brand.withValues(alpha: 0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total tracked spend',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 6),
                    Text(money(total),
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        )),
                  ],
                ),
              ),
              const _SectionHeader('MEMBER BALANCES'),
              SoftCard(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < group.members.length; i++) ...[
                      if (i > 0) const Divider(height: 1, indent: 72),
                      Builder(builder: (_) {
                        final id = group.members[i];
                        final p = data.personById(id)!;
                        final isMe = id == controller.myId;
                        final net =
                            _memberGroupNet(data, controller, groupId, id);
                        return ListTile(
                          leading: PersonAvatar(person: p, radius: 22),
                          title: Text(isMe ? 'You' : p.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          trailing: BalanceLabel(
                              net: net, compact: true, isSelf: isMe),
                        );
                      }),
                    ],
                  ],
                ),
              ),
              _SimplifySection(
                controller: controller,
                groupId: groupId,
                payments: payments,
              ),
              const _SectionHeader('EXPENSES'),
              if (groupExpenses.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('No expenses in this group yet.'),
                )
              else
                SoftCard(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < groupExpenses.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 72),
                        _ExpenseTile(
                            controller: controller,
                            expense: groupExpenses[i]),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      showAddExpenseSheet(context, controller, group: group),
                  icon: const Icon(Icons.add),
                  label: const Text('Add group expense'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  /// Member's net position within a single group (BAL-04).
  static double _memberGroupNet(
      AppData data, AppController controller, String groupId, String id) {
    var cents = 0;
    for (final e in data.expenses) {
      if (e.groupId != groupId || e.settled) continue;
      if (e.paidBy == id) cents += (e.amount * 100).round();
      cents -= (e.getParticipantShare(id) * 100).round();
    }
    for (final s in data.settlements) {
      if (s.groupId != groupId) continue;
      if (s.from == id) cents += (s.amount * 100).round();
      if (s.to == id) cents -= (s.amount * 100).round();
    }
    return cents / 100;
  }
}

/// "Simplify debts" + "settle all" section (SET-01, SET-03).
class _SimplifySection extends StatelessWidget {
  const _SimplifySection({
    required this.controller,
    required this.groupId,
    required this.payments,
  });

  final AppController controller;
  final String groupId;
  final Map<String, List<({String to, double amount})>> payments;

  @override
  Widget build(BuildContext context) {
    final flat = <({String from, String to, double amount})>[];
    payments.forEach((from, list) {
      for (final p in list) {
        flat.add((from: from, to: p.to, amount: p.amount));
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('SIMPLIFY DEBTS'),
        if (flat.isEmpty)
          SoftCard(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                _CircleIcon(
                    icon: Icons.celebration_outlined, color: AppTheme.positive),
                const SizedBox(width: 14),
                const Expanded(
                    child: Text('Everyone is settled up 🎉',
                        style: TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
          )
        else
          SoftCard(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                ...flat.map((p) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.arrow_circle_right_outlined,
                            color: AppTheme.brand, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${controller.displayName(p.from)} → ${controller.displayName(p.to)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(money(p.amount),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => controller.settleAllForGroup(groupId),
                    icon: const Icon(Icons.done_all),
                    label: const Text('Settle all debts'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Reusable expense list row (EXP-06) with a settle action.
class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.controller, required this.expense});

  final AppController controller;
  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final data = controller.state!;
    final payer = data.personById(expense.paidBy);
    return ListTile(
      onTap: () => showExpenseDetailSheet(context, controller, expense),
      leading: payer == null
          ? _CircleIcon(icon: Icons.receipt, color: AppTheme.brand)
          : PersonAvatar(person: payer, radius: 22),
      title: Text(expense.title,
          style: TextStyle(
            decoration: expense.settled ? TextDecoration.lineThrough : null,
          )),
      subtitle: Text(
          '${categoryEmoji(expense.category)} ${payer?.name ?? '?'} paid · ${expense.date.toString().split(' ').first}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(money(expense.amount),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          if (expense.settled)
            const Text('settled', style: TextStyle(fontSize: 11))
          else
            InkWell(
              onTap: () => controller.markSettled(expense),
              child: Text('mark settled',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.primary)),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Small shared widgets
// ============================================================================

class _ScreenTitle extends StatelessWidget {
  const _ScreenTitle(this.title, {this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppTheme.inkSoft)),
            ),
        ],
      ),
    );
  }
}

/// A rounded, tinted icon badge — used where a list row has no avatar.
class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 22),
    );
  }
}

/// Friendly empty-state placeholder with an icon and message.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: AppTheme.brand),
          ),
          const SizedBox(height: 16),
          Text(message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.inkSoft)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
              letterSpacing: 1,
            ),
      ),
    );
  }
}
