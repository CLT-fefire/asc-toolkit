/// 디자인팀이 전달하는 스크린샷 폴더/파일명 → ASC 식별자 매핑.
///
/// ## 폴더 패턴
/// `{NN}_{LOCALE_CODE}(부가설명)?`
/// - 예: `01_KR`, `03_CH_S(간체)`, `04_CH_T(번체)`
///
/// ## 파일 패턴
/// `APPSTORE_*_{LOCALE}_{SIZE}_{NN}.{jpg|png|jpeg}`
/// - 예: `APPSTORE_STARSHIP_KR_6_9INCH_07.jpg`
/// - `NN` 은 ASC 등록 순서 (1부터)
const Map<String, String> kFolderToAscLocale = {
  'KR': 'ko',
  'EN': 'en-US',
  'CH_S': 'zh-Hans',
  'CH_T': 'zh-Hant',
  'VI': 'vi',
  'IN': 'id',
  'JP': 'ja',
};

/// 파일명 안 `_{SIZE}_` 토큰 → ASC `screenshotDisplayType` enum.
///
/// 디자인팀 현재 표준은 `6_9INCH` 단일이지만, 다른 사이즈도 들어오면 자동 분기.
const Map<String, String> kFilenameSizeToAscType = {
  '6_9INCH': 'APP_IPHONE_69',
  '6_7INCH': 'APP_IPHONE_67',
  '6_5INCH': 'APP_IPHONE_65',
  '6_1INCH': 'APP_IPHONE_61',
  '5_5INCH': 'APP_IPHONE_55',
  '13INCH': 'APP_IPAD_PRO_3GEN_129',
  '12_9INCH': 'APP_IPAD_PRO_129',
  '11INCH': 'APP_IPAD_PRO_3GEN_11',
};

/// 폴더명에서 locale code 추출 + ASC locale 반환.
///
/// - `01_KR` → `ko`
/// - `03_CH_S(간체)` → `zh-Hans`  (괄호 이후는 무시)
/// - 알 수 없으면 null
String? localeFromFolderName(String folderName) {
  // 앞쪽 숫자 prefix(`01_`) 제거
  var s = folderName.trim();
  final prefixMatch = RegExp(r'^\d+_').firstMatch(s);
  if (prefixMatch != null) {
    s = s.substring(prefixMatch.end);
  }
  // 괄호 이후 부가설명 제거
  final parenIndex = s.indexOf('(');
  if (parenIndex >= 0) {
    s = s.substring(0, parenIndex);
  }
  return kFolderToAscLocale[s.trim()];
}

/// 파일명에서 `_{SIZE}_` 토큰을 찾아 ASC display type 반환.
///
/// - `APPSTORE_STARSHIP_KR_6_9INCH_07.jpg` → `APP_IPHONE_69`
/// - 매칭 실패 시 null
String? displayTypeFromFileName(String fileName) {
  for (final entry in kFilenameSizeToAscType.entries) {
    if (fileName.contains('_${entry.key}_')) {
      return entry.value;
    }
  }
  return null;
}

/// 파일명 끝 `_NN.{ext}` 의 순번 추출.
///
/// - `APPSTORE_STARSHIP_KR_6_9INCH_07.jpg` → 7
/// - 매칭 실패 시 null
int? orderFromFileName(String fileName) {
  final match = RegExp(r'_(\d+)\.[A-Za-z]+$').firstMatch(fileName);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
