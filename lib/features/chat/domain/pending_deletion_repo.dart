import '../../../core/result.dart';
import 'pending_deletion.dart';

abstract class PendingDeletionRepo {
  Stream<List<PendingDeletion>> watchPendingDeletions();

  /// Executes the deletion of the target document and removes the pending doc.
  Future<Result<void>> confirmPendingDeletion(PendingDeletion deletion);

  Future<Result<void>> dismissPendingDeletion(String id);
}
