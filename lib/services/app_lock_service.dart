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
      _pausedAt = DateTime.now().toUtc();
      lock(reason: 'app_paused');
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
