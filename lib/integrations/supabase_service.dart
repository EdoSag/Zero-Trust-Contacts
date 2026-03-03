import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zerotrust_contacts/utils/base64_url_codec.dart';

@NowaGenerated()
class SupabaseService {
  SupabaseService._();

  factory SupabaseService() {
    return _instance;
  }

  bool _isInitialized = false;

  SupabaseClient get client {
    return Supabase.instance.client;
  }

  User? get currentUser {
    return client.auth.currentUser;
  }

  static final SupabaseService _instance = SupabaseService._();

  Stream<AuthState> get authStateChanges {
    return client.auth.onAuthStateChange;
  }

  Future<void> initialize({
    required String url,
    required String anonKey,
  }) async {
    if (_isInitialized) {
      return;
    }

    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
    _isInitialized = true;
  }

  Future<AuthResponse> signIn(String email, String password) async {
    return client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signUp(String email, String password) async {
    return client.auth.signUp(
      email: email,
      password: password,
    );
  }

  Future<void> signOut() async {
    if (currentUser == null) {
      return;
    }
    await client.auth.signOut();
  }

  Future<void> upsertSaltForCurrentUser(List<int> salt) async {
    final user = currentUser;
    if (user == null) {
      throw StateError('No authenticated user found.');
    }

    await client.from('profiles').upsert({
      'id': user.id,
      'salt': encodeBase64Url(salt),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  Future<List<int>> fetchSaltForCurrentUser() async {
    final user = currentUser;
    if (user == null) {
      throw StateError('No authenticated user found.');
    }

    final dynamic result = await client
        .from('profiles')
        .select('salt')
        .eq('id', user.id)
        .single();
    final saltValue = result['salt'] as String?;
    if (saltValue == null || saltValue.isEmpty) {
      throw StateError('Salt not found in profile for current user.');
    }

    return decodeBase64Url(saltValue);
  }

  Future<void> upsertEncryptedVaultBlobForCurrentUser(String dataBlob) async {
    final user = currentUser;
    if (user == null) {
      throw StateError('No authenticated user found.');
    }

    await client.from('encrypted_contacts').upsert({
      'user_id': user.id,
      'data_blob': dataBlob,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<String?> fetchEncryptedVaultBlobForCurrentUser() async {
    final user = currentUser;
    if (user == null) {
      throw StateError('No authenticated user found.');
    }

    final dynamic row = await client
        .from('encrypted_contacts')
        .select('data_blob')
        .eq('user_id', user.id)
        .maybeSingle();
    if (row == null) {
      return null;
    }
    return row['data_blob'] as String?;
  }

  Future<void> deleteEncryptedVaultDataForCurrentUser() async {
    final user = currentUser;
    if (user == null) {
      throw StateError('No authenticated user found.');
    }

    await client.from('encrypted_contacts').delete().eq('user_id', user.id);
  }
}
