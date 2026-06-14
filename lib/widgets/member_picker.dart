import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'common.dart';

/// Opens the member-search sheet and returns the members the user picked, or
/// null if they cancelled. [excludeIds] hides people already added.
Future<List<Member>?> showMemberPicker(
  BuildContext context,
  AppController controller, {
  Set<String> excludeIds = const {},
  String title = 'Add members',
}) {
  return showModalBottomSheet<List<Member>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _MemberPickerSheet(
        controller: controller,
        excludeIds: excludeIds,
        title: title,
      ),
    ),
  );
}

class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet({
    required this.controller,
    required this.excludeIds,
    required this.title,
  });

  final AppController controller;
  final Set<String> excludeIds;
  final String title;

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<Member> _results = [];
  final Map<String, Member> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(value));
  }

  Future<void> _search(String value) async {
    setState(() => _loading = true);
    final all = await widget.controller.searchMembers(value.trim());
    if (!mounted) return;
    setState(() {
      _results = all.where((m) => !widget.excludeIds.contains(m.id)).toList();
      _loading = false;
    });
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
          Text(widget.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _query,
            autofocus: true,
            onChanged: _onChanged,
            decoration: const InputDecoration(
              hintText: 'Search by name or email…',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          if (_selected.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selected.values
                  .map((m) => Chip(
                        avatar: Text(m.avatar, style: const TextStyle(fontSize: 16)),
                        label: Text(m.name),
                        onDeleted: () => setState(() => _selected.remove(m.id)),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? _emptyState(theme)
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, indent: 64),
                        itemBuilder: (context, i) {
                          final m = _results[i];
                          final selected = _selected.containsKey(m.id);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: PersonAvatar(
                              person: m.toPerson(),
                              radius: 22,
                            ),
                            title: Text(m.name,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: m.email.isEmpty ? null : Text(m.email),
                            trailing: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.add_circle_outline,
                              color: selected
                                  ? AppTheme.brand
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            onTap: () => setState(() {
                              if (selected) {
                                _selected.remove(m.id);
                              } else {
                                _selected[m.id] = m;
                              }
                            }),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.values.toList()),
            child: Text(_selected.isEmpty
                ? 'Select members to add'
                : 'Add ${_selected.length} '
                    '${_selected.length == 1 ? 'member' : 'members'}'),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search,
              size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('No one found',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppTheme.inkSoft)),
        ],
      ),
    );
  }
}
