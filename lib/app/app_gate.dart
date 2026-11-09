import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_contacts/app/auth_providers.dart';
import 'package:zerotrust_contacts/app/providers.dart';
import 'package:zerotrust_contacts/legacy/legacy_import_controller.dart';
import 'package:zerotrust_contacts/pages/home_page.dart';

/// Routes between the shared account screens and the address book.
///
/// Signed out: sign in or create an account. Signed in but locked (cold
/// start, auto-lock): unlock with the account password or biometrics. A new
/// recovery key is always shown, and confirmed, before the vault opens.
class AppGate extends ConsumerStatefulWidget {
  const AppGate({super.key});

  @override
  ConsumerState<AppGate> createState() => _AppGateState();
}

class _AppGateState extends ConsumerState<AppGate> with WidgetsBindingObserver {
  /// Stays on the sign-in screen until it hands back a result, even though
  /// Supabase reports the session a moment earlier.
  late bool _signingIn = ref.read(currentUserProvider) == null;
  UnlockResult? _awaitingRecoveryKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A key still waiting behind the recovery-key screen is zeroed when the
  /// app leaves the foreground, so coming back asks for the password.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final UnlockResult? pending = _awaitingRecoveryKey;
      if (pending != null) {
        pending.dek.fillRange(0, pending.dek.length, 0);
        setState(() => _awaitingRecoveryKey = null);
      }
    }
  }

  void _onUnlocked(UnlockResult result) {
    if (result.newRecoveryKey != null) {
      setState(() {
        _signingIn = false;
        _awaitingRecoveryKey = result;
      });
      return;
    }
    setState(() => _signingIn = false);
    ref
        .read(vaultControllerProvider.notifier)
        .unlock(result.dek, legacyDek: result.legacyDek);
  }

  void _forgotPassword() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ZtForgotPasswordScreen()));

  @override
  Widget build(BuildContext context) {
    ref.listen(vaultControllerProvider, (_, VaultState next) {
      // Don't leave a contact or settings page open over a locked vault.
      if (next is VaultLocked) {
        Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
      }
    });
    ref.listen(currentUserProvider, (_, user) {
      if (user == null) {
        ref.read(vaultControllerProvider.notifier).lock();
        setState(() => _signingIn = true);
      }
    });

    final UnlockResult? pending = _awaitingRecoveryKey;
    if (pending != null) {
      return ZtRecoveryKeyScreen(
        recoveryKey: pending.newRecoveryKey!,
        onDone: () {
          setState(() => _awaitingRecoveryKey = null);
          ref
              .read(vaultControllerProvider.notifier)
              .unlock(pending.dek, legacyDek: pending.legacyDek);
        },
      );
    }

    if (ref.watch(passwordRecoveryProvider)) {
      return ZtResetPasswordScreen(
        onUnlocked: (UnlockResult result) {
          ref.read(passwordRecoveryProvider.notifier).done();
          _onUnlocked(result);
        },
      );
    }

    final user = ref.watch(currentUserProvider);
    if (user == null || _signingIn) {
      return ZtSignInScreen(
          onUnlocked: _onUnlocked, onForgotPassword: _forgotPassword);
    }

    if (ref.watch(vaultControllerProvider) is VaultLocked) {
      return ZtUnlockScreen(
        email: user.email,
        onUnlocked: _onUnlocked,
        onSignOut: () => ref.read(accountServiceProvider).signOut(),
        onForgotPassword: _forgotPassword,
      );
    }

    // Any touch counts as activity for auto-lock.
    return Listener(
      onPointerDown: (_) => ref.read(vaultControllerProvider.notifier).touch(),
      child: const _ContactsHome(),
    );
  }
}

/// The address book once the encrypted store is open, which is also when
/// sync starts and earlier contacts are brought over.
class _ContactsHome extends ConsumerStatefulWidget {
  const _ContactsHome();

  @override
  ConsumerState<_ContactsHome> createState() => _ContactsHomeState();
}

class _ContactsHomeState extends ConsumerState<_ContactsHome> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(vaultRepositoryProvider, (_, next) {
      if (next is AsyncData) {
        ref.read(legacyImportProvider.notifier).runQuietly();
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    // Keeps sync running while the app is open.
    ref.watch(ztSyncControllerProvider);

    return switch (ref.watch(vaultRepositoryProvider)) {
      AsyncData() => const HomePage(),
      AsyncError(:final Object error) when error is! VaultIsLocked => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Couldn\'t open your contacts on this device. '
                    '${ztErrorMessage(error)}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(vaultRepositoryProvider),
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}
