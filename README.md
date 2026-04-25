# MyRoom

A personal productivity app built with Flutter. MyRoom combines a calendar, to-do list, idea capture, daily notes, and a life-recap board — all backed by a local SQLite database and an AI assistant powered by OpenAI GPT-4o-mini.

---

## Features

| Tab | Description |
|-----|-------------|
| **行事曆** Calendar | Weekly timeline view. Add events with specific times. |
| **待辦** To-Do | Task list with categories (工作, 學習, 個人, 健康) and a progress ring. |
| **靈感** Ideas | Masonry card board for quick thoughts and inspiration. |
| **筆記** Notes | Date-based and category-based note editor with a calendar picker. |
| **回顧** Recap | Past / present / future goal tracking with a visual timeline. |

**AI overlay (Ask AI)**
- Real-time chat with GPT-4o-mini, with full awareness of your current todos, events, notes, ideas, and goals.
- Conversation history is persisted across sessions.

**Smart Add overlay (`+` button)**
- Type anything in plain language; GPT classifies it and routes it to the right section automatically.
- Examples: `"明天下午三點開會"` → Calendar event + Todo. `"買牛奶"` → Todo. `"如果日記能自動分析情緒就好了"` → Idea.

---

## Requirements

- Flutter `≥ 3.41.6` / Dart `≥ 3.11.4`
- An [OpenAI API key](https://platform.openai.com/api-keys) (GPT-4o-mini access)
- Android or iOS device / emulator (SQLite is not supported on Flutter Web)

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
flutter run
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
│   ├── idea.dart             # Idea
│   └── recap_item.dart       # RecapItem + Era enum
│
├── services/
│   ├── database_service.dart # SQLite singleton — all reads/writes
│   └── openai_service.dart   # OpenAI REST client — classify + chat
│
├── data/
│   └── seed_data.dart        # Sample data inserted on first launch
│
├── pages/
│   ├── calendar_page.dart    # Weekly timeline + event form
│   ├── todo_page.dart        # Filtered task list + add form
│   ├── idea_page.dart        # Masonry idea cards
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

State lives in `MyRoomShell` (`main.dart`) and is passed down as immutable lists / maps. Pages fire fine-grained callbacks (`onTodoAdded`, `onTodoToggled`, `onEventAdded`, `onIdeaAdded`, `onNoteSaved`); the shell writes to SQLite and re-fetches the affected list, then calls `setState`. No external state-management library is used.

### Persistence

`DatabaseService` is a lazy singleton wrapping `sqflite`. All tables are created in `onCreate` (schema version 1). The DB file lives at the platform default path (`getDatabasesPath()`). On cold start, `seedIfEmpty()` checks whether the `todos` table is empty and inserts sample rows only on the very first run.

**Tables:** `todos`, `events`, `ideas`, `notes`, `recap_items`, `chat_messages`

### AI integration

`OpenAIService` is a singleton that makes direct HTTPS calls to the OpenAI Chat Completions endpoint via the `http` package.

- **Classification** (`classifyInput`) — temperature 0.2, `response_format: json_object`. Returns one of:
  `ClassifiedTodo` | `ClassifiedTodoWithTime` | `ClassifiedIdea` | `ClassifiedNote` | `ClassifiedRecap` | `ClassificationError`

- **Chat** (`chat`) — temperature 0.7, max 600 tokens. The system message includes a live context summary built from the database (todos, this week's events, recent 7-day notes, ideas, active goals).

### Error handling

| Failure | Behaviour |
|---------|-----------|
| Network unavailable | `ClassificationError` returned; raw text saved as a note for the day |
| OpenAI 4xx / 5xx | Non-200 response throws; `ClassificationError` propagates |
| Malformed JSON from GPT | `FormatException` caught → `ClassificationError` |
| API key not set | `AssertionError` thrown at startup with a clear message |

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `google_fonts` | ^6.2.1 | Typography |
| `lucide_icons_flutter` | ^2.0.6 | Icon set |
| `sqflite` | ^2.4.1 | SQLite persistence |
| `path` | ^1.9.1 | Database file path helper |
| `http` | ^1.2.2 | OpenAI REST calls |

---

## Notes

- `lib/config.dart` is listed in `.gitignore`. If you clone the repo for the first time the file will not exist — create it manually as shown in the installation steps above.
- The app targets Android and iOS. Windows support is present (via the `windows/` directory) but SQLite on desktop may require additional setup.
- All UI copy is in Traditional Chinese (繁體中文); AI responses are also in Chinese.
