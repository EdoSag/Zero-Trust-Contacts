import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:zerotrust_contacts/services/app_lock_service.dart';

@NowaGenerated()
class UnlockScreen extends StatefulWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  bool _isUnlocking = false;
  String? _error;

  Future<void> _unlock() async {
    if (_isUnlocking) {
      return;
    }
    setState(() {
      _isUnlocking = true;
      _error = null;
    });
    final bool success = await AppLockService().unlockWithBiometrics();
    if (!mounted) {
      return;
    }
    setState(() {
      _isUnlocking = false;
      _error = success ? null : 'Unlock was not completed.';
    });
    if (success && mounted) {
      context.go('/');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.fingerprint_rounded,
                  size: 72,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  'Vault Locked',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Authenticate with biometrics to continue.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isUnlocking ? null : _unlock,
                  icon: _isUnlocking
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.lock_open),
                  label: Text(_isUnlocking ? 'Unlocking...' : 'Unlock Vault'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
