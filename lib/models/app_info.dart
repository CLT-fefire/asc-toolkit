/// ASC `appInfos` 리소스. 한 앱에 보통 1~2개 존재.
/// LIVE 상태의 AppInfo는 read-only, PREPARE_FOR_SUBMISSION 등은 편집 가능.
/// name/subtitle 같은 로케일별 필드는 별도 [AppInfoLocalization]로 분리됨.
/// 카테고리는 이 AppInfo의 `relationships`에 매핑.
class AppInfo {
  AppInfo({
    required this.id,
    required this.state,
    required this.primaryCategoryId,
    required this.secondaryCategoryId,
  });

  final String id;

  /// ASC `state` (신) 또는 `appStoreState` (구). 둘 중 응답에 있는 값.
  final String state;

  final String? primaryCategoryId;
  final String? secondaryCategoryId;

  /// 이름·부제·카테고리 등을 PATCH 가능한 state인지 판단.
  /// 가장 흔한 편집 가능 state는 `PREPARE_FOR_SUBMISSION`.
  /// `READY_FOR_DISTRIBUTION`(현재 출시중)은 read-only.
  bool get isEditable {
    const editableStates = {
      'PREPARE_FOR_SUBMISSION',
      'DEVELOPER_REJECTED',
      'REJECTED',
      'METADATA_REJECTED',
      'READY_FOR_REVIEW',
      'WAITING_FOR_REVIEW',
    };
    return editableStates.contains(state);
  }

  factory AppInfo.fromAscJson(Map<String, dynamic> json) {
    final attrs = (json['attributes'] as Map<String, dynamic>?) ?? const {};
    final relationships =
        (json['relationships'] as Map<String, dynamic>?) ?? const {};

    String? extractCategoryId(String key) {
      final node = relationships[key] as Map<String, dynamic>?;
      final data = node?['data'] as Map<String, dynamic>?;
      return data?['id'] as String?;
    }

    // ASC는 신/구 두 필드를 동시에 보내거나 한쪽만 보낼 수 있음.
    // state(신) 우선, 없으면 appStoreState(구)로 fallback.
    final state = (attrs['state'] as String?) ??
        (attrs['appStoreState'] as String?) ??
        '';

    return AppInfo(
      id: json['id'] as String,
      state: state,
      primaryCategoryId: extractCategoryId('primaryCategory'),
      secondaryCategoryId: extractCategoryId('secondaryCategory'),
    );
  }
}
