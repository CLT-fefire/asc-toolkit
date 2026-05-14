/// ASC `appInfos` 리소스. 앱마다 보통 1개 존재 (EDITABLE 상태).
/// name/subtitle 같은 로케일별 필드는 별도 [AppInfoLocalization]로 분리됨.
/// 카테고리는 이 AppInfo의 `relationships`에 매핑.
class AppInfo {
  AppInfo({
    required this.id,
    required this.appStoreState,
    required this.primaryCategoryId,
    required this.secondaryCategoryId,
  });

  final String id;
  final String appStoreState;
  final String? primaryCategoryId;
  final String? secondaryCategoryId;

  factory AppInfo.fromAscJson(Map<String, dynamic> json) {
    final attrs = (json['attributes'] as Map<String, dynamic>?) ?? const {};
    final relationships =
        (json['relationships'] as Map<String, dynamic>?) ?? const {};

    String? extractCategoryId(String key) {
      final node = relationships[key] as Map<String, dynamic>?;
      final data = node?['data'] as Map<String, dynamic>?;
      return data?['id'] as String?;
    }

    return AppInfo(
      id: json['id'] as String,
      appStoreState: (attrs['appStoreState'] as String?) ?? '',
      primaryCategoryId: extractCategoryId('primaryCategory'),
      secondaryCategoryId: extractCategoryId('secondaryCategory'),
    );
  }
}
