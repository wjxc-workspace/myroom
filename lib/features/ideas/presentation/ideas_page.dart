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

  // Pinned section collapse: null = count-based default (≤2 expanded, >2
  // collapsed); a manual tap pins an explicit bool override.
  bool? _pinnedExpandedOverride;

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
      final result = await context.read<IdeaRepo>().add(text);
      if (result is Ok<String>) _expandedIds.add(result.value);
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

  /// Returns true on success so the animated card knows whether the row was
  /// actually removed (on failure it restores itself; the error banner shows).
  Future<bool> _unpin(String url) async {
    return await context.read<IdeaRepo>().unpin(url) is Ok;
  }

  Future<void> _reenrichIdea(Idea idea) async {
    setState(() => _expandedIds.add(idea.id));
    await context.read<IdeaRepo>().reenrich(idea.id);
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

  /// Returns true on success (see [_unpin]).
  Future<bool> _pinAiResource(AiResource r) async {
    final result = await context.read<IdeaRepo>().pin(PinnedResource(
          id: '',
          title: r.title,
          type: r.type,
          description: r.description,
          url: r.url,
          createdAt: DateTime.now(),
        ));
    return result is Ok;
  }

  Future<void> _launchUrl(String url) async {
    var raw = url.trim();
    if (raw.isEmpty) return;
    // AI results sometimes omit the scheme; default to https so the OS can
    // resolve a browser. (The AndroidManifest <queries> entry is what lets
    // Android 11+ see one at all.) Launch directly and surface failures rather
    // than gating on canLaunchUrl, which silently no-ops when it can't resolve.
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(raw)) {
      raw = 'https://$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('無法開啟連結',
                style: AppText.body(size: 13, color: Colors.white)),
            backgroundColor: AppColors.dark,
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

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
      physics: const AlwaysScrollableScrollPhysics(),
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
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _reenrichIdea(idea),
                        child: const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(LucideIcons.refreshCw,
                              size: 14, color: AppColors.muted),
                        ),
                      ),
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
    // Loading skeleton while the enrichIdea trigger (re)generates the summary]
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
    if (idea.aiSummary == null) return const SizedBox.shrink();

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
    // Default: expand ≤2 pinned, collapse when more; a manual tap overrides.
    final pinnedExpanded = _pinnedExpandedOverride ?? (pinned.length <= 2);
    // Drop already-pinned items so a resource never shows in both sections;
    // unpinning makes it reappear here automatically (no list mutation).
    final visibleRecs =
        _recommendations.where((r) => !pinnedUrls.contains(r.url)).toList();
    return RefreshIndicator(
      onRefresh: _fetchRecs,
      color: AppColors.dark,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('推薦資源',
                        style:
                            AppText.display(size: 22, weight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text('根據你的靈感主題為你整理的相關資源',
                        style: AppText.label(size: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _loadingRecs ? null : _fetchRecs,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _loadingRecs
                        ? AppColors.dark.withOpacity(0.6)
                        : AppColors.dark,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: _loadingRecs
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(LucideIcons.refreshCw,
                            size: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Pinned section — collapsible header (count + chevron).
          if (pinned.isNotEmpty) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  setState(() => _pinnedExpandedOverride = !pinnedExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text(
                      '已釘選 (${pinned.length})',
                      style: AppText.caption(
                          size: 11,
                          weight: FontWeight.w600,
                          color: AppColors.muted,
                          letterSpacing: 0.8),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: pinnedExpanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(LucideIcons.chevronDown,
                          size: 16, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (pinnedExpanded) ...pinned.map((r) => _buildResourceCard(r)),
            const SizedBox(height: 4),
            const Divider(color: AppColors.border, height: 24),
          ],

          // AI recommendations (already-pinned ones filtered out above).
          if (visibleRecs.isNotEmpty) ...[
            Text(
              '推薦',
              style: AppText.caption(
                  size: 11,
                  weight: FontWeight.w600,
                  color: AppColors.muted,
                  letterSpacing: 0.8),
            ),
            const SizedBox(height: 8),
            ...visibleRecs.map((r) => _buildRecCard(r)),
          ] else if (_recommendations.isEmpty && !_loadingRecs) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: [
                    Icon(LucideIcons.sparkles,
                        size: 28, color: AppColors.muted.withOpacity(0.4)),
                    const SizedBox(height: 12),
                    Text(
                      '點擊右上角重新整理，或下拉頁面取得推薦',
                      style: AppText.label(size: 13, color: AppColors.muted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResourceCard(PinnedResource r) => _AnimatedResourceCard(
        key: ValueKey('pin_${r.url}'),
        title: r.title,
        type: r.type,
        description: r.description,
        url: r.url,
        isPinned: true,
        onToggle: () => _unpin(r.url),
        onOpenUrl: () => _launchUrl(r.url),
      );

  Widget _buildRecCard(AiResource r) => _AnimatedResourceCard(
        key: ValueKey('rec_${r.url}'),
        title: r.title,
        type: r.type,
        description: r.description,
        url: r.url,
        isPinned: false,
        onToggle: () => _pinAiResource(r),
        onOpenUrl: () => _launchUrl(r.url),
      );
}

/// A resource card with two micro-interactions: the bookmark icon pops on tap,
/// then the card collapses + fades out before [onToggle] commits the pin/unpin
/// (so the move never happens under the user's finger). Shared by the pinned
/// and recommendation sections of the Explore tab.
class _AnimatedResourceCard extends StatefulWidget {
  const _AnimatedResourceCard({
    super.key,
    required this.title,
    required this.type,
    required this.description,
    required this.url,
    required this.isPinned,
    required this.onToggle,
    required this.onOpenUrl,
  });

  final String title;
  final String type;
  final String description;
  final String url;
  final bool isPinned;
  // Commits the pin/unpin AFTER the exit animation; returns true on success.
  final Future<bool> Function() onToggle;
  final VoidCallback onOpenUrl;

  @override
  State<_AnimatedResourceCard> createState() => _AnimatedResourceCardState();
}

class _AnimatedResourceCardState extends State<_AnimatedResourceCard>
    with TickerProviderStateMixin {
  late final AnimationController _popCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _pop = TweenSequence<double>([
    TweenSequenceItem(
      tween:
          Tween(begin: 1.0, end: 1.4).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween:
          Tween(begin: 1.4, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
      weight: 60,
    ),
  ]).animate(_popCtrl);

  // Exit: 1.0 = fully shown, 0.0 = collapsed + transparent.
  late final AnimationController _exitCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1.0,
  );

  bool _busy = false;

  @override
  void dispose() {
    _popCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleToggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    _popCtrl.forward(from: 0).ignore(); // pop the bookmark (runs concurrently)…
    await _exitCtrl.reverse(); // …while the card collapses + fades out
    if (!mounted) return;
    final ok = await widget.onToggle(); // commit pin/unpin
    if (!mounted) return;
    if (!ok) {
      // Commit failed (error banner already shown) — restore the card; on
      // success the parent rebuild simply drops it (the stream updates).
      setState(() => _busy = false);
      _exitCtrl.forward().ignore();
    }
  }

  Color _typeColor(String type) => switch (type) {
        '書籍' => AppColors.sage,
        '文章' => AppColors.blue,
        '工具' => AppColors.amber,
        '課程' => AppColors.rose,
        _ => AppColors.muted,
      };

  @override
  Widget build(BuildContext context) {
    final color = _typeColor(widget.type);
    // While exiting, show the post-toggle bookmark state for instant feedback.
    final showPinned = _busy ? !widget.isPinned : widget.isPinned;
    return SizeTransition(
      sizeFactor: _exitCtrl,
      axisAlignment: -1.0,
      child: FadeTransition(
        opacity: _exitCtrl,
        child: Padding(
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
                            child: Text(widget.title,
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
                            child: Text(widget.type,
                                style: AppText.caption(size: 10, color: color)),
                          ),
                          const SizedBox(width: 6),
                          // Pin / unpin toggle — animated.
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _busy ? null : _handleToggle,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 2),
                              child: ScaleTransition(
                                scale: _pop,
                                child: Icon(
                                  showPinned
                                      ? LucideIcons.bookmarkCheck
                                      : LucideIcons.bookmark,
                                  size: 15,
                                  color: showPinned
                                      ? AppColors.amber
                                      : AppColors.muted,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(widget.description,
                          style:
                              AppText.label(size: 12, color: AppColors.muted)),
                      if (widget.url.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: widget.onOpenUrl,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.url,
                                  style: AppText.caption(
                                      size: 10,
                                      color: AppColors.blue.withOpacity(0.8)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(LucideIcons.externalLink,
                                  size: 10,
                                  color: AppColors.blue.withOpacity(0.6)),
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
        ),
      ),
    );
  }
}
