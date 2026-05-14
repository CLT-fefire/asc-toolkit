/// ASC `appCategories` 리소스. 트리 구조 (parent ↔ children).
/// id 자체가 enum 식별자 (예: `GAMES`, `GAMES_ACTION`, `BUSINESS`).
class AppCategory {
  AppCategory({
    required this.id,
    required this.platforms,
    this.parentId,
  });

  final String id;
  final List<String> platforms;
  final String? parentId;

  bool get isTopLevel => parentId == null;

  factory AppCategory.fromAscJson(Map<String, dynamic> json) {
    final attrs = (json['attributes'] as Map<String, dynamic>?) ?? const {};
    final platforms = (attrs['platforms'] as List<dynamic>? ?? const [])
        .cast<String>()
        .toList(growable: false);
    final relationships =
        (json['relationships'] as Map<String, dynamic>?) ?? const {};
    final parentNode = relationships['parent'] as Map<String, dynamic>?;
    final parentData = parentNode?['data'] as Map<String, dynamic>?;
    return AppCategory(
      id: json['id'] as String,
      platforms: platforms,
      parentId: parentData?['id'] as String?,
    );
  }
}
