import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Mock home page shown once a Firebase user is signed in.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = user.displayName ?? user.email ?? 'Guest';
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: const Text('Home'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Hi, $name', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('UID: ${user.uid}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          for (var i = 1; i <= 5; i++)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('$i')),
                title: Text('Placeholder item $i'),
                subtitle: const Text('Mock content'),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
