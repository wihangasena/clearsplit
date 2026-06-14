import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Email/password sign-in with quick-tap demo account tiles (AUTH-01..03).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  List<DemoAccount> _accounts = [];
  bool _loading = false;
  bool _loadingAccounts = true;
  bool _signUpMode = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    try {
      final accounts = await widget.controller.fetchAccounts();
      if (mounted) setState(() => _accounts = accounts);
    } catch (_) {
      // Backend unreachable — login form still works once it's up.
    } finally {
      if (mounted) setState(() => _loadingAccounts = false);
    }
  }

  Future<void> _signIn(String email, String password) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await widget.controller.signIn(email, password);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!ok) _error = widget.controller.lastError ?? 'Sign-in failed';
    });
  }

  Future<void> _signUp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final ok = await widget.controller.register(
      _name.text.trim(),
      _email.text.trim(),
      _password.text,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!ok) _error = widget.controller.lastError ?? 'Sign-up failed';
    });
  }

  void _submitForm() {
    if (_formKey.currentState?.validate() ?? false) {
      if (_signUpMode) {
        _signUp();
      } else {
        _signIn(_email.text.trim(), _password.text);
      }
    }
  }

  void _toggleMode() {
    setState(() {
      _signUpMode = !_signUpMode;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      gradient: AppTheme.brandGradient,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.brand.withValues(alpha: 0.4),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text('💸', style: TextStyle(fontSize: 40)),
                  ),
                ),
                const SizedBox(height: 20),
                Text('ClearSplit',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(
                    _signUpMode
                        ? 'Create an account to start splitting.'
                        : 'Track shared expenses, settle up with ease.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.inkSoft),
                    textAlign: TextAlign.center),
                const SizedBox(height: 28),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      if (_signUpMode) ...[
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v == null || v.trim().length < 2)
                              ? 'Enter your name'
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (v) => (v == null || !v.contains('@'))
                            ? 'Enter a valid email'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          helperText: _signUpMode ? 'At least 6 characters' : null,
                          prefixIcon: const Icon(Icons.lock_outline),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Enter your password';
                          if (_signUpMode && v.length < 6) {
                            return 'At least 6 characters';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _submitForm(),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _submitForm,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_signUpMode ? 'Create account' : 'Sign in'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading ? null : _toggleMode,
                  child: Text(_signUpMode
                      ? 'Already have an account? Sign in'
                      : "Don't have an account? Sign up"),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('Demo accounts (tap to sign in)',
                        style: theme.textTheme.bodySmall),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 12),
                if (_loadingAccounts)
                  const Center(child: CircularProgressIndicator())
                else
                  ..._accounts.map(_demoTile),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _demoTile(DemoAccount account) {
    final color = colorFromHex(account.color);
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      onTap: _loading
          ? null
          : () => _signIn(account.email,
              account.password.isEmpty ? 'demo123' : account.password),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: color.withValues(alpha: 0.28), width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(account.avatar, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(account.email,
                    style: TextStyle(
                        color: AppTheme.inkSoft, fontSize: 13)),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.inkSoft),
        ],
      ),
    );
  }
}
