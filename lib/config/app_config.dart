import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  AppConfig._();

  static late final String supabaseUrl;
  static late final String supabaseAnonKey;
  static late final String appInternalSalt;
  static late final bool isDebugMode;
  static late final int syncIntervalHours;

  static void loadFromEnvOrThrow() {
    supabaseUrl = _requiredValue('SUPABASE_URL');
    supabaseAnonKey = _requiredValue('SUPABASE_ANON_KEY');
    appInternalSalt = _requiredValue('APP_INTERNAL_SALT');
    isDebugMode = _parseBool(_requiredValue('IS_DEBUG_MODE'));
    syncIntervalHours = int.tryParse(_requiredValue('SYNC_INTERVAL_HOURS')) ??
        (throw StateError('SYNC_INTERVAL_HOURS must be an integer.'));

    final parsedUri = Uri.tryParse(supabaseUrl);
    final isValidSupabaseUrl = parsedUri != null &&
        parsedUri.scheme == 'https' &&
        parsedUri.host.isNotEmpty;
    if (!isValidSupabaseUrl) {
      throw StateError('SUPABASE_URL is invalid: $supabaseUrl');
    }

    if (supabaseAnonKey.trim().isEmpty) {
      throw StateError('SUPABASE_ANON_KEY must not be empty.');
    }

    if (appInternalSalt.length < 16) {
      throw StateError('APP_INTERNAL_SALT must be at least 16 characters.');
    }

    if (syncIntervalHours <= 0) {
      throw StateError('SYNC_INTERVAL_HOURS must be greater than zero.');
    }
  }

  static String _requiredValue(String key) {
    final value = dotenv.env[key]?.trim();
    if (value == null || value.isEmpty) {
      throw StateError('Missing required environment variable: $key');
    }
    return value;
  }

  static bool _parseBool(String value) {
    if (value == 'true') {
      return true;
    }
    if (value == 'false') {
      return false;
    }
    throw StateError('Boolean environment value must be true/false: $value');
  }
}
