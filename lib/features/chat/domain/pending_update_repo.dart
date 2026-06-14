import '../../../core/result.dart';
import 'pending_update.dart';

abstract class PendingUpdateRepo {
  Stream<List<PendingUpdate>> watchPendingUpdates();

  /// Applies [update.updateData] to the target document and removes the
  /// pending doc. Adds `updatedAt: serverTimestamp()` for types that carry it
  /// (todos and notes, but not events).
  Future<Result<void>> confirmPendingUpdate(PendingUpdate update);

  Future<Result<void>> dismissPendingUpdate(String id);
}
