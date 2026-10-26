import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

/// Keeps the Supabase session in OS secure storage (Android Keystore,
/// Windows DPAPI) instead of plain shared preferences.
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();

  static const _storage = FlutterSecureStorage();
  static const _key = 'supabase_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);

  @override
  Future<void> persistSession(String persistSessionString) => _storage.write(key: _key, value: persistSessionString);
}

Future<void> initSupabase() async {
  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    throw StateError('Missing Supabase config: run with --dart-define-from-file=env.json');
  }
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
    authOptions: const FlutterAuthClientOptions(localStorage: SecureSessionStorage(), detectSessionInUri: false),
  );
}
