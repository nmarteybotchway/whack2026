import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Placeholder onboarding page shown when no Firebase user is signed in.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  bool _busy = false;

  // Temporary until real sign-in is built: lets the flow be exercised end to end.
  Future<void> _continueAnonymously() async {
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sign-in failed: ${e.message ?? e.code}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                children: [
                  Icon(
                    Icons.rocket_launch,
                    size: 72,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome',
                    textAlign: .center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Setup goes here. Sign-in and onboarding are not built yet.',
                    textAlign: .center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: _busy ? null : _continueAnonymously,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue as guest'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
