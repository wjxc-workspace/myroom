MyRoom is a Flutter + Firebase personal-productivity app: calendar, to-do list, idea journal, daily
notes, and a life-recap board, with an AI layer. Users can input text, audio, pictures, and files,
and AI classifies each into the right module (Smart Add). An AI chatbot answers questions over the
user's data and modifies it via server-side tools (reschedule events, add todos/notes/ideas, write
recaps). A recap page summarizes achievements and past/future eras.

## Architecture

- **Client (`lib/`)** — feature-first. Each feature has `domain/` (model + abstract repo), `data/`
  (`firebase_*_repo.dart`), and `presentation/`. State is `go_router` (`StatefulShellRoute`) +
  `provider`: shared state comes only from Firestore `StreamProvider`s; writes go through repos and
  return `Result`; the UI re-renders from the stream (no separate optimistic store). The root
  provider tier (auth + Firebase singletons + `AiService`) is in `app.dart`; user-scoped repos mount
  in `app_shell/authenticated_scope.dart`, built from a non-null `uid` after the `users/{uid}` root
  doc exists.
- **Backend (`functions/`)** — TypeScript Cloud Functions, region `us-central1`. Seven callables
  (`chat`, `classifyMultiInput`, `fetchRecommendations`, `generateEraInsight`, `transcribe`,
  `exportRecap`, `exportAchievement`) on the OpenAI Responses API, plus triggers (`provisionUser`,
  `deleteUserData`, `enrichIdea`, `classifyNote`, `findNotesForCategory`, `categoryFanout`,
  `storageCascade`). `chat` runs the tool loop server-side via the Admin SDK; the client only reads
  streams. No OpenAI key on the client — it lives in Secret Manager (`OPENAI_API_KEY`).
- **Data** — Firestore, per-user under `users/{uid}/…`. Note: ideas live at
  `users/{uid}/ideas/data/{user_ideas|pinned_resources}` (the `data` doc is the required parent).
  Category metadata is denormalized onto todos/notes and refreshed by `categoryFanout`. Both
  category types share a permanent `無分類` sentinel with fixed id `undefined`.
- **Security** — per-collection owner-only Firestore/Storage rules (`firestore/firestore.rules`,
  `storage.rules`); function-owned fields (`aiSummary`/`aiStatus`/`links`, `*ExportStoragePath`,
  `chat_messages`, `_internal`) are not client-writable; `createdAt` is immutable.

## Conventions

- UI copy stays Traditional Chinese (`zh-TW`); i18n is out of scope.
- Timestamps use `serverTimestamp()` on create; repos never rewrite `createdAt` on update.
- Content-addressed attachments: Storage filename, `attId`, and `extracted_texts` doc id are all the
  file's `sha256`. Pinned-resource doc id is `sha1(url)`.
- `lib/firebase_options.dart` is a placeholder until `flutterfire configure` is run against a project.

## Verify

`flutter analyze` · `flutter test` · `npm --prefix functions test` (tsc build + helper tests).
Emulator-based repo/rules/trigger tests need a live Emulator Suite and real `firebase_options.dart`.
