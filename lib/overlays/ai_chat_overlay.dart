import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme.dart';
import '../services/database_service.dart';
import '../services/openai_service.dart';

class AIChatOverlay extends StatefulWidget {
  final VoidCallback onClose;

  const AIChatOverlay({super.key, required this.onClose});

  @override
  State<AIChatOverlay> createState() => _AIChatOverlayState();
}

class _ChatMsg {
  final bool isUser;
  final String text;
  const _ChatMsg({required this.isUser, required this.text});
}

class _AIChatOverlayState extends State<AIChatOverlay> with TickerProviderStateMixin {
  late AnimationController _enterCtrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  late List<AnimationController> _pulseCtls;
  final List<_ChatMsg> _msgs = [];
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _loading = false;
  bool _historyLoaded = false;
  String _selfIntro = '';
  String _aiInstructions = '';

  static const _greeting = '✦ 你好！我是你的個人助理。你可以問我今天的優先事項、週計畫，或讓我幫你整理靈感。';
  static const _suggestions = ['今天優先做什麼？', '幫我整理本週重點', '我的靈感有什麼共同主題？', '給我一個明天的計畫'];

  @override
  void initState() {
    super.initState();

    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _fade = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOut));
    _enterCtrl.forward();

    _pulseCtls = List.generate(
      3,
      (_) => AnimationController(vsync: this, duration: const Duration(milliseconds: 1200)),
    );

    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final (saved, profile) = await (
      DatabaseService.instance.getChatMessages(limit: 60),
      DatabaseService.instance.getUserProfile(),
    ).wait;
    if (!mounted) return;
    _selfIntro = profile.selfIntro;
    _aiInstructions = profile.aiInstructions;
    if (saved.isEmpty) {
      setState(() {
        _msgs.add(const _ChatMsg(isUser: false, text: _greeting));
        _historyLoaded = true;
      });
    } else {
      setState(() {
        _msgs.addAll(saved.map((m) => _ChatMsg(isUser: m.isUser, text: m.text)));
        _historyLoaded = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    for (final c in _pulseCtls) { c.dispose(); }
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _startPulse() {
    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) _pulseCtls[i].repeat();
      });
    }
  }

  void _stopPulse() {
    for (final c in _pulseCtls) {
      c.stop();
      c.reset();
    }
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

  Future<void> _send([String? preset]) async {
    final text = preset ?? _inputCtrl.text.trim();
    if (text.isEmpty || _loading) return;
    _inputCtrl.clear();
    setState(() {
      _msgs.add(_ChatMsg(isUser: true, text: text));
      _loading = true;
    });
    _startPulse();
    _scrollToBottom();

    // Last 20 turns (excluding the just-appended user msg), then re-add it at the end
    // so the final message in the API call is always the current user input.
    final historySlice = _msgs.length > 21
        ? _msgs.sublist(_msgs.length - 21, _msgs.length - 1)
        : _msgs.sublist(0, _msgs.length - 1);
    final history = [
      ...historySlice.map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text}),
      {'role': 'user', 'content': text},
    ];

    final context = await DatabaseService.instance.buildContextSummary();
    final reply   = await OpenAIService.instance.chat(
      history, context,
      selfIntro: _selfIntro,
      aiInstructions: _aiInstructions,
    );

    if (!mounted) return;

    await DatabaseService.instance.insertChatMessage(true, text);
    await DatabaseService.instance.insertChatMessage(false, reply);

    _stopPulse();
    setState(() {
      _loading = false;
      _msgs.add(_ChatMsg(isUser: false, text: reply));
    });
    _scrollToBottom();
  }

  void _close() {
    _enterCtrl.reverse().then((_) => widget.onClose());
  }

  @override
  Widget build(BuildContext context) {
    // Show suggestions only when it's the initial greeting (1 AI message, no user messages)
    final showSuggestions = _msgs.length == 1 && !_msgs.first.isUser;

    return Positioned.fill(
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Container(
            color: AppColors.bg,
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 52, 22, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: const BoxDecoration(color: AppColors.dark, shape: BoxShape.circle),
                        child: const Icon(LucideIcons.sparkles, size: 17, color: AppColors.amber),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ask AI', style: AppText.body(size: 15, weight: FontWeight.w600)),
                          Text('你的個人助理', style: AppText.caption(size: 11)),
                        ],
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _close,
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(LucideIcons.x, size: 16, color: AppColors.dark),
                        ),
                      ),
                    ],
                  ),
                ),

                // Messages
                Expanded(
                  child: !_historyLoaded
                      ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                      : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    itemCount: _msgs.length + (_loading ? 1 : 0) + (showSuggestions ? 1 : 0),
                    itemBuilder: (_, idx) {
                      // Suggestions row (after first greeting msg)
                      if (showSuggestions && idx == 1) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: _suggestions.map((s) => GestureDetector(
                              onTap: () => _send(s),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Text(s, style: AppText.body(size: 13, color: AppColors.dark)),
                              ),
                            )).toList(),
                          ),
                        );
                      }

                      final msgIdx = showSuggestions && idx > 1 ? idx - 1 : idx;

                      // Loading indicator
                      if (_loading && msgIdx >= _msgs.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(18),
                                    bottomLeft: Radius.circular(18),
                                    bottomRight: Radius.circular(18),
                                    topLeft: Radius.circular(4),
                                  ),
                                  boxShadow: const [kCardShadow],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(3, (i) => AnimatedBuilder(
                                    animation: _pulseCtls[i],
                                    builder: (_, __) {
                                      final t = _pulseCtls[i].value;
                                      final scale = 0.85 + 0.15 * sin(t * pi);
                                      final opacity = 0.3 + 0.7 * sin(t * pi);
                                      return Container(
                                        margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                                        child: Transform.scale(
                                          scale: scale,
                                          child: Opacity(
                                            opacity: opacity,
                                            child: Container(
                                              width: 6, height: 6,
                                              decoration: const BoxDecoration(
                                                color: AppColors.muted,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  )),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final msg = _msgs[msgIdx];
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: msg.isUser ? AppColors.dark : AppColors.card,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(18),
                                    topRight: const Radius.circular(18),
                                    bottomLeft: Radius.circular(msg.isUser ? 18 : 4),
                                    bottomRight: Radius.circular(msg.isUser ? 4 : 18),
                                  ),
                                  boxShadow: const [kCardShadow],
                                ),
                                child: Text(
                                  msg.text,
                                  style: AppText.body(
                                    size: 13,
                                    color: msg.isUser ? Colors.white : AppColors.dark,
                                    height: 1.65,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Input row
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 12, offset: Offset(0, 2))],
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputCtrl,
                          maxLines: 3,
                          minLines: 1,
                          decoration: InputDecoration(
                            hintText: '輸入訊息...',
                            hintStyle: AppText.body(color: AppColors.muted),
                            border: InputBorder.none,
                          ),
                          style: AppText.body(size: 14, height: 1.5),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _loading ? null : _send,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: _loading ? Colors.transparent : AppColors.dark,
                            borderRadius: BorderRadius.circular(12),
                            border: _loading ? Border.all(color: AppColors.border) : null,
                          ),
                          child: Icon(
                            LucideIcons.send,
                            size: 15,
                            color: _loading ? AppColors.muted : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
