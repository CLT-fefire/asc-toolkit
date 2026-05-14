/// 워드 문서에서 한 로케일 섹션을 파싱한 결과.
class ParsedLocaleSection {
  ParsedLocaleSection({
    required this.locale,
    required this.headerKeyword,
    this.name,
    this.subtitle,
    this.promotionalText,
    this.description,
  });

  /// ASC locale 코드 (예: `ko`, `en-US`, `ja`).
  final String locale;

  /// 워드 문서에 적힌 원본 헤더 (예: "한국어").
  final String headerKeyword;

  /// "이름: 부제"의 콜론 앞 (이름).
  final String? name;

  /// "이름: 부제"의 콜론 뒤 (부제).
  final String? subtitle;

  /// 부제 다음 ~ 구분선 이전의 짧은 본문 (프로모션 텍스트 후보).
  final String? promotionalText;

  /// 구분선 뒤의 본문 전체 (App Store 설명).
  final String? description;
}

/// 워드 문서 한 개를 파싱한 결과. 로케일별 섹션 + 매핑 안 된 헤더 목록.
class ParsedDocx {
  ParsedDocx({
    required this.sections,
    required this.unknownHeaders,
  });

  /// locale → 섹션.
  final Map<String, ParsedLocaleSection> sections;

  /// 매핑 사전에 없어서 무시된 헤더들 (사용자에게 알림).
  final List<String> unknownHeaders;

  bool get isEmpty => sections.isEmpty;
}
