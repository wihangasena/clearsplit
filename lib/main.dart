import 'package:flutter/material.dart';

import 'app_state.dart';
import 'app_shell.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

void main() {
  runApp(ClearSplitApp(controller: AppController()));
}

class ClearSplitApp extends StatelessWidget {
  const ClearSplitApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClearSplit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: SessionGate(controller: controller),
    );
  }
}

/// Routes between login and the main shell based on sign-in state.
class SessionGate extends StatelessWidget {
  const SessionGate({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isSignedIn) {
          return LoginScreen(controller: controller);
        }
        return ClearSplitHome(controller: controller);
      },
    );
  }
}
