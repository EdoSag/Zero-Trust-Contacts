import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:zerotrust_contacts/config/app_config.dart';
import 'package:zerotrust_contacts/integrations/supabase_service.dart';
import 'package:zerotrust_contacts/security_service.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

class VaultSyncScheduler with WidgetsBindingObserver {
  VaultSyncScheduler._();

  static final VaultSyncScheduler _instance = VaultSyncScheduler._();

  factory VaultSyncScheduler() {
    return _instance;
  }

  final VaultRepository _vaultRepository = VaultRepository();
  final SupabaseService _supabaseService = SupabaseService();

  Timer? _timer;
  bool _started = false;
  bool _syncInProgress = false;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(hours: AppConfig.syncIntervalHours),
      (_) => _runSync(auto: true),
    );
    await _runSync(auto: true);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runSync(auto: true);
    }
  }

  Future<void> _runSync({required bool auto}) async {
    if (_syncInProgress) {
      return;
    }
    if (_supabaseService.currentUser == null) {
      return;
    }
    if (!LocalEncryptedDatabaseService().isOpen) {
      return;
    }
    _syncInProgress = true;
    try {
      await _vaultRepository.syncWithCloud(auto: auto);
    } catch (error) {
      await _vaultRepository.logActivity(
        auto ? 'auto_sync_failed' : 'sync_failed',
        details: error.toString(),
        isError: true,
      );
    } finally {
      _syncInProgress = false;
    }
  }
}
