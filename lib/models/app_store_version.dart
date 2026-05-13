class AppStoreVersion {
  AppStoreVersion({
    required this.id,
    required this.versionString,
    required this.platform,
    required this.appStoreState,
  });

  final String id;
  final String versionString;
  final String platform;
  final String appStoreState;

  /// ASC가 PATCH를 허용하는 상태들. WAITING_FOR_REVIEW 이후는 거부될 수 있으므로
  /// 1차로는 가장 흔한 편집 가능 상태만 표시 + 그 외는 시도 후 서버 응답에 위임.
  bool get isLikelyEditable {
    const editable = {
      'PREPARE_FOR_SUBMISSION',
      'DEVELOPER_REJECTED',
      'REJECTED',
      'METADATA_REJECTED',
      'DEVELOPER_REMOVED_FROM_SALE',
      'WAITING_FOR_REVIEW',
    };
    return editable.contains(appStoreState);
  }

  factory AppStoreVersion.fromAscJson(Map<String, dynamic> json) {
    final attrs = (json['attributes'] as Map<String, dynamic>?) ?? const {};
    return AppStoreVersion(
      id: json['id'] as String,
      versionString: (attrs['versionString'] as String?) ?? '',
      platform: (attrs['platform'] as String?) ?? '',
      appStoreState: (attrs['appStoreState'] as String?) ?? '',
    );
  }
}
