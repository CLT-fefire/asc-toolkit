/// ASC `appStoreReviewDetails` 리소스. 버전별 1개.
/// 심사자에게 보내는 연락처·데모 계정·메모 정보.
class AppStoreReviewDetail {
  AppStoreReviewDetail({
    required this.id,
    this.contactFirstName,
    this.contactLastName,
    this.contactPhone,
    this.contactEmail,
    this.demoAccountName,
    this.demoAccountPassword,
    this.demoAccountRequired,
    this.notes,
  });

  final String id;
  final String? contactFirstName;
  final String? contactLastName;
  final String? contactPhone;
  final String? contactEmail;
  final String? demoAccountName;
  final String? demoAccountPassword;
  final bool? demoAccountRequired;
  final String? notes;

  factory AppStoreReviewDetail.fromAscJson(Map<String, dynamic> json) {
    final attrs = (json['attributes'] as Map<String, dynamic>?) ?? const {};
    return AppStoreReviewDetail(
      id: json['id'] as String,
      contactFirstName: attrs['contactFirstName'] as String?,
      contactLastName: attrs['contactLastName'] as String?,
      contactPhone: attrs['contactPhone'] as String?,
      contactEmail: attrs['contactEmail'] as String?,
      demoAccountName: attrs['demoAccountName'] as String?,
      demoAccountPassword: attrs['demoAccountPassword'] as String?,
      demoAccountRequired: attrs['demoAccountRequired'] as bool?,
      notes: attrs['notes'] as String?,
    );
  }
}
