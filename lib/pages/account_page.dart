import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:zerotrust_contacts/auth_service.dart';
import 'package:zerotrust_contacts/integrations/supabase_service.dart';

@NowaGenerated()
class AccountPage extends StatefulWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() {
    return _AccountPageState();
  }
}

@NowaGenerated()
class _AccountPageState extends State<AccountPage> {
  bool _isSigningOut = false;
  String? _errorMessage;

  Future<void> _handleSignOut() async {
    if (_isSigningOut) {
      return;
    }

    setState(() {
      _isSigningOut = true;
      _errorMessage = null;
    });

    try {
      if (SupabaseService().currentUser != null) {
        await AuthService().signOut();
      }
      if (mounted) {
        context.go('/onboarding');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = SupabaseService().currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Signed in as',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6.0),
            Text(
              currentUser?.email ?? 'No active session',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 10.0),
            Text(
              'User ID: ${currentUser?.id ?? 'N/A'}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20.0),
            ElevatedButton.icon(
              onPressed: _isSigningOut ? null : _handleSignOut,
              icon: const Icon(Icons.logout),
              label: _isSigningOut
                  ? const SizedBox(
                      height: 18.0,
                      width: 18.0,
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    )
                  : const Text('Sign Out'),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12.0),
              Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
