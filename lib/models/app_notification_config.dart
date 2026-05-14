/// ASC `apps` 리소스의 App Store Server Notifications V2 설정.
/// 프로덕션 / 샌드박스 각각 URL + 버전(V1/V2) 분리.
class AppNotificationConfig {
  AppNotificationConfig({
    required this.appId,
    this.subscriptionStatusUrl,
    this.subscriptionStatusUrlVersion,
    this.subscriptionStatusUrlForSandbox,
    this.subscriptionStatusUrlVersionForSandbox,
  });

  final String appId;

  /// 프로덕션 알림 URL.
  final String? subscriptionStatusUrl;

  /// "V1" / "V2". 신규는 V2가 표준.
  final String? subscriptionStatusUrlVersion;

  final String? subscriptionStatusUrlForSandbox;
  final String? subscriptionStatusUrlVersionForSandbox;

  factory AppNotificationConfig.fromAscJson(Map<String, dynamic> json) {
    final attrs = (json['attributes'] as Map<String, dynamic>?) ?? const {};
    return AppNotificationConfig(
      appId: json['id'] as String,
      subscriptionStatusUrl: attrs['subscriptionStatusUrl'] as String?,
      subscriptionStatusUrlVersion:
          attrs['subscriptionStatusUrlVersion'] as String?,
      subscriptionStatusUrlForSandbox:
          attrs['subscriptionStatusUrlForSandbox'] as String?,
      subscriptionStatusUrlVersionForSandbox:
          attrs['subscriptionStatusUrlVersionForSandbox'] as String?,
    );
  }
}
