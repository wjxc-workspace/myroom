# MyRoom

A personal productivity app built with **Flutter + Firebase**. MyRoom combines a calendar, to-do
list, idea journal, daily notes, and a life-recap board with an AI assistant. AI runs entirely
server-side through Cloud Functions on the OpenAI API — the app ships no API key.

UI copy is Traditional Chinese (繁體中文). Targets: **Android, iOS, Windows, Web (Chrome)**.

---

## Features

| Tab | Description |
|-----|-------------|
| **行事曆** Calendar | Month / week / day views; add / edit / delete events with real `DateTime` start/end. |
| **待辦** To-Do | Tasks with custom categories, drag-to-reorder, show/hide completed, swipe-to-delete. |
| **靈感** Ideas | 紀錄 (capture) — each idea is enriched in the background (one-line insight + resource links). 探索 (explore) — web-searched recommendations from your top ideas, pinnable. |
| **札記** Notes | Date mode (full-year calendar with note-day indicators) and category mode; image / audio / file attachments; AI auto-classification into your categories. |
| **成就** Recap | `recaps` (titled reviews) and `achievements` (past / present / future summaries), each with AI-generated insight text and optional exported graphic. |

**AI chat (`/chat`)** — conversational assistant with a bounded snapshot of your data and
server-side tool execution (add/delete events, todos, ideas, notes, and add recaps), looping up to
6 rounds. Messages are appended to a single `chat_messages` thread by the function.

**Smart Add (`+`)** — accepts text, images, audio, and text/PDF files in one submission. Audio is
transcribed (Whisper), PDF text is extracted client-side, then everything is classified into
todo / timed-todo / idea / note / recap items and routed to the right collection. Attachments
routed to a note are uploaded to Storage (content-addressed by `sha256`).

---

## Architecture

- **State** — `go_router` `StatefulShellRoute` shell + the `provider` package. Shared state is read
  only from Firestore streams (`StreamProvider`); writes go through repositories and return a
  `Result`; the UI re-renders from the stream (no hand-rolled optimistic store).
- **Persistence** — Firestore only, per-user isolated under `users/{uid}/…`. Category metadata is
  denormalized onto todos/notes and kept fresh by a Cloud Function.
- **AI / backend** — Cloud Functions (region `us-central1`) on the OpenAI Responses API. Seven
  callables (`chat`, `classifyMultiInput`, `fetchRecommendations`, `generateEraInsight`,
  `transcribe`, `exportRecap`, `exportAchievement`) and triggers (`provisionUser`, `deleteUserData`,
  `enrichIdea`, `classifyNote`, `findNotesForCategory`, `categoryFanout`, `storageCascade`).
- **Auth** — Firebase Auth (Email/Password + Google; Apple on iOS). A new account is provisioned
  server-side (`provisionUser`) with its settings doc and default categories before the shell loads.
- **Security** — per-collection owner-only Firestore/Storage rules; Function-owned fields are never client-writable.

```
lib/
├── app.dart, main.dart           # root provider tier + bootstrap
├── app_shell/                    # authenticated scope + scaffold (nav, tz patch, tutorial)
├── router/                       # go_router config + auth redirect
├── core/                         # result/failures, theme, shared widgets, constants
├── features/<feature>/           # domain/ (model + repo interface), data/ (Firebase repo), presentation/
└── shared/                       # auth, ai (Cloud Functions client), storage
functions/src/
├── callable/  triggers/  middleware/  lib/   # TypeScript AI proxy + lifecycle/denormalization triggers
firestore/    # rules + composite indexes
storage.rules # owner-only + 10 MB cap
```

---

## Setup

Prerequisites: Flutter (see `pubspec.yaml` for the SDK constraint), the Firebase CLI, and Node 20
for the functions.

```bash
flutter pub get
flutterfire configure --project=YOUR_PROJECT  # generates lib/firebase_options.dart for your project
firebase init functions
flutterfire configure
firebase functions:secrets:set OPENAI_API_KEY # You'll be prompt to paste the secret value.
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
```

Run locally against the Emulator Suite (Auth + Firestore + Storage + Functions):

```bash
flutter run                    # Android / iOS
flutter run -d windows         # Windows desktop
flutter run -d chrome          # Web
```

---

## Tests

```bash
flutter analyze        # static analysis (strict lints)
flutter test           # Dart unit tests (models + classification parsing + helpers)
npm --prefix functions test    # tsc build + Cloud Functions helper tests
```
