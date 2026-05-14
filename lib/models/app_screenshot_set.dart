/// ASC `appScreenshotSets` — 한 locale + displayType의 스크린샷 컨테이너.
class AppScreenshotSet {
  AppScreenshotSet({
    required this.id,
    required this.screenshotDisplayType,
  });

  final String id;

  /// ASC enum (예: `APP_IPHONE_69`)
  final String screenshotDisplayType;

  factory AppScreenshotSet.fromAscJson(Map<String, dynamic> json) {
    final attrs = (json['attributes'] as Map<String, dynamic>?) ?? const {};
    return AppScreenshotSet(
      id: json['id'] as String,
      screenshotDisplayType: (attrs['screenshotDisplayType'] as String?) ?? '',
    );
  }
}
