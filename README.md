# MyRoom

A personal productivity app built with Flutter. MyRoom combines a calendar, to-do list, idea capture, daily notes, and a life-recap board — all backed by a local SQLite database and an AI assistant powered by OpenAI GPT-4o-mini.

---

## Features

| Tab | Description |
|-----|-------------|
| **行事曆** Calendar | Weekly timeline view. Add events with specific times. |
| **待辦** To-Do | Task list with categories (工作, 學習, 個人, 健康) and a progress ring. |
| **靈感** Ideas | Expandable idea cards with AI-generated summaries and resource links. Pinnable AI resource recommendations. |
| **筆記** Notes | Date-based and category-based note editor with a calendar picker. |
| **回顧** Recap | Past / present / future goal tracking with a visual timeline. |

**AI overlay (Ask AI)**
- Real-time chat with GPT-4o-mini, with full awareness of your current todos, events, notes, ideas, and goals.
- Conversation history is persisted across sessions.

**Smart Add overlay (`+` button)**
- Type anything in plain language; GPT classifies it and routes it to the right section automatically.
- Examples: `"明天下午三點開會"` → Calendar event + Todo. `"買牛奶"` → Todo. `"如果日記能自動分析情緒就好了"` → Idea.

**Idea page (靈感)**
- **紀錄靈感 tab** — Each new idea is immediately saved, then enriched by GPT (one-sentence core insight + 2–3 resource links). Tap a card to expand the AI panel. Links open in the system browser. Cards can be individually deleted (synced to DB).
- **探索資源 tab** — On page load (or "重新推薦" tap), the app sends your top 5 ideas to GPT and gets back 4–6 curated learning resources. Resources can be pinned; pinned items persist across sessions in their own DB table and appear at the top of the list.

---

## Requirements

- Flutter `≥ 3.41.6` / Dart `≥ 3.11.4`
- An [OpenAI API key](https://platform.openai.com/api-keys) (GPT-4o-mini access)
- Android, iOS, or Windows desktop (Flutter Web is not supported — SQLite is unavailable in browser)

---

## Installation

### 1. Clone the repo

```bash
git clone <repo-url>
cd myroom
```

### 2. Add your OpenAI API key

Create (or edit) `lib/config.dart`. This file is gitignored — never commit a real key.

```dart
// lib/config.dart
class AppConfig {
  static const openAiApiKey = 'sk-YOUR_KEY_HERE';  // ← paste your key here
  static const openAiModel  = 'gpt-4o-mini';
}
```

### 3. Install dependencies

```bash
flutter pub get
```

### 4. Run the app

```bash
flutter run                 # mobile (Android / iOS)
flutter run -d windows      # Windows desktop
```

The database is created automatically on first launch and seeded with sample data so every tab shows content immediately.

---

## Project Structure

```
lib/
├── config.dart               # API key & model name (gitignored)
├── main.dart                 # App entry point, shell, tab state, DB callbacks
├── theme.dart                # Colours, typography, shared shadow tokens
│
├── models/                   # Pure data classes (no Flutter dependency)
│   ├── event.dart            # CalendarEvent
│   ├── todo_item.dart        # TodoItem
│   ├── idea.dart             # Idea + IdeaLink
│   ├── ai_resource.dart      # AiResource (explore-tab recommendations)
│   └── recap_item.dart       # RecapItem + Era enum
│
├── services/
│   ├── database_service.dart # SQLite singleton — all reads/writes
│   └── openai_service.dart   # OpenAI REST client — classify, chat, enrich, recommend
│
├── data/
│   └── seed_data.dart        # Sample data inserted on first launch
│
├── pages/
│   ├── calendar_page.dart    # Weekly timeline + event form
│   ├── todo_page.dart        # Filtered task list + add form
│   ├── idea_page.dart        # Expandable idea cards + AI resource explorer
│   ├── note_page.dart        # Date/category note editor
│   └── recap_page.dart       # Past / present / future timeline
│
├── overlays/
│   ├── add_overlay.dart      # Smart-add with GPT classification
│   └── ai_chat_overlay.dart  # Full-screen AI chat
│
└── widgets/
    ├── bottom_nav_bar.dart   # Animated bottom navigation
    ├── mr_card.dart          # Shared card container
    ├── mr_icon_button.dart   # Icon button with consistent sizing
    └── mr_add_row.dart       # "Add new item" trigger row
```

---

## Architecture

### State management

State lives in `MyRoomShell` (`main.dart`) and is passed down as immutable lists / maps. Pages fire fine-grained callbacks (`onTodoAdded`, `onTodoToggled`, `onEventAdded`, `onIdeaAdded`, `onIdeaDeleted`, `onNoteSaved`); the shell writes to SQLite and re-fetches the affected list, then calls `setState`. No external state-management library is used.

### Persistence

`DatabaseService` is a lazy singleton wrapping `sqflite`. All tables are created together in `_onCreate` (schema version 1) — there is no migration path. The DB file lives at the path returned by `getDatabasesPath()`. On cold start, `seedIfEmpty()` checks whether the `todos` table is empty and inserts sample rows only on the very first run.

**Tables:**

| Table | Purpose |
|-------|---------|
| `todos` | Tasks with category, color, done flag |
| `events` | Calendar events with start/end day and time |
| `ideas` | User ideas with optional `ai_summary` and `links` JSON columns |
| `notes` | Date-keyed journal entries (UNIQUE on `date_key`) |
| `recap_items` | Past / present / future milestones |
| `chat_messages` | Persisted AI chat history |
| `pinned_resources` | User-pinned explore resources (UNIQUE on `url`) |

On **Windows desktop**, `sqflite_common_ffi` is initialised in `main()` before `runApp`:

```dart
if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
```

### AI integration

`OpenAIService` is a singleton making direct HTTPS calls to the OpenAI Chat Completions endpoint via the `http` package. It exposes four operations:

| Method | Temp | Tokens | Purpose |
|--------|------|--------|---------|
| `classifyInput` | 0.2 | 200 | Routes free-text input to the correct tab |
| `chat` | 0.7 | 600 | Conversational assistant with live DB context |
| `enrichIdea` | 0.5 | 300 | One-sentence insight + 2–3 links per idea |
| `fetchRecommendations` | 0.6 | 600 | 4–6 curated resources from top-5 ideas |

All methods using structured output pass `response_format: {"type": "json_object"}` for deterministic parsing.

**Classification result types** (sealed class hierarchy):

```
ClassificationResult
 ├── ClassifiedTodo
 ├── ClassifiedTodoWithTime
 ├── ClassifiedIdea
 ├── ClassifiedNote
 ├── ClassifiedRecap
 └── ClassificationError
```

### Error handling

| Failure | Behaviour |
|---------|-----------|
| Network unavailable | `SocketException` caught; `ClassificationError` returned; raw text saved as a note |
| OpenAI 4xx / 5xx | Non-200 response logged; operation returns `null` / error result |
| Malformed JSON from GPT | `FormatException` caught → `ClassificationError` or empty list |
| API key not set | `AssertionError` thrown at first AI call with a clear message |
| Idea enrichment failure | Idea is already saved; card shows "AI 分析中…" permanently (no crash) |

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `google_fonts` | ^6.2.1 | Typography |
| `lucide_icons_flutter` | ^2.0.6 | Icon set |
| `sqflite` | ^2.4.1 | SQLite persistence (Android / iOS) |
| `sqflite_common_ffi` | ^2.3.4 | SQLite FFI layer for Windows / Linux / macOS |
| `path` | ^1.9.1 | Database file path helper |
| `http` | ^1.2.2 | OpenAI REST calls |
| `url_launcher` | ^6.3.1 | Open URLs in the system browser |

---

## Notes

- `lib/config.dart` is listed in `.gitignore`. If you clone the repo for the first time the file will not exist — create it manually as shown in the installation steps above.
- All UI copy is in Traditional Chinese (繁體中文); AI responses are also in Chinese.
- The database has no migration path. If the schema needs to change in a future version, delete the DB file (located at the path printed by `getDatabasesPath()`) and relaunch to trigger a fresh `_onCreate`.
