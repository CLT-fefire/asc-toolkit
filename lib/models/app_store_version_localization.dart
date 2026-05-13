class AppStoreVersionLocalization {
  AppStoreVersionLocalization({
    required this.id,
    required this.locale,
    this.whatsNew,
    this.description,
    this.keywords,
    this.promotionalText,
    this.supportUrl,
    this.marketingUrl,
  });

  final String id;
  final String locale;
  final String? whatsNew;
  final String? description;
  final String? keywords;
  final String? promotionalText;
  final String? supportUrl;
  final String? marketingUrl;

  factory AppStoreVersionLocalization.fromAscJson(Map<String, dynamic> json) {
    final attrs = (json['attributes'] as Map<String, dynamic>?) ?? const {};
    return AppStoreVersionLocalization(
      id: json['id'] as String,
      locale: (attrs['locale'] as String?) ?? '',
      whatsNew: attrs['whatsNew'] as String?,
      description: attrs['description'] as String?,
      keywords: attrs['keywords'] as String?,
      promotionalText: attrs['promotionalText'] as String?,
      supportUrl: attrs['supportUrl'] as String?,
      marketingUrl: attrs['marketingUrl'] as String?,
    );
  }
}
