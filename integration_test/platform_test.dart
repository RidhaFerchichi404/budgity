// On-device checks for platform plugins (secure storage, DB file lifecycle).
// Run: flutter test integration_test -d windows   (or an Android device)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mybudget/database/app_database.dart';
import 'package:mybudget/services/supabase_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a full-size session survives secure storage', (_) async {
    const storage = SecureSessionStorage();
    // Real sessions are ~2–4 KB (JWT + refresh token + user JSON); use 8 KB to be safe.
    final session = '{"access_token":"${'x' * 8000}"}';
    await storage.persistSession(session);
    expect(await storage.accessToken(), session);
    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
  });

  testWidgets('database file opens, persists, and is fully deleted on purge', (_) async {
    await deleteDbFiles();
    var db = AppDatabase.open();
    await db.syncDao.setMeta('probe', '1');
    await db.close();

    db = AppDatabase.open();
    expect(await db.syncDao.meta('probe'), '1');
    await db.close();

    await deleteDbFiles();
    final path = await dbFilePath();
    for (final f in [path, '$path-wal', '$path-shm']) {
      expect(File(f).existsSync(), isFalse, reason: f);
    }
  });
}
