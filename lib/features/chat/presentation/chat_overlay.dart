import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/app_errors.dart';
import '../../../core/result.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/ai/domain/ai_service.dart';
import '../../../shared/ai/domain/chat_action.dart';
import '../domain/chat_message.dart';
import '../domain/chat_repo.dart';

/// AI Chat overlay — a pushed full-screen route (owns its own [Scaffold]).
///
/// Phase 1 is READ-ONLY over Firestore: it streams the latest messages from
/// [ChatRepo.watchMessages] and renders them as bubbles. Sending is Phase 2
/// (a server-side Cloud Function appends messages); the input stays visible but
/// submitting only shows a "coming soon" notice and never writes to Firestore.
class ChatOverlay extends StatelessWidget {
  const ChatOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamProvider<List<ChatMessage>>(
      create: (c) => c.read<ChatRepo>().watchMessages(),
      initialData: const [],
      catchError: (c, e) {
        AppErrors.present(e);
        return const <ChatMessage>[];
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
  // Must match FirebaseChatRepo._pageSize: a full window means older history may
  // exist, a short one means the thread start has been reached.
  static const int _pageSize = 50;

  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  // Data changes the AI proposed on the last turn, awaiting the user's accept /
  // deny on the confirm card (held in memory only, like the Smart Add bar — no
  // pending Firestore doc). Cleared once applied or dismissed.
  List<ProposedAction> _pending = const [];
  bool _applying = false;

  // Pagination. The live stream only carries the latest [_pageSize] messages;
  // older pages fetched via [loadOlder] are accumulated here. We merge both into
  // [_byId] (the thread is append-only, so accumulating by id never gaps or
  // double-counts) and render the id map sorted by createdAt.
  final Map<String, ChatMessage> _byId = {};
  bool _hasMore = false;
  bool _initializedHasMore = false;
  bool _loadingOlder = false;
  String? _lastTailId;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Fetches the page of messages older than the oldest one currently shown and
  /// merges it in. Triggered by the "載入較早的訊息" control at the top.
  Future<void> _loadOlder(List<ChatMessage> current) async {
    if (_loadingOlder || current.isEmpty) return;
    setState(() => _loadingOlder = true);
    final older = await context.read<ChatRepo>().loadOlder(current.first.createdAt);
    if (!mounted) return;
    setState(() {
      for (final m in older) {
        _byId[m.id] = m;
      }
      if (older.length < _pageSize) _hasMore = false;
      _loadingOlder = false;
    });
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

  /// Sends the message through the `chat` Cloud Function. The function appends
  /// the user turn (shown immediately via the stream) and the assistant reply;
  /// while we await, a typing indicator shows and the input is disabled.
  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    FocusScope.of(context).unfocus();
    _inputCtrl.clear();
    // A new message supersedes any unconfirmed proposal from the previous turn.
    setState(() {
      _sending = true;
      _pending = const [];
    });
    final res = await context.read<AiService>().chat(text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (res is Ok<ChatTurn>) _pending = res.value.proposedActions;
    });
    if (_pending.isNotEmpty) _scrollToBottom();
  }

  /// Applies the proposed changes the user accepted on the confirm card. The
  /// server writes the data + an assistant result message (arrives via the
  /// stream); we just clear the card. On failure the card stays so they can retry.
  Future<void> _confirmPending() async {
    if (_pending.isEmpty || _applying) return;
    setState(() => _applying = true);
    final res = await context.read<AiService>().applyChatActions(_pending);
    if (!mounted) return;
    setState(() {
      _applying = false;
      if (res is Ok) _pending = const [];
    });
  }

  /// Discards the proposed changes without applying them.
  void _denyPending() => setState(() => _pending = const []);

  @override
  Widget build(BuildContext context) {
    final streamed = context.watch<List<ChatMessage>>();
    // Accumulate the live window into the id map (append-only → safe to merge).
    for (final m in streamed) {
      _byId[m.id] = m;
    }
    // Decide once, from the first non-empty window, whether older history exists.
    if (!_initializedHasMore && streamed.isNotEmpty) {
      _initializedHasMore = true;
      _hasMore = streamed.length >= _pageSize;
    }
    final messages = _byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Auto-scroll to the latest only when a NEW tail message arrives (a send or
    // an AI reply) — not when older history is prepended.
    final tailId = messages.isNotEmpty ? messages.last.id : null;
    if (tailId != _lastTailId) {
      _lastTailId = tailId;
      _scrollToBottom();
    } else if (_sending) {
      _scrollToBottom();
    }

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
              child: messages.isEmpty && !_sending && _pending.isEmpty
                  ? const _EmptyState()
                  : Builder(builder: (context) {
                      // index 0 = load-more control (only when older history may
                      // exist); then the messages; then a single trailing slot:
                      // the typing bubble while sending, otherwise the confirm
                      // card when the AI proposed changes awaiting confirmation.
                      final lead = _hasMore ? 1 : 0;
                      final hasTrailing = _sending || _pending.isNotEmpty;
                      return ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        itemCount: lead + messages.length + (hasTrailing ? 1 : 0),
                        itemBuilder: (_, idx) {
                          if (lead == 1 && idx == 0) {
                            return _LoadMore(
                              loading: _loadingOlder,
                              onTap: () => _loadOlder(messages),
                            );
                          }
                          final i = idx - lead;
                          if (i < messages.length) {
                            return _Bubble(message: messages[i]);
                          }
                          return _sending
                              ? const _TypingBubble()
                              : _ConfirmCard(
                                  actions: _pending,
                                  applying: _applying,
                                  onAccept: _confirmPending,
                                  onDeny: _denyPending,
                                );
                        },
                      );
                    }),
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

/// Top-of-thread control to fetch the previous page of messages.
class _LoadMore extends StatelessWidget {
  const _LoadMore({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.muted),
              )
            : GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text('載入較早的訊息',
                      style: AppText.caption(size: 12, color: AppColors.muted)),
                ),
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
              child: Text(
                message.content,
                style: AppText.body(
                  size: 13,
                  color: isUser ? Colors.white : AppColors.dark,
                  height: 1.65,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// AI-style bubble asking the user to approve the data changes the chat AI
/// proposed this turn. Accepting applies them server-side; denying discards them.
class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({
    required this.actions,
    required this.applying,
    required this.onAccept,
    required this.onDeny,
  });

  final List<ProposedAction> actions;
  final bool applying;
  final VoidCallback onAccept;
  final VoidCallback onDeny;

  // Builds e.g. "新增 1 項行程、刪除 2 項待辦" from the proposed tool calls.
  String _summary() {
    const units = {
      'event': '行程',
      'todo': '待辦',
      'idea': '靈感',
      'note': '札記',
      'recap': '回顧',
    };
    final adds = <String, int>{};
    final dels = <String, int>{};
    for (final a in actions) {
      final isAdd = a.name.startsWith('add_');
      final key = a.name.replaceFirst(RegExp(r'^(add|delete)_'), '');
      final unit = units[key] ?? key;
      final bucket = isAdd ? adds : dels;
      bucket[unit] = (bucket[unit] ?? 0) + 1;
    }
    String join(Map<String, int> m) =>
        m.entries.map((e) => '${e.value} 項${e.key}').join('、');
    return [
      if (adds.isNotEmpty) '新增${join(adds)}',
      if (dels.isNotEmpty) '刪除${join(dels)}',
    ].join('、');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '允許 MyRoom 助理${_summary()}嗎？',
                    style: AppText.body(
                        size: 13, color: AppColors.dark, height: 1.6),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _ConfirmButton(
                        label: '允許',
                        filled: true,
                        loading: applying,
                        onTap: applying ? null : onAccept,
                      ),
                      const SizedBox(width: 8),
                      _ConfirmButton(
                        label: '拒絕',
                        filled: false,
                        loading: false,
                        onTap: applying ? null : onDeny,
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

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.label,
    required this.filled,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: filled ? AppColors.dark : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: filled ? null : Border.all(color: AppColors.border),
        ),
        child: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(
                label,
                style: AppText.body(
                  size: 13,
                  weight: FontWeight.w600,
                  color: filled ? Colors.white : AppColors.dark,
                ),
              ),
      ),
    );
  }
}
