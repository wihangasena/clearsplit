import 'package:flutter/material.dart';

import '../app_state.dart';
import '../widgets/common.dart';

/// Edit display name, avatar emoji, and profile color (PROF-01..03).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late String _avatar;
  late String _color;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final me = widget.controller.state!.personById(widget.controller.myId)!;
    _name = TextEditingController(text: me.name);
    _avatar = me.avatar;
    _color = me.color;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.controller.updateProfile(
      name: _name.text.trim(),
      avatar: _avatar,
      color: _color,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: colorFromHex(_color).withValues(alpha: 0.18),
              child: Text(_avatar, style: const TextStyle(fontSize: 44)),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          Text('Avatar', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: avatarChoices.map((emoji) {
              final selected = emoji == _avatar;
              return GestureDetector(
                onTap: () => setState(() => _avatar = emoji),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: selected
                      ? colorFromHex(_color).withValues(alpha: 0.25)
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text('Color', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: profilePalette.map((hex) {
              final selected = hex == _color;
              return GestureDetector(
                onTap: () => setState(() => _color = hex),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorFromHex(hex),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.black87 : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save changes'),
          ),
        ],
      ),
    );
  }
}
