/// ASC `appInfoLocalizations` 리소스 — 앱 자체의 로케일별 메타.
/// 버전과 무관. (vs `appStoreVersionLocalizations`는 버전별)
class AppInfoLocalization {
  AppInfoLocalization({
    required this.id,
    required this.locale,
    this.name,
    this.subtitle,
    this.privacyPolicyUrl,
    this.privacyPolicyText,
  });

  final String id;
  final String locale;
  final String? name;
  final String? subtitle;
  final String? privacyPolicyUrl;
  final String? privacyPolicyText;

  factory AppInfoLocalization.fromAscJson(Map<String, dynamic> json) {
    final attrs = (json['attributes'] as Map<String, dynamic>?) ?? const {};
    return AppInfoLocalization(
      id: json['id'] as String,
      locale: (attrs['locale'] as String?) ?? '',
      name: attrs['name'] as String?,
      subtitle: attrs['subtitle'] as String?,
      privacyPolicyUrl: attrs['privacyPolicyUrl'] as String?,
      privacyPolicyText: attrs['privacyPolicyText'] as String?,
    );
  }
}
