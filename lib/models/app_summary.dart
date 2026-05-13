class AppSummary {
  AppSummary({
    required this.id,
    required this.name,
    required this.bundleId,
    required this.sku,
    required this.primaryLocale,
  });

  final String id;
  final String name;
  final String bundleId;
  final String sku;
  final String primaryLocale;

  factory AppSummary.fromAscJson(Map<String, dynamic> json) {
    final attrs = (json['attributes'] as Map<String, dynamic>?) ?? const {};
    return AppSummary(
      id: json['id'] as String,
      name: (attrs['name'] as String?) ?? '',
      bundleId: (attrs['bundleId'] as String?) ?? '',
      sku: (attrs['sku'] as String?) ?? '',
      primaryLocale: (attrs['primaryLocale'] as String?) ?? '',
    );
  }
}
