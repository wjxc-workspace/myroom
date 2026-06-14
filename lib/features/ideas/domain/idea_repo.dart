import '../../../core/result.dart';
import 'idea.dart';
import 'pinned_resource.dart';

abstract class IdeaRepo {
  /// Streams the user's ideas, newest first.
  Stream<List<Idea>> watchIdeas();

  /// Creates an idea from [text]; returns the new doc id. AI enrichment
  /// (`aiSummary`/`aiStatus`/`links`) is filled later by the `enrichIdea`
  /// trigger — the client never writes those fields.
  Future<Result<String>> add(String text);

  Future<Result<void>> updateText(String id, String text);

  /// Requests fresh AI enrichment for an existing idea without changing its
  /// text — bumps the client-writable `reenrichAt` field, which the `enrichIdea`
  /// trigger watches to re-run (`aiSummary`/`aiStatus`/`links` stay fn-only).
  Future<Result<void>> reenrich(String id);

  Future<Result<void>> delete(String id);

  /// Streams pinned resources, ordered by `sortOrder`.
  Stream<List<PinnedResource>> watchPinnedResources();

  /// Pins [resource]; the doc id is `sha1(url)` so re-pinning the same URL is
  /// idempotent.
  Future<Result<void>> pin(PinnedResource resource);

  /// Removes the pinned resource whose id is `sha1(url)`.
  Future<Result<void>> unpin(String url);
}
