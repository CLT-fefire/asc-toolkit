/// What's New 붙여넣기 텍스트 파싱 결과.
///
/// 입력 예시:
/// ```
/// 메타데이터
/// 국: 앱 안정성이 개선되었습니다.
/// 영: App stability has been improved.
/// 일: アプリの安定性が改善されました
/// 기타: App stability has been improved.
/// ```
///
/// - `국 / 영 / 일 / 중 / 베 / 인` 등 짧은 prefix 인식
/// - `기타 / etc` 는 wildcard — 명시되지 않은 모든 로케일에 적용
/// - 콜론(`:` 또는 `：`)이 없는 줄(`메타데이터` 같은 머리말)은 무시
class ParsedWhatsNew {
  ParsedWhatsNew({
    required this.whatsNewByLocale,
    required this.unknownPrefixes,
  });

  /// ASC locale → What's New 텍스트.
  final Map<String, String> whatsNewByLocale;

  /// 매핑되지 않은 prefix (그대로 보여서 사용자가 인지하도록).
  final List<String> unknownPrefixes;

  String? whatsNewFor(String locale) => whatsNewByLocale[locale];

  bool get isEmpty => whatsNewByLocale.isEmpty;
}
