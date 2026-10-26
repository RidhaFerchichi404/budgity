import 'package:drift/drift.dart';

import '../../../core/errors/validation_exception.dart';
import '../../../core/money/money.dart';
import '../../../database/app_database.dart';
import '../../../database/server_rows.dart';

export '../../../database/app_database.dart' show Profile;

/// Profile preferences are last-write-wins (ADR 0002), but still queued so
/// they can be changed offline.
class ProfileRepository {
  ProfileRepository(this._db, this._userId);

  final AppDatabase _db;
  final String Function() _userId;

  Stream<Profile?> watchProfile() =>
      (_db.select(_db.profiles)..where((p) => p.id.equals(_userId()))).watchSingleOrNull();

  /// [freelancerEnabled] null keeps the current value and leaves it out of the payload.
  Future<void> update({required String displayName, required String currencyCode, bool? freelancerEnabled}) async {
    if (displayName.trim().length > 100) throw const ValidationException('Name is too long');
    if (!Money.supportedCurrencies.contains(currencyCode)) throw const ValidationException('Unsupported currency');
    await _db.transaction(() async {
      final current = await watchProfile().first;
      final row = Profile(
        id: _userId(),
        displayName: displayName.trim(),
        currencyCode: currencyCode,
        freelancerEnabled: freelancerEnabled ?? current?.freelancerEnabled ?? false,
        updatedAt: DateTime.now().toUtc(),
        changeSeq: 0,
      );
      await _db
          .into(_db.profiles)
          .insert(
            row,
            onConflict: DoUpdate(
              (_) => ProfilesCompanion(
                displayName: Value(row.displayName),
                currencyCode: Value(row.currencyCode),
                freelancerEnabled: Value(row.freelancerEnabled),
                updatedAt: Value(row.updatedAt),
              ),
            ),
          );
      await _db.syncDao.enqueue(
        EntityType.profile,
        row.id,
        'update',
        ServerRows.profilePayload(row, sendFreelancer: freelancerEnabled != null),
      );
    });
  }
}
