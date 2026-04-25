class AiResource {
  final String title;
  final String type; // 書籍 | 文章 | 工具 | 課程 | 網站
  final String desc;
  final String url;

  const AiResource({
    required this.title,
    required this.type,
    required this.desc,
    required this.url,
  });
}
