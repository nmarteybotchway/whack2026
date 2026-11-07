import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'appearance/appearance_controller.dart';
import 'firebase_options.dart';
import 'pages/home_page.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final appearance = await AppearanceController.load();
  runApp(MyApp(appearance: appearance));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.appearance});

  final AppearanceController appearance;

  @override
  Widget build(BuildContext context) {
    return AppearanceScope(
      controller: appearance,
      child: ListenableBuilder(
        listenable: appearance,
        builder: (context, _) => MaterialApp(
          title: 'Hackathon',
          theme: AppTheme.light(appearance.accent),
          darkTheme: AppTheme.dark(appearance.accent),
          themeMode: appearance.mode,
          home: const AuthGate(),
        ),
      ),
    );
  }
}

/// Signs the user in anonymously, without any sign-in UI, and shows [HomePage]
/// once a Firebase user exists.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _signingIn = false;

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null && !_signingIn) {
        _signingIn = true;
        FirebaseAuth.instance.signInAnonymously().whenComplete(
          () => _signingIn = false,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return HomePage(key: ValueKey(user.uid), user: user);
      },
    );
  }
}
