import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/member_picker.dart';

// ============================================================================
// Public entry points (REQUIREMENTS §8 modal sheets).
// ============================================================================

Future<void> showAddExpenseSheet(
  BuildContext context,
  AppController controller, {
  Group? group,
  String? friendId,
  Expense? existing,
}) {
  return _showSheet(
    context,
    AddExpenseSheet(
      controller: controller,
      group: group,
      friendId: friendId,
      existing: existing,
    ),
  );
}

/// Opens an expense's detail view: history, comments, and (for the creator or a
/// group admin) edit/delete actions.
Future<void> showExpenseDetailSheet(
  BuildContext context,
  AppController controller,
  Expense expense,
) {
  return _showSheet(
    context,
    ExpenseDetailSheet(controller: controller, expenseId: expense.id),
  );
}

Future<void> showCreateGroupSheet(BuildContext context, AppController controller) {
  return _showSheet(context, CreateGroupSheet(controller: controller));
}

Future<void> showManageMembersSheet(
  BuildContext context,
  AppController controller,
  Group group,
) {
  return _showSheet(
    context,
    ManageMembersSheet(controller: controller, group: group),
  );
}

Future<void> showSettleUpSheet(
  BuildContext context,
  AppController controller, {
  String? groupId,
  String? friendId,
}) {
  return _showSheet(
    context,
    SettleUpSheet(controller: controller, groupId: groupId, friendId: friendId),
  );
}

Future<void> _showSheet(BuildContext context, Widget child) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: child,
    ),
  );
}

// ============================================================================
// Add expense (EXP-01..03)
// ============================================================================

class AddExpenseSheet extends StatefulWidget {
  const AddExpenseSheet({
    super.key,
    required this.controller,
    this.group,
    this.friendId,
    this.existing,
  });

  final AppController controller;
  final Group? group;
  final String? friendId;
  final Expense? existing; // non-null = edit mode

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late String _category;
  String? _groupId;
  late String _payer;
  final Set<String> _participants = {};
  String _splitMethod = 'equal';
  DateTime _date = DateTime.now();

  // For amount/percentage splits: personId -> text controller.
  final Map<String, TextEditingController> _shareControllers = {};

  AppData get _data => widget.controller.state!;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      // Edit mode: prefill every field from the expense being edited.
      _title.text = existing.title;
      _amount.text = existing.amount.toString();
      _note.text = existing.note ?? '';
      _category = existing.category;
      _groupId = existing.groupId;
      _payer = existing.paidBy;
      _participants.addAll(existing.participants);
      _splitMethod = existing.splitMethod;
      _date = existing.date;
      existing.splits.forEach((id, value) {
        _shareController(id).text = value.toString();
      });
      return;
    }

    _category = 'general';
    _payer = widget.controller.myId;
    _groupId = widget.group?.id;

    if (widget.group != null) {
      _participants.addAll(widget.group!.members);
    } else if (widget.friendId != null) {
      _participants.addAll([widget.controller.myId, widget.friendId!]);
    } else {
      _participants.add(widget.controller.myId);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    for (final c in _shareControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _candidatePeople {
    if (_groupId != null) {
      return _data.groupById(_groupId!)?.members ?? [];
    }
    // Non-group: any person can be a participant.
    return _data.people.map((p) => p.id).toList();
  }

  TextEditingController _shareController(String personId) =>
      _shareControllers.putIfAbsent(personId, () => TextEditingController());

  String? _validateSplits(double amount) {
    if (_splitMethod == 'equal') return null;
    var total = 0.0;
    for (final id in _participants) {
      total += double.tryParse(_shareController(id).text) ?? 0;
    }
    if (_splitMethod == 'amount' && (total - amount).abs() > 0.01) {
      return 'Exact amounts must add up to ${money(amount)} (currently ${money(total)})';
    }
    if (_splitMethod == 'percentage' && (total - 100).abs() > 0.01) {
      return 'Percentages must add up to 100% (currently ${total.toStringAsFixed(1)}%)';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_participants.isEmpty) {
      _snack('Pick at least one participant');
      return;
    }
    final amount = double.parse(_amount.text);
    final splitError = _validateSplits(amount);
    if (splitError != null) {
      _snack(splitError);
      return;
    }

    final splits = <String, double>{};
    if (_splitMethod != 'equal') {
      for (final id in _participants) {
        splits[id] = double.tryParse(_shareController(id).text) ?? 0;
      }
    }

    final expense = Expense(
      id: widget.existing?.id ?? 'exp-${DateTime.now().microsecondsSinceEpoch}',
      title: _title.text.trim(),
      amount: amount,
      paidBy: _payer,
      participants: _participants.toList(),
      groupId: _groupId,
      category: _category,
      date: _date,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      splitMethod: _splitMethod,
      splits: splits,
    );

    try {
      if (_isEdit) {
        await widget.controller.editExpense(expense);
      } else {
        await widget.controller.addExpense(expense);
      }
    } catch (e) {
      _snack(e is ArgumentError ? '${e.message}' : '$e');
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isEdit ? 'Edit expense' : 'Add expense',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final parsed = double.tryParse(v ?? '');
                  if (parsed == null || parsed <= 0) return 'Enter an amount';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: expenseCategories
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text('${categoryEmoji(c)}  $c'),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? 'general'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _groupId,
                decoration: const InputDecoration(
                  labelText: 'Group (optional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('No group')),
                  ..._data.groups.map((g) => DropdownMenuItem(
                        value: g.id,
                        child: Text('${g.emoji}  ${g.name}'),
                      )),
                ],
                onChanged: (v) => setState(() {
                  _groupId = v;
                  if (v != null) {
                    _participants
                      ..clear()
                      ..addAll(_data.groupById(v)!.members);
                  }
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _payer,
                decoration: const InputDecoration(
                  labelText: 'Paid by',
                  border: OutlineInputBorder(),
                ),
                items: _candidatePeople.map((id) {
                  final p = _data.personById(id)!;
                  return DropdownMenuItem(
                      value: id, child: Text('${p.avatar}  ${p.name}'));
                }).toList(),
                onChanged: (v) =>
                    setState(() => _payer = v ?? widget.controller.myId),
              ),
              const SizedBox(height: 16),
              Text('Split method', style: theme.textTheme.titleSmall),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'equal', label: Text('Equal')),
                  ButtonSegment(value: 'amount', label: Text('Exact')),
                  ButtonSegment(value: 'percentage', label: Text('%')),
                ],
                selected: {_splitMethod},
                onSelectionChanged: (s) =>
                    setState(() => _splitMethod = s.first),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Participants', style: theme.textTheme.titleSmall),
                  if (_groupId == null)
                    TextButton.icon(
                      onPressed: _addParticipant,
                      icon: const Icon(Icons.person_add_alt, size: 18),
                      label: const Text('Add someone'),
                    ),
                ],
              ),
              ..._candidatePeople.map(_participantTile),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text('Date: ${_date.toString().split(' ').first}'),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: const Text('Change'),
                    onPressed: _pickDate,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submit,
                child: Text(_isEdit ? 'Save changes' : 'Add expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _participantTile(String id) {
    final p = _data.personById(id)!;
    final selected = _participants.contains(id);
    return Row(
      children: [
        Expanded(
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: selected,
            title: Text('${p.avatar}  ${p.name}'),
            onChanged: (v) => setState(() {
              if (v ?? false) {
                _participants.add(id);
              } else {
                _participants.remove(id);
              }
            }),
          ),
        ),
        if (selected && _splitMethod != 'equal')
          SizedBox(
            width: 90,
            child: TextField(
              controller: _shareController(id),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                prefixText: _splitMethod == 'amount' ? '\$' : null,
                suffixText: _splitMethod == 'percentage' ? '%' : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
      ],
    );
  }

  /// Searches the member directory, adds the chosen people to local state, and
  /// marks them as participants on this (non-group) expense.
  Future<void> _addParticipant() async {
    final picked = await showMemberPicker(
      context,
      widget.controller,
      excludeIds: _candidatePeople.toSet(),
      title: 'Add participant',
    );
    if (picked == null || picked.isEmpty) return;
    for (final m in picked) {
      await widget.controller.ensurePerson(m);
      _participants.add(m.id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }
}

// ============================================================================
// Create group (GRP-01)
// ============================================================================

class CreateGroupSheet extends StatefulWidget {
  const CreateGroupSheet({super.key, required this.controller});

  final AppController controller;

  @override
  State<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<CreateGroupSheet> {
  final _name = TextEditingController();
  String _emoji = '👥';
  final List<Member> _members = [];
  static const _emojiChoices = ['👥', '🏖️', '🏠', '🚗', '✈️', '🎉', '⛺', '🍽️'];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickMembers() async {
    final picked = await showMemberPicker(
      context,
      widget.controller,
      excludeIds: {widget.controller.myId, ..._members.map((m) => m.id)},
      title: 'Add members',
    );
    if (picked != null && picked.isNotEmpty) {
      setState(() => _members.addAll(picked));
    }
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) return;
    await widget.controller
        .createGroup(_name.text.trim(), _emoji, members: _members);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Create group', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Group name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Emoji', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _emojiChoices.map((e) {
              final selected = e == _emoji;
              return GestureDetector(
                onTap: () => setState(() => _emoji = e),
                child: CircleAvatar(
                  backgroundColor: selected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Text(e),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Members', style: theme.textTheme.titleSmall),
              TextButton.icon(
                onPressed: _pickMembers,
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          Text("You're added automatically.",
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppTheme.inkSoft)),
          if (_members.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _members
                  .map((m) => Chip(
                        avatar:
                            Text(m.avatar, style: const TextStyle(fontSize: 16)),
                        label: Text(m.name),
                        onDeleted: () =>
                            setState(() => _members.removeWhere((x) => x.id == m.id)),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: _create, child: const Text('Create')),
        ],
      ),
    );
  }
}

// ============================================================================
// Manage members (GRP-02)
// ============================================================================

class ManageMembersSheet extends StatelessWidget {
  const ManageMembersSheet({
    super.key,
    required this.controller,
    required this.group,
  });

  final AppController controller;
  final Group group;

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Wraps an admin action so permission/validation errors surface as a snack
  /// instead of crashing the sheet.
  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        _snack(context, e is StateError ? e.message : '$e');
      }
    }
  }

  Future<void> _addFromDirectory(BuildContext context, Group current) async {
    final picked = await showMemberPicker(
      context,
      controller,
      excludeIds: current.members.toSet(),
      title: 'Add to ${current.name}',
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    await _run(context, () => controller.addMembersToGroup(current.id, picked));
  }

  Future<void> _confirmRemove(
      BuildContext context, Group current, Person p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('${p.name} will be removed from ${current.name}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(
        context, () => controller.removeMemberFromGroup(current.id, p.id));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final data = controller.state!;
        final current = data.groupById(group.id) ?? group;
        final amAdmin = controller.amIAdmin(current.id);
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('Members of ${current.name}',
                        style: theme.textTheme.titleLarge),
                  ),
                  if (amAdmin)
                    FilledButton.tonalIcon(
                      onPressed: () => _addFromDirectory(context, current),
                      icon: const Icon(Icons.person_add_alt, size: 18),
                      label: const Text('Add'),
                    ),
                ],
              ),
              if (!amAdmin) ...[
                const SizedBox(height: 4),
                Text('Only group admins can add or remove members.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppTheme.inkSoft)),
              ],
              const SizedBox(height: 12),
              ...current.members.map((id) {
                final p = data.personById(id)!;
                final isMe = id == controller.myId;
                final memberIsAdmin = current.isAdmin(id);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PersonAvatar(person: p),
                  title: Text(p.name),
                  subtitle: memberIsAdmin
                      ? Text('Admin',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.primary))
                      : null,
                  trailing: _memberTrailing(
                    context,
                    current,
                    p,
                    isMe: isMe,
                    memberIsAdmin: memberIsAdmin,
                    amAdmin: amAdmin,
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  /// Trailing widget for a member row: a "You" chip, and — for admins acting on
  /// other members — a popup with role + removal actions.
  Widget? _memberTrailing(
    BuildContext context,
    Group current,
    Person p, {
    required bool isMe,
    required bool memberIsAdmin,
    required bool amAdmin,
  }) {
    final youChip = isMe ? const Chip(label: Text('You')) : null;
    // Admins manage other members; they can't act on themselves here.
    if (!amAdmin || isMe) return youChip;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        switch (value) {
          case 'promote':
            _run(context, () => controller.assignAdmin(current.id, p.id));
          case 'demote':
            _run(context, () => controller.revokeAdmin(current.id, p.id));
          case 'remove':
            _confirmRemove(context, current, p);
        }
      },
      itemBuilder: (_) => [
        if (memberIsAdmin)
          const PopupMenuItem(value: 'demote', child: Text('Remove admin'))
        else
          const PopupMenuItem(value: 'promote', child: Text('Make admin')),
        const PopupMenuItem(value: 'remove', child: Text('Remove from group')),
      ],
    );
  }
}

// ============================================================================
// Settle up (SET-02)
// ============================================================================

class SettleUpSheet extends StatefulWidget {
  const SettleUpSheet({
    super.key,
    required this.controller,
    this.groupId,
    this.friendId,
  });

  final AppController controller;
  final String? groupId;
  final String? friendId;

  @override
  State<SettleUpSheet> createState() => _SettleUpSheetState();
}

class _SettleUpSheetState extends State<SettleUpSheet> {
  final _amount = TextEditingController();
  late String _otherPerson;
  bool _iPay = true; // true: I pay them; false: they pay me

  AppData get _data => widget.controller.state!;

  @override
  void initState() {
    super.initState();
    _otherPerson = widget.friendId ??
        _data.people.firstWhere((p) => p.id != widget.controller.myId).id;
    final net = widget.controller.balanceWithFriend(_otherPerson);
    _iPay = net < 0; // I owe them → I pay
    _amount.text = net.abs().toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _settle() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount greater than zero')),
      );
      return;
    }
    final me = widget.controller.myId;
    await widget.controller.recordSettlement(
      widget.groupId,
      from: _iPay ? me : _otherPerson,
      to: _iPay ? _otherPerson : me,
      amount: amount,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final others =
        _data.people.where((p) => p.id != widget.controller.myId).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settle up', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          if (widget.friendId == null)
            DropdownButtonFormField<String>(
              initialValue: _otherPerson,
              decoration: const InputDecoration(
                labelText: 'With',
                border: OutlineInputBorder(),
              ),
              items: others.map((p) {
                return DropdownMenuItem(
                    value: p.id, child: Text('${p.avatar}  ${p.name}'));
              }).toList(),
              onChanged: (v) => setState(() => _otherPerson = v!),
            ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('I pay')),
              ButtonSegment(value: false, label: Text('They pay me')),
            ],
            selected: {_iPay},
            onSelectionChanged: (s) => setState(() => _iPay = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: '\$ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _settle,
            child: const Text('Record payment'),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Expense detail — history, comments, edit/delete (business-logic spec)
// ============================================================================

/// Human-readable label for an expense's split method.
String splitMethodLabel(String method) {
  switch (method) {
    case 'amount':
      return 'Exact amounts';
    case 'percentage':
      return 'Percentage split';
    case 'equal':
    default:
      return 'Split equally';
  }
}

class ExpenseDetailSheet extends StatefulWidget {
  const ExpenseDetailSheet({
    super.key,
    required this.controller,
    required this.expenseId,
  });

  final AppController controller;
  final String expenseId;

  @override
  State<ExpenseDetailSheet> createState() => _ExpenseDetailSheetState();
}

class _ExpenseDetailSheetState extends State<ExpenseDetailSheet> {
  final _comment = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  String _who(AppData data, String id) => data.personById(id)?.name ?? id;

  String _stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final local = d.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _postComment(Expense expense) async {
    final text = _comment.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    await widget.controller.addComment(expense, text);
    if (!mounted) return;
    _comment.clear();
    setState(() => _posting = false);
  }

  Future<void> _confirmDelete(BuildContext context, Expense expense) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('"${expense.title}" will be removed for everyone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.controller.deleteExpense(expense);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final data = widget.controller.state;
        final expense = data?.expenses
            .where((e) => e.id == widget.expenseId)
            .cast<Expense?>()
            .firstWhere((e) => e != null, orElse: () => null);
        if (data == null || expense == null) {
          // Deleted out from under us — close gracefully.
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('This expense is no longer available.'),
          );
        }
        final canModify = widget.controller.canModifyExpense(expense);
        final payer = data.personById(expense.paidBy);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(expense.title,
                          style: theme.textTheme.titleLarge),
                    ),
                    Text(money(expense.amount),
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${categoryEmoji(expense.category)} ${payer?.name ?? '?'} paid · '
                  '${expense.date.toString().split(' ').first}',
                  style: theme.textTheme.bodySmall,
                ),
                if (canModify) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          showAddExpenseSheet(context, widget.controller,
                              existing: expense);
                        },
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Delete'),
                        onPressed: () => _confirmDelete(context, expense),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 24),

                // Split breakdown — who's in the expense and how much each owes.
                Text('Split breakdown', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '${splitMethodLabel(expense.splitMethod)} · '
                  '${widget.controller.displayName(expense.paidBy)} paid ${money(expense.amount)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                ...expense.participants.map((id) {
                  final person = data.personById(id);
                  final share = expense.getParticipantShare(id);
                  final isPayer = id == expense.paidBy;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        if (person != null)
                          PersonAvatar(person: person, radius: 16)
                        else
                          const CircleAvatar(
                              radius: 16, child: Icon(Icons.person, size: 16)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.controller.displayName(id),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        if (isPayer)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text('paid',
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary)),
                          ),
                        Text(
                          money(share),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(height: 24),

                // History
                Text('History', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                if (expense.history.isEmpty)
                  Text('No history yet.', style: theme.textTheme.bodySmall)
                else
                  ...expense.history.map((h) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${_who(data, h.user)} ${h.action} · ${_stamp(h.timestamp)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      )),
                const Divider(height: 24),

                // Comments
                Text('Comments', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                if (expense.comments.isEmpty)
                  Text('No comments yet.', style: theme.textTheme.bodySmall)
                else
                  ...expense.comments.map((c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${_who(data, c.userId)} · ${_stamp(c.timestamp)}',
                                style: theme.textTheme.labelSmall),
                            Text(c.message, style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      )),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _comment,
                        decoration: const InputDecoration(
                          hintText: 'Add a comment…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _postComment(expense),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _posting ? null : () => _postComment(expense),
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
