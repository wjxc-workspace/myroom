# Phase 3 — Hardening & polish

Picked up after Phase 2 was committed under a session limit with its adversarial
review unfinished. Re-audited Phase 2, fixed the one real bug, then did the
Phase 3 hardening.

## Phase 2 bug found & fixed

- **`web_search` → `web_search_preview`** (`functions/src/lib/config.ts` +
  `enrichIdea` + `fetchRecommendations`). The guide names the hosted tool
  `web_search`, but the pinned `openai@4.104` SDK / the gpt-4o-mini Responses
  endpoint only accept `web_search_preview`; a bare `web_search` is a runtime
  400. The Responses params are cast to `unknown`, so `tsc` never caught it —
  idea enrichment and Explore recommendations would have failed live. Verified
  the `user_location` shape (flat `{type:"approximate", …}`), the function-tool
  shape, and the `text.format` json_schema shape against the SDK `.d.ts` — those
  were already correct. Now centralized in a shared `WEB_SEARCH_TOOL` constant.

The rest of Phase 2 audited clean: callable/trigger contracts, the chat
server-side tool loop + loop-limit reply, rate-limit txn, category injection,
tz-aware dates, rules (fn-only fields, `_internal`, `chat_messages`), and the
client wiring (region `asia-east1`, error→`AiFailure` mapping). No other
behavioral changes were needed.

## Phase 3 work

- **Strict lints** (`analysis_options.yaml`): enabled `avoid_print`,
  `unawaited_futures`, `prefer_const_constructors`. Zero `avoid_print` /
  `unawaited_futures` violations (the code already awaits its futures); 21
  `prefer_const_constructors` infos auto-fixed (`dart fix`). `flutter analyze` →
  No issues found.
- **Loading skeletons** (`core/widgets/mr_skeleton.dart`, a zero-dep shimmer):
  - Ideas enrichment — the `分析中…` state now renders a dark summary-shaped
    skeleton while the `enrichIdea` trigger runs.
  - Recap — era-insight generation (`_EraBlock`) and recap generation
    (`_RecapCard`) show skeleton lines in the content area while
    `generateEraInsight` runs (split the old `_busy` into
    `_generating`/`_exporting` so export still just spins).
- **Chat pagination**: the repo already exposed `loadOlder`, but with a
  `DocumentSnapshot` cursor that leaked `cloud_firestore` into the domain
  interface and was unusable from the UI. Switched it to a `DateTime before`
  cursor; wired a "載入較早的訊息" control in the overlay. The overlay accumulates
  the live 50-window + fetched history by message id (append-only thread → no
  gaps/dupes) and only auto-scrolls on a new tail message, not when prepending.
- **Indexes & categoryFanout**: verified the two composite `notes` indexes cover
  every real client query; all function queries are single-field or
  range+orderBy on the same field (auto-indexed). `categoryFanout` matches
  DataModel.md for both types (refresh on update, reassign-to-`undefined` on
  delete, ≤450-op batches). No changes needed.

## Tests

- **Dart (20 green)**: `ClassificationItem` parsing — discriminator + all 5 item
  types (Test.md §2); model map round-trips (`TodoCategoryRef`,
  `NoteCategoryRef`, `NoteAttachment`, `IdeaLink`, `AiResource`); plus the
  existing date/failure tests.
- **Functions (7 green)**: zero-dep `node --test` over the side-effect-free
  helpers — `zonedToUtc`/`todayKey`/`daysFromNow` tz math and the tolerant
  `extractJson`. `npm test` now builds then runs them.

## Verification

`tsc` build clean · functions tests 7/7 · `flutter analyze` clean (strict lints)
· `flutter test` 20/20.

## Remaining for "definition of done" (blocked on infra not in this env)

The emulator-dependent Test.md layers are **not** done and need a live Emulator
Suite + a real `lib/firebase_options.dart` (still the Phase 0 placeholder, as
flagged in Phase 1): emulator repo/trigger tests, `@firebase/rules-unit-testing`
rules tests, callable App-Check/auth-rejection tests (`firebase-functions-test`),
the 60% coverage target, CI wiring, and the four platform builds. These are the
natural next step once `flutterfire configure` has been run against the project.
