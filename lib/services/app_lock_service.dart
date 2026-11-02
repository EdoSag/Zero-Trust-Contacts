import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';
import 'package:zerotrust_contacts/security_service.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

class AppLockService extends ChangeNotifier with WidgetsBindingObserver {
  AppLockService._();

  static final AppLockService _instance = AppLockService._();

  factory AppLockService() {
    return _instance;
  }

  final LocalSecurityRepository _localSecurityRepository =
      LocalSecurityRepository();
  final LocalAuthentication _localAuthentication = LocalAuthentication();
  final VaultRepository _vaultRepository = VaultRepository();

  bool _initialized = false;
  bool _biometricsRequired = false;
  bool _isLocked = false;
  DateTime _lastInteraction = DateTime.now().toUtc();
  DateTime? _pausedAt;
  int _systemUiDepth = 0;

  Duration idleTimeout = const Duration(minutes: 3);

  bool get isLocked => _isLocked;
  bool get isLockRequired => _biometricsRequired;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    await refreshPreferences();
    Timer.periodic(const Duration(seconds: 30), (_) {
      _checkIdleTimeout();
    });
  }

  Future<void> refreshPreferences() async {
    final bool biometricsEnabled =
        await _localSecurityRepository.isBiometricEnabled();
    final bool hasLocalVault =
        await _localSecurityRepository.hasEncryptedDbKey();
    _biometricsRequired = biometricsEnabled && hasLocalVault;
    if (_biometricsRequired) {
      _isLocked = true;
    } else {
      _isLocked = false;
    }
    notifyListeners();
  }

  void recordInteraction() {
    _lastInteraction = DateTime.now().toUtc();
    if (!_isLocked) {
      return;
    }
    notifyListeners();
  }

  /// Runs [action] while the app hands off to system UI it opened itself (a
  /// permission prompt or the file picker), so leaving the app for that
  /// screen does not lock the vault and drop the user out of what they were
  /// doing. The idle timeout still applies.
  Future<T> whileShowingSystemUi<T>(Future<T> Function() action) async {
    _systemUiDepth += 1;
    try {
      return await action();
    } finally {
      _systemUiDepth -= 1;
      // Time spent in the system screen still counts as idle: lock if the
      // timeout passed meanwhile, and only otherwise count the return as
      // activity.
      _checkIdleTimeout();
      if (!_isLocked) {
        _lastInteraction = DateTime.now().toUtc();
      }
    }
  }

  void lock({String reason = 'manual'}) {
    if (!isLockRequired) {
      return;
    }
    if (_isLocked) {
      return;
    }
    _isLocked = true;
    notifyListeners();
    _vaultRepository.logActivity('vault_locked', details: reason);
  }

  Future<bool> unlockWithBiometrics() async {
    if (!isLockRequired) {
      _isLocked = false;
      notifyListeners();
      return true;
    }

    try {
      final bool canCheck = await _localAuthentication.canCheckBiometrics;
      final bool deviceSupported =
          await _localAuthentication.isDeviceSupported();
      if (!canCheck || !deviceSupported) {
        await _vaultRepository.logActivity(
          'vault_unlock_failed',
          details: 'Biometrics unavailable',
          isError: true,
        );
        return false;
      }

      final bool authenticated = await _localAuthentication.authenticate(
        localizedReason: 'Unlock your secure vault',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (!authenticated) {
        await _vaultRepository.logActivity(
          'vault_unlock_failed',
          details: 'Biometric authentication declined',
          isError: true,
        );
        return false;
      }

      _isLocked = false;
      _lastInteraction = DateTime.now().toUtc();
      notifyListeners();
      await _vaultRepository.logActivity('vault_unlocked',
          details: 'Biometric unlock succeeded');
      return true;
    } catch (error) {
      await _vaultRepository.logActivity(
        'vault_unlock_failed',
        details: error.toString(),
        isError: true,
      );
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_initialized || !isLockRequired) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pausedAt ??= DateTime.now().toUtc();
      // Leaving for a system screen the app opened itself does not lock at
      // once; the resume check below still applies the idle timeout.
      if (_systemUiDepth == 0) {
        lock(reason: 'app_paused');
      }
    }
    if (state == AppLifecycleState.resumed) {
      final DateTime now = DateTime.now().toUtc();
      if (_pausedAt != null && now.difference(_pausedAt!) >= idleTimeout) {
        lock(reason: 'resume_after_timeout');
      }
      _pausedAt = null;
    }
  }

  void _checkIdleTimeout() {
    if (!_initialized || !isLockRequired || _isLocked) {
      return;
    }
    final DateTime now = DateTime.now().toUtc();
    if (now.difference(_lastInteraction) >= idleTimeout) {
      lock(reason: 'idle_timeout');
    }
  }
}
