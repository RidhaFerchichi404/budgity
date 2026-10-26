import 'package:mybudget/database/server_rows.dart';
import 'package:mybudget/features/synchronization/domain/remote_sync_api.dart';

/// In-memory stand-in for Supabase that mirrors sync_push semantics
/// (supabase/migrations/*_sync_rpc.sql): version check, op ledger, change_seq.
class FakeServer {
  FakeServer(this.userId);

  final String userId;
  final tables = <String, Map<String, Json>>{for (final t in EntityType.values) t.table: {}};
  final _ledger = <String, Json>{};
  int _seq = 0;

  int rowCount(String table) => tables[table]!.length;

  Json _stamp(Json row) => {...row, 'change_seq': ++_seq, 'updated_at': DateTime.now().toUtc().toIso8601String()};

  Json apply(Json op) {
    final opId = op['op_id'] as String;
    final type = EntityType.byName(op['entity_type'] as String);
    final id = op['entity_id'] as String;
    final table = tables[type.table]!;
    if (_ledger.containsKey(opId)) {
      return {..._ledger[opId]!, 'op_id': opId, 'status': 'duplicate', 'current': table[id]};
    }
    final cur = table[id];
    final p = op['payload'] as Json;
    final catId = p['category_id'] as String?;
    if (catId != null && !tables['categories']!.containsKey(catId)) {
      return {'op_id': opId, 'status': 'blocked'};
    }
    Json res;
    switch (op['operation']) {
      case 'create':
        if (cur != null) return {'op_id': opId, 'status': 'conflict', 'row': cur};
        if ((p['amount_minor'] as int? ?? 1) <= 0) return {'op_id': opId, 'status': 'invalid', 'error': 'check'};
        table[id] = _stamp({
          ...p,
          'id': id,
          'user_id': userId,
          'deleted_at': null,
          'version': 1,
          'icon_key': p['icon_key'] ?? 'tag',
          'sort_order': p['sort_order'] ?? 0,
          'description': p['description'] ?? '',
        });
      case 'update' || 'delete':
        if (cur == null) return {'op_id': opId, 'status': 'invalid', 'error': 'not found'};
        if (cur['version'] != op['base_version']) return {'op_id': opId, 'status': 'conflict', 'row': cur};
        table[id] = _stamp(
          op['operation'] == 'delete'
              ? {...cur, 'deleted_at': DateTime.now().toUtc().toIso8601String(), 'version': cur['version'] + 1}
              : {...cur, ...p, 'created_at': cur['created_at'], 'deleted_at': null, 'version': cur['version'] + 1},
        );
    }
    res = {'status': 'applied', 'row': table[id]};
    _ledger[opId] = res;
    return {...res, 'op_id': opId};
  }

  /// Simulates another device's edit landing on the server directly.
  void serverEdit(String table, String id, Json changes) {
    final cur = tables[table]![id]!;
    tables[table]![id] = _stamp({...cur, ...changes, 'version': cur['version'] + 1});
  }

  void seedProfile() =>
      tables['profiles']![userId] = _stamp({'id': userId, 'display_name': '', 'currency_code': 'TND'});
}

/// One device's connection to a [FakeServer].
class FakeRemote implements RemoteSyncApi {
  FakeRemote(this.server);

  final FakeServer server;
  bool online = true;
  bool signedIn = true;

  /// Next push is committed on the server but the response is "lost".
  bool dropNextPushResponse = false;
  int pushCalls = 0;

  /// Session object exists locally but the server rejects it (e.g. revoked).
  bool rejectToken = false;

  void _check() {
    if (!signedIn || rejectToken) throw const RemoteException(RemoteErrorKind.auth, 'signed out');
    if (!online) throw const RemoteException(RemoteErrorKind.network, 'offline');
  }

  @override
  bool get hasSession => signedIn;

  @override
  Future<List<Json>> push(List<Json> ops) async {
    _check();
    pushCalls++;
    final results = [for (final op in ops) server.apply(op)];
    if (dropNextPushResponse) {
      dropNextPushResponse = false;
      throw const RemoteException(RemoteErrorKind.network, 'timeout after commit');
    }
    return results;
  }

  @override
  Future<Json> updateProfile(Json payload) async {
    _check();
    final cur = server.tables['profiles']![server.userId]!;
    server.tables['profiles']![server.userId] = server._stamp({...cur, ...payload});
    return server.tables['profiles']![server.userId]!;
  }

  @override
  Future<List<Json>> pull(String table, int afterSeq, int limit) async {
    _check();
    final rows = server.tables[table]!.values.where((r) => (r['change_seq'] as int) > afterSeq).toList()
      ..sort((a, b) => (a['change_seq'] as int).compareTo(b['change_seq'] as int));
    return rows.take(limit).toList();
  }

  @override
  Future<Json?> fetchById(String table, String id) async {
    _check();
    return server.tables[table]![id];
  }
}
