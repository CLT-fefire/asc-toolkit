/// 키워드 파일(.txt) 파싱 결과.
///
/// 한 파일에 여러 언어 헤더가 등장하며, 헤더는 콤마로 다중 언어를 묶을 수 있다.
/// 예) "영어, 베트남어, 인도네시아어" → 다음 줄 키워드가 en-US/vi/id 세 로케일에 모두 적용.
class ParsedKeywordsFile {
  ParsedKeywordsFile({
    required this.keywordsByLocale,
    required this.unknownHeaders,
  });

  /// ASC locale → 키워드 문자열(콤마 구분, 원본 형식 유지).
  final Map<String, String> keywordsByLocale;

  /// 매핑되지 않은 헤더 (그대로 보여줘서 사용자가 인지하도록).
  final List<String> unknownHeaders;

  /// 해당 locale에 대응하는 키워드. 없으면 null.
  String? keywordsFor(String locale) => keywordsByLocale[locale];

  bool get isEmpty => keywordsByLocale.isEmpty;
}
