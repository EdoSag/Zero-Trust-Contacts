import 'dart:typed_data';

import 'package:zerotrust_contacts/integrations/supabase_service.dart';
import 'package:zerotrust_contacts/security_service.dart';
import 'package:zerotrust_contacts/services/app_lock_service.dart';
import 'package:zerotrust_contacts/services/vault_repository.dart';

class AuthService {
  AuthService({
    SupabaseService? supabaseService,
    LocalSecurityRepository? localSecurityRepository,
    KeyDerivationService? keyDerivationService,
    LocalEncryptedDatabaseService? localEncryptedDatabaseService,
  })  : _supabaseService = supabaseService ?? SupabaseService(),
        _localSecurityRepository =
            localSecurityRepository ?? LocalSecurityRepository(),
        _keyDerivationService = keyDerivationService ?? KeyDerivationService(),
        _localEncryptedDatabaseService =
            localEncryptedDatabaseService ?? LocalEncryptedDatabaseService();

  final SupabaseService _supabaseService;
  final LocalSecurityRepository _localSecurityRepository;
  final KeyDerivationService _keyDerivationService;
  final LocalEncryptedDatabaseService _localEncryptedDatabaseService;
  final VaultRepository _vaultRepository = VaultRepository();

  Future<void> register({
    required String email,
    required String password,
    required bool enableBiometrics,
  }) async {
    if (password.length < 12) {
      throw StateError('Password must be at least 12 characters.');
    }

    final authResponse = await _supabaseService.signUp(email, password);
    if (authResponse.session == null) {
      throw StateError(
        'Sign up succeeded without an active session. Disable email confirmation in Supabase Auth settings for this shared auth flow.',
      );
    }

    final localSalt = _keyDerivationService.generateRandomSalt();
    await _localSecurityRepository.saveSalt(localSalt);
    await _supabaseService.upsertSaltForCurrentUser(localSalt);

    final derivedKey = await _deriveVaultKey(password, localSalt);
    await _localEncryptedDatabaseService.openWithDerivedKey(derivedKey);
    await _localSecurityRepository.saveEncryptedDbKey(derivedKey);
    await _localSecurityRepository.saveBiometricEnabled(enableBiometrics);
    await AppLockService().refreshPreferences();
    await _vaultRepository.logActivity(
      'auth_register',
      details: 'Created vault for $email',
    );
  }

  Future<void> login({
    required String email,
    required String password,
    required bool enableBiometrics,
  }) async {
    if (password.length < 12) {
      throw StateError('Password must be at least 12 characters.');
    }

    final authResponse = await _supabaseService.signIn(email, password);
    if (authResponse.session == null) {
      throw StateError('Login failed: missing active session.');
    }

    final cloudSalt = await _supabaseService.fetchSaltForCurrentUser();
    await _localSecurityRepository.saveSalt(cloudSalt);

    final derivedKey = await _deriveVaultKey(password, cloudSalt);
    await _localEncryptedDatabaseService.openWithDerivedKey(derivedKey);
    await _localSecurityRepository.saveEncryptedDbKey(derivedKey);
    await _localSecurityRepository.saveBiometricEnabled(enableBiometrics);
    await AppLockService().refreshPreferences();

    final cloudBlob =
        await _supabaseService.fetchEncryptedVaultBlobForCurrentUser();
    if (cloudBlob != null) {
      await _localSecurityRepository.saveCachedCloudBlob(cloudBlob);
    }
    await _vaultRepository.logActivity(
      'auth_login',
      details: 'Signed in as $email',
    );
  }

  Future<void> signOut() async {
    await _supabaseService.signOut();
    await _localEncryptedDatabaseService.close();
    await _localSecurityRepository.clearEncryptedDbKey();
    await AppLockService().refreshPreferences();
    await _vaultRepository.clearPendingConflicts();
    await _vaultRepository.logActivity('auth_sign_out');
  }

  Future<bool> isLocalVaultInitialized() {
    return _localSecurityRepository.hasEncryptedDbKey();
  }

  Future<void> restoreLocalVaultForActiveSession() async {
    if (_supabaseService.currentUser == null) {
      return;
    }

    final localKey = await _localSecurityRepository.readEncryptedDbKey();
    if (localKey == null) {
      return;
    }

    await _localEncryptedDatabaseService.openWithDerivedKey(localKey);
  }

  Future<void> pushVaultBlobToCloud(String dataBlob) async {
    final bool looksEncrypted =
        dataBlob.contains('"format":"ztc_cloud_cipher_v1"') ||
            (dataBlob.contains('"nonce"') &&
                dataBlob.contains('"cipherText"') &&
                dataBlob.contains('"mac"'));
    if (!looksEncrypted) {
      throw StateError(
        'Plaintext cloud uploads are disabled. Use VaultRepository.pushLocalToCloud() to upload encrypted data.',
      );
    }
    await _supabaseService.upsertEncryptedVaultBlobForCurrentUser(dataBlob);
    await _vaultRepository.logActivity('vault_push_blob');
  }

  Future<String?> pullVaultBlobFromCloud() async {
    final dataBlob =
        await _supabaseService.fetchEncryptedVaultBlobForCurrentUser();
    if (dataBlob != null) {
      await _localSecurityRepository.saveCachedCloudBlob(dataBlob);
    }
    await _vaultRepository.logActivity('vault_pull_blob');
    return dataBlob;
  }

  Future<void> deleteCloudVaultBlob() async {
    await _supabaseService.deleteEncryptedVaultDataForCurrentUser();
    await _localSecurityRepository.clearCachedCloudBlob();
    await _vaultRepository.logActivity('vault_delete_cloud_blob');
  }

  Future<Uint8List> _deriveVaultKey(String password, List<int> salt) {
    return _keyDerivationService.deriveKey(password: password, salt: salt);
  }
}
