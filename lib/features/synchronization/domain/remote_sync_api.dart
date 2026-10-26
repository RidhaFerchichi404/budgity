import '../../../database/server_rows.dart';

enum RemoteErrorKind {
  /// No connection, DNS failure, timeout: the request may or may not have arrived.
  network,

  /// Session missing or can't be refreshed; user must sign in again.
  auth,
  rateLimited,
  server,
}

class RemoteException implements Exception {
  const RemoteException(this.kind, this.message, {this.retryAfter});

  final RemoteErrorKind kind;
  final String message;
  final Duration? retryAfter;

  @override
  String toString() => 'RemoteException(${kind.name}): $message';
}

/// Transport to the cloud. Every method throws [RemoteException] on failure.
abstract interface class RemoteSyncApi {
  bool get hasSession;

  /// Calls the `sync_push` RPC; one result per op, matched by `op_id`.
  Future<List<Json>> push(List<Json> ops);

  Future<Json> updateProfile(Json payload);

  /// Rows of [table] with change_seq > [afterSeq], ascending, at most [limit].
  Future<List<Json>> pull(String table, int afterSeq, int limit);

  Future<Json?> fetchById(String table, String id);
}
