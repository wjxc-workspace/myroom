import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/ai/domain/classification.dart';
import '../../notes/domain/note_category.dart';
import '../../todo/domain/todo_category.dart';

/// One selectable destination page in the edit sheet.
class _CatMeta {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const _CatMeta(this.key, this.label, this.icon, this.color);
}

const _kBaseCats = <_CatMeta>[
  _CatMeta('calendar', '行事曆', LucideIcons.calendar, AppColors.sage),
  _CatMeta('todo', '待辦', LucideIcons.check, AppColors.blue),
  _CatMeta('idea', '靈感', LucideIcons.lightbulb, AppColors.amber),
  _CatMeta('note', '札記', LucideIcons.fileText, AppColors.rose),
];
const _kRecapCat =
    _CatMeta('recap', '回顧', LucideIcons.bookOpen, AppColors.muted);

String _itemCatKey(ClassificationItem item) => switch (item) {
      ClassifiedTodoWithTime() => 'calendar',
      ClassifiedTodo() => 'todo',
      ClassifiedIdea() => 'idea',
      ClassifiedNote() => 'note',
      ClassifiedRecap() => 'recap',
    };

/// The user's edit choice: which pages to re-route to + optional sub-categories.
class SmartAddEditResult {
  final Set<String> cats;
  final String? todoCatId;
  final String? noteCatId;
  const SmartAddEditResult({
    required this.cats,
    required this.todoCatId,
    required this.noteCatId,
  });
}

/// Shows the non-fullscreen "這段輸入該被分類到？" sheet, pre-filled from the AI's
/// current [items]. Returns null if dismissed without confirming.
Future<SmartAddEditResult?> showSmartAddEditSheet(
  BuildContext context, {
  required List<ClassificationItem> items,
  required List<TodoCategory> todoCats,
  required List<NoteCategory> noteCats,
}) {
  return showModalBottomSheet<SmartAddEditResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _SmartAddEditSheet(
      items: items,
      todoCats: todoCats,
      noteCats: noteCats,
    ),
  );
}

class _SmartAddEditSheet extends StatefulWidget {
  const _SmartAddEditSheet({
    required this.items,
    required this.todoCats,
    required this.noteCats,
  });

  final List<ClassificationItem> items;
  final List<TodoCategory> todoCats;
  final List<NoteCategory> noteCats;

  @override
  State<_SmartAddEditSheet> createState() => _SmartAddEditSheetState();
}

class _SmartAddEditSheetState extends State<_SmartAddEditSheet> {
  late final Set<String> _selectedMainCats;
  late String _todoCatId;
  late String _noteCatId;

  @override
  void initState() {
    super.initState();
    _selectedMainCats = widget.items.map(_itemCatKey).toSet();
    // Pre-fill the sub-category pickers from the first todo / note the AI found.
    var todoCat = kUndefinedCategoryId;
    var noteCat = kUndefinedCategoryId;
    var foundTodo = false, foundNote = false;
    for (final i in widget.items) {
      if (!foundTodo && i is ClassifiedTodo) {
        todoCat = i.catId;
        foundTodo = true;
      }
      if (!foundNote && i is ClassifiedNote) {
        noteCat = i.noteCatId;
        foundNote = true;
      }
    }
    _todoCatId = todoCat;
    _noteCatId = noteCat;
  }

  bool get _showRecap => widget.items.any((i) => i is ClassifiedRecap);

  @override
  Widget build(BuildContext context) {
    final cats = [..._kBaseCats, if (_showRecap) _kRecapCat];
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: const [kCardShadow],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(LucideIcons.sparkles, size: 14, color: AppColors.amber),
                const SizedBox(width: 6),
                Text('這段輸入該被分類到？',
                    style: AppText.body(
                        size: 14,
                        weight: FontWeight.w600,
                        color: AppColors.dark)),
              ],
            ),
            const SizedBox(height: 4),
            Text('選擇後會請 AI 依你指定的頁面重新分類。',
                style: AppText.caption(size: 11, color: AppColors.muted)),
            const SizedBox(height: 14),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: cats
                  .map((c) => _mainCatChip(c.key, c.label, c.icon, c.color))
                  .toList(),
            ),

            if (_selectedMainCats.contains('todo') &&
                widget.todoCats.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('待辦分類',
                  style: AppText.caption(
                      size: 11, weight: FontWeight.w500, color: AppColors.muted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.todoCats
                    .map((c) => _subCatChip(c.id, c.label, c.color, isTodo: true))
                    .toList(),
              ),
            ],

            if (_selectedMainCats.contains('note') &&
                widget.noteCats.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('札記分類',
                  style: AppText.caption(
                      size: 11, weight: FontWeight.w500, color: AppColors.muted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.noteCats
                    .map((c) => _subCatChip(c.id, c.label, c.color, isTodo: false))
                    .toList(),
              ),
            ],

            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Center(
                        child: Text('取消',
                            style: AppText.body(
                                size: 14, color: AppColors.muted)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _selectedMainCats.isEmpty ? null : _confirm,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        color: _selectedMainCats.isEmpty
                            ? AppColors.dark.withOpacity(0.5)
                            : AppColors.dark,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text('重新分類',
                            style: AppText.body(
                                size: 14,
                                weight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirm() {
    Navigator.of(context).pop(SmartAddEditResult(
      cats: _selectedMainCats,
      todoCatId: _selectedMainCats.contains('todo') ? _todoCatId : null,
      noteCatId: _selectedMainCats.contains('note') ? _noteCatId : null,
    ));
  }

  Widget _mainCatChip(String key, String label, IconData icon, Color color) {
    final selected = _selectedMainCats.contains(key);
    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          _selectedMainCats.remove(key);
        } else {
          _selectedMainCats.add(key);
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: selected ? color : AppColors.muted),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppText.body(
                  size: 13,
                  weight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? color : AppColors.muted),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(LucideIcons.check, size: 11, color: color),
            ],
          ],
        ),
      ),
    );
  }

  Widget _subCatChip(String catId, String label, Color color,
      {required bool isTodo}) {
    final current = isTodo ? _todoCatId : _noteCatId;
    final selected = current == catId;
    return GestureDetector(
      onTap: () => setState(
          () => isTodo ? _todoCatId = catId : _noteCatId = catId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : AppColors.border),
        ),
        child: Text(
          label,
          style: AppText.caption(
              size: 12,
              weight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? color : AppColors.muted),
        ),
      ),
    );
  }
}
