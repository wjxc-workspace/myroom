/// Cloud Functions / Firestore region. Taiwan — Firestore + Functions colocated.
const String kFunctionsRegion = 'us-central1';

/// Fixed document id of the per-user preferences singleton.
const String kSettingsDocId = 'app';

/// Fixed id of the "無分類" sentinel category (present in both
/// `todo_categories` and `note_categories`; never user-deletable).
const String kUndefinedCategoryId = 'undefined';

/// The `ideas` area (DataModel.md) holds two sibling subcollections —
/// `user_ideas` and `pinned_resources`. Firestore requires a parent document
/// between the `ideas` collection and those subcollections; this is its fixed
/// id, so the live paths are:
///   users/{uid}/ideas/data/user_ideas/{id}
///   users/{uid}/ideas/data/pinned_resources/{id}
/// Both are covered by the `match /ideas/{document=**}` security rule. The
/// Phase 2 `enrichIdea` trigger targets the same `user_ideas` path.
const String kIdeasRootDocId = 'data';

/// Default IANA timezone used until the client patches it to the device tz.
const String kDefaultTimezone = 'Asia/Taipei';

/// Max attachment size (bytes) — enforced client-side and in storage.rules.
const int kMaxAttachmentBytes = 10 * 1024 * 1024;
