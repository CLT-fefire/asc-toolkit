/// 워드 문서의 언어 헤더(예: "한국어", "영어") → ASC locale 코드 매핑.
///
/// 매핑이 없으면 null 반환. 새 언어가 들어오면 이 표만 갱신.
const Map<String, String> _docxLocaleMap = {
  // ---- 한국어 표기 ----
  '한국어': 'ko',
  '영어': 'en-US',
  '중국어 (간체)': 'zh-Hans',
  '중국어(간체)': 'zh-Hans',
  '중국어 간체': 'zh-Hans',
  '간체': 'zh-Hans',
  '중국어 (번체)': 'zh-Hant',
  '중국어(번체)': 'zh-Hant',
  '중국어 번체': 'zh-Hant',
  '번체': 'zh-Hant',
  '베트남어': 'vi',
  '인니어': 'id',
  '인도네시아어': 'id',
  '일본어': 'ja',
  '스페인어': 'es-ES',
  '독일어': 'de-DE',
  '프랑스어': 'fr-FR',
  '포르투갈어': 'pt-PT',
  '러시아어': 'ru',
  '태국어': 'th',
  '아랍어': 'ar-SA',

  // ---- 영어 표기 (alt) ----
  'Korean': 'ko',
  'English': 'en-US',
  'Chinese (Simplified)': 'zh-Hans',
  'Chinese (Traditional)': 'zh-Hant',
  'Vietnamese': 'vi',
  'Indonesian': 'id',
  'Japanese': 'ja',
  'Spanish': 'es-ES',
  'German': 'de-DE',
  'French': 'fr-FR',
  'Portuguese': 'pt-PT',
  'Russian': 'ru',
  'Thai': 'th',
  'Arabic': 'ar-SA',
};

/// 워드 문서 헤더 라인이 알려진 언어 키워드인지 식별 후 ASC locale 반환.
/// 매핑 없으면 null.
String? localeFromHeader(String header) {
  final trimmed = header.trim();
  if (trimmed.isEmpty) return null;
  return _docxLocaleMap[trimmed];
}

/// 모든 알려진 언어 키워드 (header 매칭용).
Iterable<String> get knownLocaleKeywords => _docxLocaleMap.keys;
