class IdeaLink {
  final String title;
  final String url;
  const IdeaLink({required this.title, required this.url});
}

class Idea {
  final int id;
  final String text;
  final String? aiSummary; // null = AI pending or failed
  final List<IdeaLink> links; // empty until AI responds

  const Idea({
    required this.id,
    required this.text,
    this.aiSummary,
    this.links = const [],
  });
}
