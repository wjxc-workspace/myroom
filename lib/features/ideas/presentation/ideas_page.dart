import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_errors.dart';
import '../../../core/result.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/mr_card.dart';
import '../../../core/widgets/mr_skeleton.dart';
import '../../../shared/ai/domain/ai_resource.dart';
import '../../../shared/ai/domain/ai_service.dart';
import '../domain/idea.dart';
import '../domain/idea_repo.dart';
import '../domain/pinned_resource.dart';

enum IdeaSub { input, explore }

class IdeasPage extends StatelessWidget {
  const IdeasPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Page-local streams provided ABOVE the stateful body (mirrors RecapPage) so
    // the body's context can read them; repos come from AuthenticatedScope.
    return MultiProvider(
      providers: [
        StreamProvider<List<Idea>>(
          create: (c) => c.read<IdeaRepo>().watchIdeas(),
          initialData: const [],
          catchError: (c, e) {
            AppErrors.present(e);
            return const <Idea>[];
          },
        ),
        StreamProvider<List<PinnedResource>>(
          create: (c) => c.read<IdeaRepo>().watchPinnedResources(),
          initialData: const [],
          catchError: (c, e) {
            AppErrors.present(e);
            return const <PinnedResource>[];
          },
        ),
      ],
      child: const _IdeasView(),
    );
  }
}

class _IdeasView extends StatefulWidget {
  const _IdeasView();

  @override
  State<_IdeasView> createState() => _IdeasViewState();
}

class _IdeasViewState extends State<_IdeasView> {
  IdeaSub _sub = IdeaSub.input;
  final _draftCtrl = TextEditingController();
  bool _adding = false;
  final Set<String> _expandedIds = {};

  // Explore tab: AI recommendations fetched on demand (Phase 2).
  List<AiResource> _recommendations = [];
  bool _loadingRecs = false;

  @override
  void dispose() {
    _draftCtrl.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _addIdea() async {
    if (_draftCtrl.text.isEmpty || _adding) return;
    final text = _draftCtrl.text;
    _draftCtrl.clear();
    setState(() => _adding = true);
    try {
      await context.read<IdeaRepo>().add(text);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _deleteIdea(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
            Text('刪除靈感', style: AppText.body(size: 16, weight: FontWeight.w600)),
        content: Text('確定刪除這份靈感？', style: AppText.body(size: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                Text('取消', style: AppText.body(size: 14, color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '刪除',
              style: AppText.body(
                  size: 14, weight: FontWeight.w600, color: AppColors.rose),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _expandedIds.remove(id));
      await context.read<IdeaRepo>().delete(id);
    }
  }

  Future<void> _editIdea(Idea idea) async {
    final ctrl = TextEditingController(text: idea.text);
    final newText = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title:
            Text('編輯靈感', style: AppText.body(size: 16, weight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '更新你的靈感內容...',
            hintStyle: AppText.body(color: AppColors.muted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.dark),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          style: AppText.body(size: 14, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text('取消', style: AppText.body(size: 14, color: AppColors.muted)),
          ),
          TextButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isEmpty) return;
              Navigator.pop(ctx, t);
            },
            child: Text(
              '儲存',
              style: AppText.body(
                  size: 14, weight: FontWeight.w600, color: AppColors.dark),
            ),
          ),
        ],
      ),
    );
    if (newText != null && newText != idea.text && mounted) {
      await context.read<IdeaRepo>().updateText(idea.id, newText);
    }
  }

  Future<void> _unpin(String url) async {
    await context.read<IdeaRepo>().unpin(url);
  }

  /// Fetches AI recommendations from the latest ideas (AI_proxy.md §5).
  Future<void> _fetchRecs() async {
    if (_loadingRecs) return;
    final ideas = context.read<List<Idea>>();
    if (ideas.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('先記錄一些靈感，才能取得推薦',
                style: AppText.body(size: 13, color: Colors.white)),
            backgroundColor: AppColors.dark,
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    final texts = ideas.take(5).map((i) => i.text).toList();
    setState(() => _loadingRecs = true);
    final result = await context.read<AiService>().fetchRecommendations(texts);
    if (!mounted) return;
    setState(() {
      _loadingRecs = false;
      if (result is Ok<List<AiResource>>) _recommendations = result.value;
    });
  }

  Future<void> _pinAiResource(AiResource r) async {
    await context.read<IdeaRepo>().pin(PinnedResource(
          id: '',
          title: r.title,
          type: r.type,
          description: r.description,
          url: r.url,
          createdAt: DateTime.now(),
        ));
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Color _typeColor(String type) => switch (type) {
        '書籍' => AppColors.sage,
        '文章' => AppColors.blue,
        '工具' => AppColors.amber,
        '課程' => AppColors.rose,
        _ => AppColors.muted,
      };

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: IdeaSub.values.map((s) {
                final active = _sub == s;
                final labels = ['✦  記錄靈感', '⊹  探索資源'];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _sub = s),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: active ? AppColors.dark : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Center(
                        child: Text(
                          labels[s.index],
                          style: AppText.body(
                            size: 13,
                            weight: active ? FontWeight.w600 : FontWeight.w400,
                            color: active ? Colors.white : AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        Expanded(
          child: _sub == IdeaSub.input ? _buildInput() : _buildExplore(),
        ),
      ],
    );
  }

  // ── 記錄靈感 ──────────────────────────────────────────────────────────────────

  Widget _buildInput() {
    final ideas = context.watch<List<Idea>>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        MrCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Focus(
                onKeyEvent: (kIsWeb &&
                        defaultTargetPlatform != TargetPlatform.android &&
                        defaultTargetPlatform != TargetPlatform.iOS)
                    ? (FocusNode _, KeyEvent event) {
                        if (event is KeyDownEvent &&
                            (event.logicalKey == LogicalKeyboardKey.enter ||
                                event.logicalKey ==
                                    LogicalKeyboardKey.numpadEnter) &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          _addIdea();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      }
                    : null,
                child: TextField(
                  controller: _draftCtrl,
                  maxLines: 2,
                  scrollPadding: const EdgeInsets.only(bottom: 120.0),
                  decoration: InputDecoration(
                    hintText: '記下你的靈感...',
                    hintStyle: AppText.body(color: AppColors.muted),
                    border: InputBorder.none,
                  ),
                  style: AppText.body(size: 14, height: 1.55),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _adding ? null : _addIdea,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color:
                        _adding ? AppColors.dark.withOpacity(0.6) : AppColors.dark,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _adding
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text('新增',
                          style: AppText.body(
                              size: 13,
                              weight: FontWeight.w500,
                              color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
        ...ideas.asMap().entries.map((entry) {
          final i = entry.key;
          final idea = entry.value;
          final expanded = _expandedIds.contains(idea.id);
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: MrCard(
              onTap: () => setState(() {
                expanded
                    ? _expandedIds.remove(idea.id)
                    : _expandedIds.add(idea.id);
              }),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style:
                                AppText.body(size: 13, weight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(idea.text,
                            style: AppText.body(size: 14, height: 1.55)),
                      ),
                      const SizedBox(width: 8),
                      // Edit button — isolated from expand tap
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _editIdea(idea),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(LucideIcons.pencil,
                              size: 14, color: AppColors.muted),
                        ),
                      ),
                      // Delete button — isolated from expand tap
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _deleteIdea(idea.id),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(LucideIcons.trash2,
                              size: 14, color: AppColors.muted),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        expanded
                            ? LucideIcons.chevronUp
                            : LucideIcons.chevronDown,
                        size: 15,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 12),
                    _buildAiPanel(idea),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  /// AI enrichment is filled by the `enrichIdea` trigger. The client only
  /// renders whatever the trigger has written: a summary + links once ready, a
  /// subtle "分析中…" while processing, and otherwise nothing extra.
  Widget _buildAiPanel(Idea idea) {
    if (idea.aiSummary == null) {
      // Loading skeleton while the enrichIdea trigger generates the summary.
      if (idea.aiStatus == 'processing') {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.dark,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.sparkles,
                      size: 13, color: AppColors.amber.withOpacity(0.7)),
                  const SizedBox(width: 6),
                  Text('分析中…',
                      style: AppText.caption(
                          size: 12, color: Colors.white.withOpacity(0.7))),
                ],
              ),
              const SizedBox(height: 12),
              MrSkeletonLines(
                lines: 2,
                height: 10,
                baseColor: Colors.white.withOpacity(0.12),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(LucideIcons.sparkles, size: 13, color: AppColors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  idea.aiSummary!,
                  style: AppText.body(
                      size: 13,
                      color: Colors.white.withOpacity(0.9),
                      height: 1.6),
                ),
              ),
            ],
          ),
          if (idea.links.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 10),
            ...idea.links.map((link) => GestureDetector(
                  onTap: () => _launchUrl(link.url),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.link,
                            size: 12, color: AppColors.amber.withOpacity(0.7)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      link.title,
                                      style: AppText.body(
                                          size: 12,
                                          weight: FontWeight.w600,
                                          color: Colors.white.withOpacity(0.9)),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(LucideIcons.externalLink,
                                      size: 10,
                                      color: AppColors.amber.withOpacity(0.6)),
                                ],
                              ),
                              Text(
                                link.url,
                                style: AppText.caption(
                                    size: 11, color: AppColors.muted),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  // ── 探索資源 ──────────────────────────────────────────────────────────────────

  Widget _buildExplore() {
    final pinned = context.watch<List<PinnedResource>>();
    final pinnedUrls = pinned.map((p) => p.url).toSet();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        Text('推薦資源', style: AppText.display(size: 22, weight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text('根據你的靈感主題為你整理的相關資源', style: AppText.label(size: 12)),
        const SizedBox(height: 16),

        // Fetch button
        GestureDetector(
          onTap: _loadingRecs ? null : _fetchRecs,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _loadingRecs ? AppColors.dark.withOpacity(0.6) : AppColors.dark,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: _loadingRecs
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.sparkles,
                            size: 15, color: AppColors.amber),
                        const SizedBox(width: 8),
                        Text('取得 AI 推薦',
                            style: AppText.body(
                                size: 14,
                                weight: FontWeight.w600,
                                color: Colors.white)),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Pinned section
        if (pinned.isNotEmpty) ...[
          Text(
            '已釘選',
            style: AppText.caption(
                size: 11,
                weight: FontWeight.w600,
                color: AppColors.muted,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          ...pinned.map((r) => _buildResourceCard(r)),
          const SizedBox(height: 4),
          const Divider(color: AppColors.border, height: 24),
        ],

        // AI recommendations
        if (_recommendations.isNotEmpty) ...[
          Text(
            '推薦',
            style: AppText.caption(
                size: 11,
                weight: FontWeight.w600,
                color: AppColors.muted,
                letterSpacing: 0.8),
          ),
          const SizedBox(height: 8),
          ..._recommendations
              .map((r) => _buildRecCard(r, pinnedUrls.contains(r.url))),
        ] else if (!_loadingRecs) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  Icon(LucideIcons.sparkles,
                      size: 28, color: AppColors.muted.withOpacity(0.4)),
                  const SizedBox(height: 12),
                  Text(
                    '點擊上方按鈕，依你的靈感取得推薦',
                    style: AppText.label(size: 13, color: AppColors.muted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResourceCard(PinnedResource r) {
    return _resourceCard(
      title: r.title,
      type: r.type,
      description: r.description,
      url: r.url,
      isPinned: true,
      onPinToggle: () => _unpin(r.url),
    );
  }

  Widget _buildRecCard(AiResource r, bool isPinned) {
    return _resourceCard(
      title: r.title,
      type: r.type,
      description: r.description,
      url: r.url,
      isPinned: isPinned,
      onPinToggle: () => isPinned ? _unpin(r.url) : _pinAiResource(r),
    );
  }

  Widget _resourceCard({
    required String title,
    required String type,
    required String description,
    required String url,
    required bool isPinned,
    required VoidCallback onPinToggle,
  }) {
    final color = _typeColor(type);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: MrCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(LucideIcons.fileText, size: 22, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(title,
                            style: AppText.body(
                                size: 14, weight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(type,
                            style: AppText.caption(size: 10, color: color)),
                      ),
                      const SizedBox(width: 6),
                      // Pin / unpin toggle
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onPinToggle,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Icon(
                            isPinned
                                ? LucideIcons.bookmarkCheck
                                : LucideIcons.bookmark,
                            size: 15,
                            color: isPinned ? AppColors.amber : AppColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(description,
                      style: AppText.label(size: 12, color: AppColors.muted)),
                  if (url.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _launchUrl(url),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              url,
                              style: AppText.caption(
                                  size: 10,
                                  color: AppColors.blue.withOpacity(0.8)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(LucideIcons.externalLink,
                              size: 10, color: AppColors.blue.withOpacity(0.6)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
