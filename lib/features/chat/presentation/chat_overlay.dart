import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/app_errors.dart';
import '../../../core/result.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/calendar/domain/event_repo.dart';
import '../../../features/calendar/domain/pending_event.dart';
import '../../../shared/ai/domain/ai_service.dart';
import '../domain/chat_message.dart';

/// AI Chat overlay — a pushed full-screen route (owns its own [Scaffold]).
///
/// Messages are held in memory only; the thread is fresh on every app launch.
/// Within a session, the OpenAI response ID is forwarded to the cloud function
/// so multi-turn context is preserved.
class ChatOverlay extends StatelessWidget {
  const ChatOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamProvider<List<PendingEvent>>(
      create: (c) => c.read<EventRepo>().watchPendingEvents(),
      initialData: const [],
      catchError: (c, e) {
        AppErrors.present(e);
        return const <PendingEvent>[];
      },
      child: const _ChatView(),
    );
  }
}

class _ChatView extends StatefulWidget {
  const _ChatView();

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  // In-memory thread — cleared on every app launch.
  final List<ChatMessage> _messages = [];
  // Carries the OpenAI response ID across turns so multi-turn context is
  // preserved within the session without persisting anything to Firestore.
  String? _previousResponseId;
  int _nextId = 0;
  final Map<String, (PendingEvent, String)> _handled = {};

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _confirmEvent(PendingEvent pending) async {
    setState(() => _handled[pending.id] = (pending, '已確認'));
    final repo = context.read<EventRepo>();
    await repo.add(pending.toCalendarEvent());
    await repo.deletePendingEvent(pending.id);
  }

  Future<void> _cancelEvent(PendingEvent pending) async {
    setState(() => _handled[pending.id] = (pending, '已取消'));
    await context.read<EventRepo>().deletePendingEvent(pending.id);
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    _inputCtrl.clear();

    // Optimistically show the user bubble immediately.
    setState(() {
      _messages.add(ChatMessage(
        id: '${_nextId++}',
        role: 'user',
        content: text,
        createdAt: DateTime.now(),
      ));
      _sending = true;
    });
    _scrollToBottom();

    final result = await context
        .read<AiService>()
        .chat(text, previousResponseId: _previousResponseId);

    if (!mounted) return;
    if (result case Ok(:final value)) {
      setState(() {
        _previousResponseId =
            value.responseId.isNotEmpty ? value.responseId : null;
        _messages.add(ChatMessage(
          id: '${_nextId++}',
          role: 'assistant',
          content: value.reply,
          createdAt: DateTime.now(),
        ));
      });
    }
    // Err: already surfaced by AiService via AppErrors.
    setState(() => _sending = false);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final activeEvents = context.watch<List<PendingEvent>>();
    final activeIds = {for (final e in activeEvents) e.id};
    // Events already handled (status set) that the stream has since removed.
    final doneCards = _handled.entries
        .where((entry) => !activeIds.contains(entry.key))
        .map((entry) => entry.value)
        .toList();
    // Active events (with possible status override) followed by done cards.
    final allCards = [
      ...activeEvents.map((e) => (e, _handled[e.id]?.$2)),
      ...doneCards,
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: AppColors.dark,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.sparkles,
                        size: 17, color: AppColors.amber),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Ask AI',
                          style: AppText.body(size: 15, weight: FontWeight.w600)),
                      Text('你的個人助理', style: AppText.caption(size: 11)),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(LucideIcons.x,
                          size: 16, color: AppColors.dark),
                    ),
                  ),
                ],
              ),
            ),

            // Messages
            Expanded(
              child: _messages.isEmpty && allCards.isEmpty && !_sending
                  ? const _EmptyState()
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      itemCount: _messages.length +
                          allCards.length +
                          (_sending ? 1 : 0),
                      itemBuilder: (_, idx) {
                        if (idx < _messages.length) {
                          return _Bubble(message: _messages[idx]);
                        }
                        final pi = idx - _messages.length;
                        if (pi < allCards.length) {
                          final (event, status) = allCards[pi];
                          return _PendingEventCard(
                            event: event,
                            status: status,
                            onConfirm: () => _confirmEvent(event),
                            onCancel: () => _cancelEvent(event),
                          );
                        }
                        return const _TypingBubble();
                      },
                    ),
            ),

            // Input row
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 12,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      maxLines: 3,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: '輸入訊息...',
                        hintStyle: AppText.body(color: AppColors.muted),
                        border: InputBorder.none,
                      ),
                      style: AppText.body(size: 14, height: 1.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _sending ? null : _send,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _sending
                            ? AppColors.dark.withOpacity(0.5)
                            : AppColors.dark,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(9),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(LucideIcons.send,
                              size: 15, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(LucideIcons.sparkles,
                  size: 24, color: AppColors.amber),
            ),
            const SizedBox(height: 16),
            Text(
              '你好！我是你的個人助理',
              textAlign: TextAlign.center,
              style: AppText.body(size: 15, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '你可以問我今天的優先事項、週計畫，或讓我幫你整理靈感。',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13, color: AppColors.muted, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown at the tail of the thread while the `chat` function is running.
class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
              boxShadow: [kCardShadow],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.muted),
                ),
                const SizedBox(width: 8),
                Text('思考中…',
                    style: AppText.body(size: 13, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? AppColors.dark : AppColors.card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: const [kCardShadow],
              ),
              child: isUser
                  ? Text(
                      message.content,
                      style: AppText.body(
                          size: 13, color: Colors.white, height: 1.65),
                    )
                  : MarkdownBody(
                      data: message.content,
                      softLineBreak: true,
                      styleSheet: MarkdownStyleSheet(
                        p: AppText.body(
                            size: 13, color: AppColors.dark, height: 1.65),
                        strong: AppText.body(
                            size: 13,
                            weight: FontWeight.w700,
                            color: AppColors.dark,
                            height: 1.65),
                        em: AppText.body(
                                size: 13, color: AppColors.dark, height: 1.65)
                            .copyWith(fontStyle: FontStyle.italic),
                        listBullet: AppText.body(
                            size: 13, color: AppColors.dark, height: 1.65),
                        h1: AppText.body(
                            size: 18,
                            weight: FontWeight.w700,
                            color: AppColors.dark),
                        h2: AppText.body(
                            size: 16,
                            weight: FontWeight.w600,
                            color: AppColors.dark),
                        h3: AppText.body(
                            size: 14,
                            weight: FontWeight.w600,
                            color: AppColors.dark),
                        code: AppText.body(size: 12, color: AppColors.dark)
                            .copyWith(backgroundColor: AppColors.border),
                        blockSpacing: 8,
                        listIndent: 20,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingEventCard extends StatelessWidget {
  const _PendingEventCard({
    required this.event,
    this.status,
    required this.onConfirm,
    required this.onCancel,
  });

  final PendingEvent event;
  final String? status;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  static String _fmt(DateTime dt) =>
      '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}  '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final e = event;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(color: AppColors.border),
                boxShadow: const [kCardShadow],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(LucideIcons.calendar,
                          size: 13, color: AppColors.muted),
                      const SizedBox(width: 5),
                      Text('建議新增行程',
                          style: AppText.caption(
                              size: 11, color: AppColors.muted)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(e.title,
                      style: AppText.body(
                          size: 14, weight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    '${_fmt(e.startTime)}  —  ${_fmt(e.endTime)}',
                    style: AppText.caption(size: 12, color: AppColors.muted),
                  ),
                  if (e.location != null && e.location!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(e.location!,
                        style: AppText.caption(
                            size: 12, color: AppColors.muted)),
                  ],
                  if (e.description != null && e.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(e.description!,
                        style: AppText.caption(
                            size: 12, color: AppColors.muted)),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: status != null
                        ? [
                            Text(status!,
                                style: AppText.caption(
                                    size: 13, color: AppColors.muted)),
                          ]
                        : [
                            GestureDetector(
                              onTap: onCancel,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('取消',
                                    style: AppText.caption(size: 13)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: onConfirm,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: AppColors.dark,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text('確認新增',
                                    style: AppText.caption(
                                        size: 13, color: Colors.white)),
                              ),
                            ),
                          ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
