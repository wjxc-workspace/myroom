# MyRoom

A personal productivity app built with Flutter. MyRoom combines a calendar, to-do list, idea capture, daily notes, and a life-recap board — all backed by a local SQLite database and an AI assistant powered by OpenAI GPT-4o-mini.

---

## Features

| Tab | Description |
|-----|-------------|
| **行事曆** Calendar | Month / week / day views. Add, view, and **delete** events. Week view uses `Expanded` columns to avoid overflow on any screen width. |
| **待辦** To-Do | Task list with custom categories, priority sorting (1–4), done-task toggle, and **swipe-left to delete** with a confirm dialog. |
| **靈感** Ideas | Expandable idea cards with AI-generated summaries and resource links. Pinnable AI resource recommendations. |
| **筆記** Notes | Date-based notes with a full-year calendar; category-based notes with user-created categories; AI auto-classification. |
| **回顧** Recap | Past / present / future goal tracking with a visual timeline. |

**AI overlay (Ask AI)**
- Real-time chat with GPT-4o-mini, with full awareness of your current todos, events, notes, ideas, and goals.
- **Tool-calling (9 CRUD tools)**: the AI can create and delete items directly from conversation — add/delete calendar events and todos, add ideas (auto-enrichment triggered), add notes (auto-classification triggered), add recap items, and delete ideas and notes.
- The AI response loop runs up to 6 rounds, processing all tool calls before generating a final reply.
- Conversation history is persisted across sessions.

**Smart Add overlay (`+` button)**
- Accepts **text, images, audio (in-app recording or uploaded file), and text/PDF files** (all ≤ 25 MB).
- A single message can contain **multiple unrelated items**; GPT splits and classifies each one independently.
  - Example: `"提醒我明天早上9點開FRC會議，然後找個時間開始練習電繪。喔對了，昨天我寫完FSLib了"` → Calendar event + Todo + Note.
- Calendar events carry full **year and month** fields — events for dates in future months (e.g. "明年3月15號") land on the correct month, not the current one.
- Attachments: tap 📎 to pick images, audio files (.mp3/.m4a/.wav/.ogg), plain text or PDF; tap 🎤 to record directly.
  - Images are encoded and sent to GPT-4o-mini vision.
  - Audio is transcribed via OpenAI Whisper before classification.
  - Text/PDF content is extracted and prepended to the classification prompt.
- Classified ideas are immediately routed through AI enrichment (summary + resource links); classified notes are immediately routed through AI category classification.
- After saving, a silent summary chip lists all created items (e.g. "✓ 新增 1 行程、1 待辦、1 筆記").

**Idea page (靈感)**
- **紀錄靈感 tab** — Each new idea is immediately saved, then enriched by GPT (one-sentence core insight + 2–3 resource links). Tap a card to expand the AI panel. Links open in the system browser. Cards can be individually deleted (synced to DB).
- **探索資源 tab** — On page load (or "重新推薦" tap), the app sends your top 5 ideas to GPT and gets back 4–6 curated learning resources. Resources can be pinned; pinned items persist across sessions in their own DB table and appear at the top of the list.

**Note page (筆記)**
- **日期 tab** — Full-year calendar with month navigation and dot indicators on days that have notes. Tap a day to open a panel with a primary note editor (auto-saves on every keystroke). Eraser button clears both the text field and the DB row. Multiple notes can be added to one day via the "新增筆記" button with a category picker. All notes for the selected day are shown below the editor, expandable and individually deletable. Closing the panel (save icon) triggers background AI classification of the primary note into one of the user's categories.
- **分類 tab** — Category grid showing note count per category. Tap a category to see its notes in a scrollable list; notes are expandable and deletable. "新增筆記" adds a manually written note to the category. The trash icon on a category card prompts for confirmation then deletes the category and all its notes. "新增分類" opens a dialog to name the category and pick from 7 icons; colour is auto-assigned from a palette. After a new category is saved, GPT silently checks every 未分類 note in one batch call and moves any matches into the new category.

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
  static const openAiWebSearchModel = 'gpt-4o-mini-search-preview';
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
│   ├── note_item.dart        # NoteItem + NoteCategory
│   └── recap_item.dart       # RecapItem + Era enum
│
├── services/
│   ├── database_service.dart # SQLite singleton — all reads/writes
│   └── openai_service.dart   # OpenAI REST client — classify, chat, enrich, recommend, classify-note, batch-reclassify
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

State lives in `MyRoomShell` (`main.dart`) and is passed down as immutable lists / maps. Pages fire fine-grained callbacks (`onTodoAdded`, `onTodoToggled`, `onTodoDeleted`, `onEventAdded`, `onEventDeleted`, `onIdeaAdded`, `onIdeaDeleted`, `onNotesMutated`); the shell re-fetches the affected list from SQLite and calls `setState`. `NotePage` is an exception — it writes directly to the DB and only calls `onNotesMutated` so the shell can refresh the `_notes` dot-indicator map. No external state-management library is used.

### Persistence

`DatabaseService` is a lazy singleton wrapping `sqflite`. All tables are created together in `_onCreate` (schema **version 1**) — there is no `_onUpgrade` handler; the schema is fully defined in `_onCreate`. The DB file lives at the path returned by `getDatabasesPath()`. On cold start, `seedIfEmpty()` checks whether **both** the `todos` and `events` tables are empty: if both are empty it seeds everything; if only `events` is empty (e.g. after a migration wiped the table) it re-seeds events only, leaving existing todos intact.

**Tables:**

| Table | Purpose |
|-------|---------|
| `todos` | Tasks with category, color, done flag, `priority` (1 = highest … 4 = lowest), and `created_at` timestamp |
| `categories` | User-defined todo categories with `name` (UNIQUE) and `color` |
| `events` | Calendar events with full date fields: `start_year`, `start_month`, `start_day`, `start_hour`, `start_min`, `end_year`, `end_month`, `end_day`, `end_hour`, `end_min` |
| `ideas` | User ideas with optional `ai_summary` and `links` JSON columns |
| `notes` | Notes with `date_key`, `title`, `content`, and nullable `cat_id` (`NULL` = primary date note; `'undefined'` = unclassified). Multiple rows per `date_key` are allowed. |
| `note_categories` | User-created note categories with label, icon name, colour, and sort order. Four defaults are seeded on first launch. |
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

`OpenAIService` is a singleton making direct HTTPS calls to the OpenAI Chat Completions and Audio endpoints via the `http` package. It exposes eight operations:

| Method | Temp | Tokens | Purpose |
|--------|------|--------|---------|
| `classifyMultiInput` | 0.2 | 800 | Multi-modal multi-item classification — text + images + file text → `List<ClassificationResult>` |
| `transcribeAudio` | — | — | Sends audio bytes to Whisper (`whisper-1`) and returns the transcript |
| `chat` | 0.7 | 600 | Conversational assistant with tool-calling (9 CRUD tools, multi-round loop), live DB context, user self-intro, and AI instructions |
| `enrichIdea` | 0.5 | 300 | One-sentence insight + 2–3 links per idea |
| `fetchRecommendations` | — | 600 | 4–6 web-searched curated resources from top-5 ideas (`gpt-4o-mini-search-preview`) |
| `classifyNoteToCategory` | 0.2 | 50 | Assigns a single date note to the best-matching category when the day panel is closed |
| `findNotesMatchingCategory` | 0.2 | 200 | Batch-checks all 未分類 notes against a newly created category in one API call; returns matched note IDs |

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
| `file_picker` | ^8.1.1 | Pick images, audio files, and text/PDF files from device storage |
| `record` | ^6.0.0 | In-app microphone audio recording |
| `permission_handler` | ^11.3.1 | Microphone permission on Android / iOS |
| `pdfrx` | ^1.2.23 | PDF text extraction (pdfium-based, cross-platform) |

---

## Notes

- `lib/config.dart` is listed in `.gitignore`. If you clone the repo for the first time the file will not exist — create it manually as shown in the installation steps above.
- All UI copy is in Traditional Chinese (繁體中文); AI responses are also in Chinese.
- The `todos` table has `priority INTEGER NOT NULL DEFAULT 3` and `created_at INTEGER NOT NULL` columns. The `categories` table stores custom todo categories.
- The `events` table stores full year/month fields (`start_year`, `start_month`, `end_year`, `end_month`) so events can span across different months and years correctly.
- **Delete support**: calendar events have a trash icon in their detail sheet (confirm dialog before delete); todo items support swipe-left (confirm dialog before delete). All four delete methods (`deleteEvent`, `deleteTodo`, `deleteIdea`, `deleteNote`) return `Future<int>` (rows affected), so the AI chat can detect "item not found" without a pre-check query.
- The database schema is version 3. If you have an older DB file, delete it (located at the path printed by `getDatabasesPath()`) and relaunch to trigger a fresh `_onCreate`.
