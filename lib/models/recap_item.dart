enum Era { past, now, future }

class RecapItem {
  final String id;
  final Era era;
  final String title;
  final String? completedDate;
  final String? targetDate;
  final String desc;
  final String? noteLink; // 'diary' | 'note'

  const RecapItem({
    required this.id,
    required this.era,
    required this.title,
    this.completedDate,
    this.targetDate,
    required this.desc,
    this.noteLink,
  });

  String get displayDate => completedDate ?? targetDate ?? '';
}
