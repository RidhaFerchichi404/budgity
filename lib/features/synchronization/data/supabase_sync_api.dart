import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' show ClientException;
import 'package:supabase/supabase.dart';

import '../../../database/server_rows.dart';
import '../domain/remote_sync_api.dart';

class SupabaseSyncApi implements RemoteSyncApi {
  SupabaseSyncApi(this._client, {this.timeout = const Duration(seconds: 20)});

  final SupabaseClient _client;
  final Duration timeout;

  @override
  bool get hasSession => _client.auth.currentSession != null;

  @override
  Future<List<Json>> push(List<Json> ops) => _guard(() async {
    final res = await _client.rpc('sync_push', params: {'ops': ops});
    return (res as List).cast<Json>();
  });

  @override
  Future<Json> updateProfile(Json payload) => _guard(() async {
    final res = await _client.rpc(
      'update_profile',
      params: {'p_display_name': payload['display_name'], 'p_currency_code': payload['currency_code']},
    );
    return res as Json;
  });

  @override
  Future<List<Json>> pull(String table, int afterSeq, int limit) => _guard(() async {
    final rows = await _client
        .from(table)
        .select()
        .gt('change_seq', afterSeq)
        .order('change_seq', ascending: true)
        .limit(limit);
    return rows.cast<Json>();
  });

  @override
  Future<Json?> fetchById(String table, String id) =>
      _guard(() => _client.from(table).select().eq('id', id).maybeSingle());

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      await _ensureFreshSession();
      return await call().timeout(timeout);
    } on RemoteException {
      rethrow;
    } on TimeoutException {
      throw const RemoteException(RemoteErrorKind.network, 'request timed out');
    } on SocketException catch (e) {
      throw RemoteException(RemoteErrorKind.network, e.message);
    } on ClientException catch (e) {
      throw RemoteException(RemoteErrorKind.network, e.message);
    } on AuthException catch (e) {
      throw RemoteException(_isNetworky(e) ? RemoteErrorKind.network : RemoteErrorKind.auth, e.message);
    } on PostgrestException catch (e) {
      throw _fromPostgrest(e);
    }
  }

  Future<void> _ensureFreshSession() async {
    final session = _client.auth.currentSession;
    if (session == null) throw const RemoteException(RemoteErrorKind.auth, 'not signed in');
    if (session.isExpired) await _client.auth.refreshSession().timeout(timeout);
  }

  static bool _isNetworky(AuthException e) => e is AuthRetryableFetchException;

  static RemoteException _fromPostgrest(PostgrestException e) {
    final code = e.code ?? '';
    // 42501 (permission denied) is a server/config problem, not an expired session.
    if (code == '28000' || code.startsWith('PGRST30')) {
      return RemoteException(RemoteErrorKind.auth, e.message);
    }
    if (code == '429') return RemoteException(RemoteErrorKind.rateLimited, e.message);
    return RemoteException(RemoteErrorKind.server, '${e.code}: ${e.message}');
  }
}
